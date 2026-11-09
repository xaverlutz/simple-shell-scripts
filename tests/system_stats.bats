#!/usr/bin/env bats
#
# Tests for system_stats.sh: its parsers, formatting helpers, the --once
# snapshot and its options.
#
#   bats tests/
#
# The live dashboard never runs: each test sources the script with
# everything from the "# --- Main ---" marker on stripped, which leaves only
# function definitions and settings, then feeds the functions saved samples of
# what top, pmset, system_profiler and the sensor helper print (in
# tests/fixtures/system_stats/). For a whole snapshot, fake_macos_tools puts
# stand-ins for every macOS tool it reads on PATH (fixtures/system_stats/
# snapshot/). The option tests run the script itself, but only with options
# that make it exit before it reads anything. No terminal or macOS tool is
# needed, but zsh is, so the whole file is skipped where it isn't installed.

setup() {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

  TMP="$(mktemp -d)"
  FIX="$BATS_TEST_DIRNAME/fixtures/system_stats"
  # Same basename as the script, so `make coverage` credits its lines to it.
  LIB="$TMP/system_stats.sh"
  sed '/^# --- Main ---/,$d' "$BATS_TEST_DIRNAME/../system_stats.sh" > "$LIB"
  # Make sure the cut really happened, or a test could start the dashboard.
  grep -q '^collect_probe()' "$LIB"
  if grep -q '^live$' "$LIB"; then
    echo "the Main section of system_stats.sh was not stripped" >&2
    return 1
  fi
  export TMP FIX LIB NO_COLOR=1
}

teardown() {
  if [ -n "${TMP:-}" ]; then rm -rf "$TMP"; fi
}

# Run zsh code with the script's functions loaded. -f keeps the user's own
# zsh startup files out of it, so under `make coverage` the line tracer is
# sourced here explicitly.
zsh_run() {
  run zsh -f -c 'if [[ -n ${COV_ZSH-} ]]; then source "$COV_ZSH"; fi
source "$LIB" || exit 99
'"$1"
}

# Put stand-ins for the macOS tools system_stats reads first on PATH. Each is
# a link to fixtures/system_stats/snapshot/fake_tool.sh, which prints a saved
# sample for the tool it's called as.
fake_macos_tools() {
  local t
  mkdir -p "$TMP/bin"
  for t in sysctl vm_stat ioreg system_profiler pmset top scutil hostname \
           sw_vers uname xcode-select route networksetup ipconfig who netstat df ps; do
    ln -sf "$FIX/snapshot/fake_tool.sh" "$TMP/bin/$t"
  done
  export SNAPSHOT_DIR="$FIX/snapshot" PATH="$TMP/bin:$PATH"
}

# Draw one --once snapshot, with the sky pinned to day so it doesn't depend
# on the date.
snapshot() {
  fake_macos_tools
  zsh_run "apply_theme turtle; SKY_MODE=day; COLUMNS=${1:-120}; once"
}

# --- parse_top_line --------------------------------------------------------

@test "parse_top_line: reads processes, load and CPU usage from a top header" {
  zsh_run '
    local l
    while IFS= read -r l; do parse_top_line "$l" && break; done < "$FIX/top_header.txt"
    print -r -- "last=$l"
    print -r -- "procs=$S_PROCS running=$S_RUNNING threads=$S_THREADS"
    print -r -- "load=$S_LOAD1|$S_LOAD5|$S_LOAD15"
    print -r -- "cpu=$S_CPU_USER|$S_CPU_SYS|$S_CPU_IDLE"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "last=Disks: 17434586/814G read, 8451403/200G written." ]
  [ "${lines[1]}" = "procs=1083 running=3 threads=5026" ]
  [ "${lines[2]}" = "load=2.55|2.65|3.20" ]
  [ "${lines[3]}" = "cpu=8.72|14.9|77.18" ]
}

@test "parse_top_line: only the Disks line ends a sample" {
  zsh_run '
    parse_top_line "Processes: 1 total, 1 running, 0 sleeping, 9 threads"; print $?
    parse_top_line "CPU usage: 1.0% user, 2.0% sys, 97.0% idle"; print $?
    parse_top_line "Disks: 1/1G read, 1/1G written."; print $?
  '
  [ "$status" -eq 0 ]
  [ "${lines[*]}" = "1 1 0" ]
}

