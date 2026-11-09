#!/bin/sh
#
# Stand-in for the macOS tools system_stats.sh reads. tests/system_stats.bats
# links it into a bin directory under each tool's name, so it can tell which
# tool it is from $0 and prints the saved sample for how it was called.
# $SNAPSHOT_DIR is this directory; the parser fixtures sit one level up.
#
# All values are made up; only the formats are copied from real output.

snap=$SNAPSHOT_DIR
fix=$SNAPSHOT_DIR/..

case ${0##*/} in
  sysctl)   # sysctl -n <key>
    awk -v k="$2" 'index($0, k ": ") == 1 { print substr($0, length(k) + 3) }' "$snap/sysctl.txt" ;;
  vm_stat)
    cat "$snap/vm_stat.txt" ;;
  ioreg)
    case "$*" in
      *IODeviceTree*)         cat "$snap/ioreg_cpus.txt" ;;
      *IOAccelerator*)        cat "$snap/ioreg_gpu.txt" ;;
      *AppleSmartBattery*)    cat "$snap/ioreg_battery.txt" ;;
      *IOBlockStorageDriver*) cat "$snap/ioreg_disk.txt" ;;
      *BatteryPercent*)       cat "$snap/ioreg_hid.txt" ;;
    esac ;;
  system_profiler)
    case "$*" in
      *SPBluetoothDataType*) cat "$fix/bluetooth.txt" ;;
      *)                     cat "$snap/system_profiler_hw.txt" ;;
    esac ;;
  pmset)
    case "$*" in
      *batt*)  cat "$fix/pmset_discharging.txt" ;;
      *therm*) cat "$snap/pmset_therm.txt" ;;
    esac ;;
  top)
    cat "$fix/top_header.txt" ;;
  scutil)   # scutil --get ComputerName
    echo "Test Mac" ;;
  hostname)
    echo "test-mac" ;;
  sw_vers)
    case "$1" in
      -productVersion) echo "15.1" ;;
      -buildVersion)   echo "24B83" ;;
    esac ;;
  uname)
    echo "24.1.0" ;;
  xcode-select)   # no Command Line Tools, so no sensor helper gets built
    exit 2 ;;
  route)
    cat "$snap/route.txt" ;;
  networksetup)
    cat "$snap/networksetup.txt" ;;
  ipconfig)   # ipconfig getifaddr <if>
    echo "192.0.2.23" ;;
  who)
    printf 'tester   console  Nov  9 08:00\ntester   ttys000  Nov  9 09:12\n' ;;
  netstat)
    cat "$snap/netstat.txt" ;;
  df)
    cat "$snap/df.txt" ;;
  ps)   # sorted by CPU (-r) or by memory (-m)
    case "$*" in
      *" -m") cat "$snap/ps_mem.txt" ;;
      *)      cat "$snap/ps_cpu.txt" ;;
    esac ;;
  *)
    echo "fake_tool.sh: no stand-in for ${0##*/}" >&2
    exit 1 ;;
esac