# --- unit_bytes --------------------------------------------------------------

@test "unit_bytes: converts sysctl swap sizes to bytes" {
  zsh_run '
    for v in 0.00M 1024.00M 2.50G 512.00K 3.00T; do unit_bytes $v; print -r -- "$v=$REPLY"; done
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0.00M=0" ]
  [ "${lines[1]}" = "1024.00M=1073741824" ]
  [ "${lines[2]}" = "2.50G=2684354560" ]
  [ "${lines[3]}" = "512.00K=524288" ]
  [ "${lines[4]}" = "3.00T=3298534883328" ]
}

@test "unit_bytes: works on the fields collect_dynamic cuts out of vm.swapusage" {
  zsh_run '
    line="total = 2048.00M  used = 1.25G  free = 0.75G  (encrypted)"
    unit_bytes ${${line#*total = }%% *}; print -r -- $REPLY
    unit_bytes ${${line#*used = }%% *}; print -r -- $REPLY
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2147483648" ]
  [ "${lines[1]}" = "1342177280" ]
}

# --- signed64 --------------------------------------------------------------

@test "signed64: turns ioreg's unsigned 64-bit currents back into negatives" {
  zsh_run '
    for v in 18446744073709547723 18446744073709551615 1520 0 ""; do signed64 "$v"; print -r -- "$REPLY"; done
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "-3893" ]
  [ "${lines[1]}" = "-1" ]
  [ "${lines[2]}" = "1520" ]
  [ "${lines[3]}" = "0" ]
  [ "${lines[4]}" = "0" ]
}

# --- parse_pmset_batt ------------------------------------------------------

@test "parse_pmset_batt: a laptop running on battery" {
  zsh_run '
    parse_pmset_batt "$(<$FIX/pmset_discharging.txt)"
    print -r -- "$S_POWER_SOURCE|$S_BATT_PCT|$S_BATT_STATE|$S_BATT_TIME"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "Battery Power|80|discharging|5:12 remaining" ]
}

@test "parse_pmset_batt: a laptop charging without a time estimate" {
  zsh_run '
    parse_pmset_batt "$(<$FIX/pmset_charging.txt)"
    print -r -- "$S_POWER_SOURCE|$S_BATT_PCT|$S_BATT_STATE|$S_BATT_TIME"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "AC Power|54|charging|(no estimate)" ]
}

@test "parse_pmset_batt: a desktop has a power source but no battery" {
  zsh_run '
    S_BATT_PCT=stale S_BATT_STATE=stale S_BATT_TIME=stale
    parse_pmset_batt "$(<$FIX/pmset_desktop.txt)"
    print -r -- "$S_POWER_SOURCE|$S_BATT_PCT|$S_BATT_STATE|$S_BATT_TIME"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "AC Power|||" ]
}

# --- parse_bluetooth -------------------------------------------------------

@test "parse_bluetooth: lists connected devices with their batteries" {
  zsh_run 'parse_bluetooth < "$FIX/bluetooth.txt"'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "$(printf 'Test AirPods Pro\tHeadphones\tcase=85 left=100 right=98')" ]
  [ "${lines[1]}" = "$(printf 'Magic Keyboard\tKeyboard\tbattery=64')" ]
}

@test "parse_bluetooth: keeps a connected device that reports no battery" {
  zsh_run 'parse_bluetooth < "$FIX/bluetooth.txt"'
  [ "$status" -eq 0 ]
  # bats drops the trailing empty field, so compare the raw line
  [ "$(printf '%s\n' "$output" | sed -n 3p)" = "$(printf 'Living Room Speaker\tSpeaker\t')" ]
}

@test "parse_bluetooth: ignores devices that are not connected" {
  # `|| false` because bash 3.2 does not fail a test on a false [[ ]]
  zsh_run 'parse_bluetooth < "$FIX/bluetooth.txt"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"MX Master"* ]] || false
  [[ "$output" != *"Old AirPods"* ]] || false
  [[ "$output" != *"Bluetooth Controller"* ]] || false
}

@test "parse_bluetooth: prints nothing when no device is connected" {
  zsh_run 'sed "/^      Connected:/,/^      Not Connected:/{/Not Connected/!d;}" "$FIX/bluetooth.txt" | parse_bluetooth'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- collect_probe ---------------------------------------------------------

# A stand-in for the compiled sensor helper that prints a saved sample.
fake_probe() {
  printf '#!/bin/sh\ncat "%s"\n' "$FIX/$1" > "$TMP/probe"
  chmod +x "$TMP/probe"
}

@test "collect_probe: groups HID temperatures and keeps each group's maximum" {
  fake_probe probe.txt
  zsh_run '
    PROBE=$TMP/probe
    collect_probe
    for g in CPU GPU DIE BOARD SSD BATTERY; do printf "%s=%.2f\n" $g ${(P)${:-S_TEMP_$g}}; done
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "CPU=52.75" ]
  [ "${lines[1]}" = "GPU=44.00" ]
  [ "${lines[2]}" = "DIE=47.50" ]
  [ "${lines[3]}" = "BOARD=38.00" ]
  [ "${lines[4]}" = "SSD=33.50" ]
  [ "${lines[5]}" = "BATTERY=30.25" ]
}

@test "collect_probe: averages groups with several sensors and skips tcal" {
  fake_probe probe.txt
  zsh_run '
    PROBE=$TMP/probe
    collect_probe
    printf "%s=%.3f\n" DIE_AVG $S_TEMP_DIE_AVG CPU_AVG $S_TEMP_CPU_AVG BOARD_AVG $S_TEMP_BOARD_AVG
    print -r -- "single=${S_TEMP_GPU_AVG-unset} other=${S_TEMP_OTHER-unset}"
  '
  [ "$status" -eq 0 ]
  # The 99.00 "PMU tcal" reading would dominate DIE if it were counted
  [ "${lines[0]}" = "DIE_AVG=44.375" ]
  [ "${lines[1]}" = "CPU_AVG=51.000" ]
  [ "${lines[2]}" = "BOARD_AVG=33.500" ]
  [ "${lines[3]}" = "single=unset other=unset" ]
}

@test "collect_probe: ignores SMC temperatures when HID sensors exist" {
  fake_probe probe.txt
  zsh_run '
    PROBE=$TMP/probe
    collect_probe
    print -r -- "$S_TEMP_CPU $S_TEMP_BATTERY"
  '
  [ "$status" -eq 0 ]
  # smc TC0P 88.00 and TB0T 77.00 must not win over the HID readings
  [ "$output" = "52.75 30.25" ]
}

@test "collect_probe: falls back to SMC temperatures on Intel Macs" {
  fake_probe probe_intel.txt
  zsh_run '
    PROBE=$TMP/probe
    collect_probe
    for g in CPU GPU BATTERY SSD BOARD; do print -r -- "$g=${(P)${:-S_TEMP_$g}}"; done
    print -r -- "fans=$S_FANS"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "CPU=64.25" ]
  [ "${lines[1]}" = "GPU=55.00" ]
  [ "${lines[2]}" = "BATTERY=31.00" ]
  [ "${lines[3]}" = "SSD=40.75" ]
  [ "${lines[4]}" = "BOARD=45.00" ]
  [ "${lines[5]}" = "fans=0 2160 2000 6200" ]
}

@test "collect_probe: lists fans and one load figure per core" {
  fake_probe probe.txt
  zsh_run '
    PROBE=$TMP/probe
    collect_probe
    print -r -- "$S_FANS"
    print -r -- "cores=$S_CORE_PCT"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0 1200 1200 5700" ]
  [ "${lines[1]}" = "1 1350 1200 6100" ]
  # The first sample has nothing to compare against yet
  [ "${lines[2]}" = "cores=0 0" ]
}

@test "collect_probe: without a helper it clears the old readings" {
  zsh_run '
    S_TEMP_CPU=50 S_FANS="0 1 2 3" PROBE=""
    collect_probe
    print -r -- "${S_TEMP_CPU-unset}|$S_FANS|$S_CORE_PCT"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "unset||" ]
}

# --- Formatting helpers ----------------------------------------------------

@test "human_bytes: picks a unit and keeps one decimal below 10" {
  zsh_run '
    for b in 0 999 1536 10240 1073741824 5368709120000; do human_bytes $b; print -r -- $REPLY; done
  '
  [ "$status" -eq 0 ]
  [ "${lines[*]}" = "0B 999B 1.5K 10K 1.0G 4.9T" ]
}

@test "human_duration: shows the two largest units" {
  zsh_run '
    for s in 0 59 600 3660 97200; do human_duration $s; print -r -- "$REPLY"; done
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0m" ]
  [ "${lines[1]}" = "0m" ]
  [ "${lines[2]}" = "10m" ]
  [ "${lines[3]}" = "1h 1m" ]
  [ "${lines[4]}" = "1d 3h" ]
}

@test "degrees: Celsius by default" {
  zsh_run 'degrees 41.4; print -r -- $REPLY; degrees 0; print -r -- $REPLY'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "41°C" ]
  [ "${lines[1]}" = "0°C" ]
}

@test "degrees: Fahrenheit with FAHRENHEIT=1" {
  zsh_run 'FAHRENHEIT=1; degrees 41; print -r -- $REPLY; degrees 100; print -r -- $REPLY'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "106°F" ]
  [ "${lines[1]}" = "212°F" ]
}

@test "fit: pads by visible width, not counting color codes" {
  zsh_run '
    fit $'"'"'\e[31mhot\e[0m'"'"' 6
    print -r -- "[$REPLY]" | cat -v
  '
  [ "$status" -eq 0 ]
  # 3 visible characters plus 3 spaces, with the escapes kept intact
  [ "$output" = "[^[[31mhot^[[0m   ]" ]
}

@test "fit: cuts long text with an ellipsis and drops its colors" {
  zsh_run '
    fit $'"'"'\e[32mabcdefgh\e[0m'"'"' 5; print -r -- "[$REPLY]"
    fit plain 8; print -r -- "[$REPLY]"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[abcd…]" ]
  [ "${lines[1]}" = "[plain   ]" ]
}

@test "human_rate: an ellipsis until there's a second sample, then bytes per second" {
  zsh_run 'human_rate ""; print -r -- $REPLY; human_rate 2048; print -r -- $REPLY'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "…" ]
  [ "${lines[1]}" = "2.0K/s" ]
}

@test "pct: rounds to a whole percent" {
  zsh_run 'pct 12.6; print -r -- $REPLY; pct; print -r -- $REPLY'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "13%" ]
  [ "${lines[1]}" = "0%" ]
}

@test "bar: fills by eighths and clamps to 0-100%" {
  zsh_run '
    apply_theme turtle
    bar 50 10; print -r -- "[$REPLY]"
    bar 55 10; print -r -- "[$REPLY]"
    bar 150 4; print -r -- "[$REPLY]"
    bar -5 4; print -r -- "[$REPLY]"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[█████░░░░░]" ]
  [ "${lines[1]}" = "[█████▌░░░░]" ]
  [ "${lines[2]}" = "[████]" ]
  [ "${lines[3]}" = "[░░░░]" ]
}

@test "spark: scales to the largest value and right-aligns short histories" {
  zsh_run '
    apply_theme turtle
    spark 5 0 PAL_HEAT 0 1 2 4 8; print -r -- "[$REPLY]"
    spark 3 0 PAL_HEAT 7; print -r -- "[$REPLY]"
    spark 2 0 PAL_HEAT 1 2 3 4; print -r -- "[$REPLY]"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[▁▂▃▅█]" ]
  [ "${lines[1]}" = "[  █]" ]
  # Only the newest values that fit are drawn.
  [ "${lines[2]}" = "[▆█]" ]
}

@test "spark2: a value above half height spills into the top row" {
  zsh_run '
    apply_theme turtle
    spark2 3 0 PAL_HEAT 1 8; print -rl -- "[$reply[1]]" "[$reply[2]]"
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[  █]" ]
  [ "${lines[1]}" = "[ ▂█]" ]
}

@test "sky_state: --sky overrides what the date and time would pick" {
  zsh_run '
    for SKY_MODE in day night snow fireworks; do
      sky_state
      print -r -- "$SKY_MODE night=$SKY_NIGHT fireworks=$SKY_FIREWORKS"
    done
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "day night=0 fireworks=0" ]
  [ "${lines[1]}" = "night night=1 fireworks=0" ]
  [ "${lines[3]}" = "fireworks night=1 fireworks=1" ]
}

# --- --once snapshot -------------------------------------------------------

@test "once: draws every panel from the macOS tools' output" {
  snapshot
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"Test Mac · MacBook Pro · macOS 15.1"* ]]
  local panel
  for panel in CPU MEMORY THERMALS POWER GPU NETWORK DISK SYSTEM BLUETOOTH PROCESSES; do
    [[ "$output" == *"$panel"* ]] || { echo "missing panel: $panel"; return 1; }
  done
  [[ "$output" == *"Apple M4 · 4 performance + 6 efficiency"* ]]
  [[ "$output" == *"load     2.55  2.65  3.20"* ]]
  [[ "$output" == *"8.9G / 16G"* ]]
  [[ "$output" == *"swap 512M of 2.0G"* ]]
  [[ "$output" == *"discharging · 5:12 remaining"* ]]
  [[ "$output" == *"health 95% · cycles 87 · 12.45V"* ]]
  [[ "$output" == *"Apple M4 · 10 cores"* ]]
  [[ "$output" == *"memory in use 768M"* ]]
  [[ "$output" == *"en0 · Wi-Fi · 192.0.2.23"* ]]
  [[ "$output" == *"393G / 926G"* ]]
  [[ "$output" == *"macOS 15.1 (24B83) · Darwin 24.1.0"* ]]
  [[ "$output" == *"1083 processes · 3 running · 5026 threads"* ]]
  [[ "$output" == *"Mac16,1 · 16G memory · 2 logged in"* ]]
  [[ "$output" == *"44.6    180M  WindowServer"* ]]
}

@test "once: points to the Command Line Tools when there's no sensor helper" {
  snapshot
  [ "$status" -eq 0 ]
  [[ "$output" == *"xcode-select --install"* ]]
}

@test "once: shows a battery device that only ioreg reports" {
  # The Magic Trackpad comes from ioreg, not system_profiler. Appending it
  # used to add a literal $'\n' instead of a newline, which merged it into
  # the device before and crashed bt_lines with a bad math expression.
  snapshot
  [ "$status" -eq 0 ]
  [[ "$output" != *"bad math expression"* ]]
  [[ "$output" == *"Living Room Speaker · speaker"* ]]
  [[ "$output" == *"│ Magic Trackpad "* ]]
}

# The widths of a snapshot's lines, one per distinct width. Counted in the
# script's own session, which sets a UTF-8 locale so ${#l} counts characters.
snapshot_widths() {
  fake_macos_tools
  zsh_run "apply_theme turtle; SKY_MODE=day; COLUMNS=$1"'
    for l in "${(@f)$(once)}"; do print ${#l}; done | sort -u'
}

@test "once: every line has the same width, never wider than the terminal" {
  # Wide terminals get two columns of panels at an odd width.
  snapshot_widths 120
  [ "$status" -eq 0 ]
  [ "$output" = "119" ]

  snapshot_widths 84
  [ "$status" -eq 0 ]
  [ "$output" = "84" ]
}

@test "once: a terminal narrower than 64 columns still gets 64" {
  snapshot_widths 40
  [ "$status" -eq 0 ]
  [ "$output" = "64" ]
}

# --- Options ---------------------------------------------------------------
# These run the script itself. Every case exits while parsing its options,
# before it checks for macOS or reads any tool.

@test "--help prints usage and exits 0" {
  run zsh "$BATS_TEST_DIRNAME/../system_stats.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"system_stats.sh --once"* ]]
}

@test "rejects an --interval outside 1-60 seconds" {
  run zsh "$BATS_TEST_DIRNAME/../system_stats.sh" --interval 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"--interval needs whole seconds from 1 to 60"* ]]

  run zsh "$BATS_TEST_DIRNAME/../system_stats.sh" --interval=abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"--interval needs whole seconds"* ]]
}

@test "rejects an unknown --theme or --sky" {
  run zsh "$BATS_TEST_DIRNAME/../system_stats.sh" --theme plaid
  [ "$status" -ne 0 ]
  [[ "$output" == *"--theme needs one of: turtle, ocean, sunset, mono"* ]]

  run zsh "$BATS_TEST_DIRNAME/../system_stats.sh" --sky rain
  [ "$status" -ne 0 ]
  [[ "$output" == *"--sky needs one of"* ]]
}

@test "rejects unknown options with the usage" {
  run zsh "$BATS_TEST_DIRNAME/../system_stats.sh" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
  [[ "$output" == *"USAGE"* ]]
}
