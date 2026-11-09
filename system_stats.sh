#!/bin/zsh

# ---------------------------------------------------------------------------
# system_stats.sh — a live, animated dashboard of your Mac's vital signs
#
# Usage: ./system_stats.sh [--interval SECONDS] [--fahrenheit] [--once]
#
# Shows CPU (per core), GPU, memory, temperatures and fans, power and battery,
# network, disk, system facts and the busiest processes: everything macOS hands
# out without sudo. A turtle strolls along the top, faster the busier the CPU
# is, under the sun by day and the stars by night, and naps when the Mac idles.
#
# Temperatures, fans and per-core load come from a tiny helper compiled once
# with the Xcode Command Line Tools and cached in ~/Library/Caches.
#
# Keys: q quits, p pauses, f switches °C/°F. NO_COLOR=1 disables colors.
# ---------------------------------------------------------------------------

setopt extended_glob
zmodload zsh/datetime zsh/mathfunc

# In zsh, $0 inside a function is the *function* name (FUNCTION_ARGZERO is on by
# default), so capture the script name once here at top level.
SCRIPT_NAME=$(basename -- "$0")

# Measure text in characters rather than bytes, and keep decimal points as dots
# whatever the region is set to, so tool output parses the same everywhere.
unset LC_ALL
export LC_CTYPE=en_US.UTF-8 LC_NUMERIC=C

INTERVAL=2
ONCE=0
FAHRENHEIT=0

# --- Colors ----------------------------------------------------------------
# With a 256-color terminal, bars and sparklines get smooth gradients; with 8
# colors they step through green, yellow and red; with NO_COLOR they're plain.

C_RESET=""; C_BOLD=""; C_REV=""; C_NOREV=""
C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GRAY=""
C_FRAME=""; C_TRACK=""; C_GROUND=""
typeset -ga PAL_HEAT PAL_COOL PAL_WARM PAL_VIOLET
typeset -gA ACCENT INK

setup_colors() {
    local c
    local -a heat cool warm violet
    PAL_HEAT=('' '' '' '' '' '' '' '' '' '')
    PAL_COOL=("${PAL_HEAT[@]}") PAL_WARM=("${PAL_HEAT[@]}") PAL_VIOLET=("${PAL_HEAT[@]}")
    ACCENT=(cpu '' mem '' temp '' power '' gpu '' net '' disk '' sys '' proc '')
    INK=(o '' s '' h '' l '' e '' z '' c '' u '' m '' k '')
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] || return 0

    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_REV=$'\e[7m' C_NOREV=$'\e[27m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
    C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m' C_GRAY=$'\e[90m'

    if [[ $TERM == *256color* || $TERM == *(kitty|ghostty|alacritty|wezterm)* || -n ${COLORTERM:-} ]]; then
        fg() { REPLY=$'\e[38;5;'$1'm'; }
        heat=(41 77 113 149 185 221 215 209 203 197)
        cool=(24 25 31 32 38 39 45 51 87 123)
        warm=(94 130 136 172 178 214 220 221 227 229)
        violet=(54 55 91 92 128 129 135 165 171 177)
        PAL_HEAT=() PAL_COOL=() PAL_WARM=() PAL_VIOLET=()
        for c in $heat; do fg $c; PAL_HEAT+=("$REPLY"); done
        for c in $cool; do fg $c; PAL_COOL+=("$REPLY"); done
        for c in $warm; do fg $c; PAL_WARM+=("$REPLY"); done
        for c in $violet; do fg $c; PAL_VIOLET+=("$REPLY"); done
        fg 240; C_FRAME=$REPLY
        fg 237; C_TRACK=$REPLY
        fg 245; C_GRAY=$REPLY
        fg 71;  C_GROUND=$REPLY
        fg 75;  ACCENT[cpu]=$REPLY
        fg 141; ACCENT[mem]=$REPLY
        fg 209; ACCENT[temp]=$REPLY
        fg 220; ACCENT[power]=$REPLY
        fg 39;  ACCENT[gpu]=$REPLY
        fg 43;  ACCENT[net]=$REPLY
        fg 176; ACCENT[disk]=$REPLY
        fg 250; ACCENT[sys]=$REPLY
        fg 114; ACCENT[proc]=$REPLY
        fg 34;  INK[o]=$REPLY     # shell rim
        fg 28;  INK[s]=$REPLY     # shell plates
        fg 150; INK[h]=$REPLY     # head
        fg 107; INK[l]=$REPLY     # legs
        fg 244; INK[e]=$REPLY     # speed lines
        fg 153; INK[z]=$REPLY     # z's
        fg 255; INK[c]=$REPLY     # clouds
        fg 220; INK[u]=$REPLY     # sun
        fg 229; INK[m]=$REPLY     # moon
        fg 240; INK[k]=$REPLY     # stars
        unfunction fg
    else
        PAL_HEAT=($C_GREEN $C_GREEN $C_GREEN $C_GREEN $C_GREEN $C_YELLOW $C_YELLOW $C_YELLOW $C_RED $C_RED)
        PAL_COOL=($C_BLUE $C_BLUE $C_BLUE $C_BLUE $C_BLUE $C_CYAN $C_CYAN $C_CYAN $C_CYAN $C_CYAN)
        PAL_WARM=("${(@)PAL_HEAT/*/$C_YELLOW}")
        PAL_VIOLET=("${(@)PAL_HEAT/*/$C_MAGENTA}")
        C_FRAME=$C_GRAY C_TRACK=$C_GRAY C_GROUND=$C_GREEN
        ACCENT=(cpu $C_BLUE mem $C_MAGENTA temp $C_RED power $C_YELLOW gpu $C_CYAN net $C_GREEN disk $C_MAGENTA sys $C_RESET proc $C_GREEN)
        INK=(o $C_GREEN s $C_GREEN h $C_YELLOW l $C_GREEN e $C_GRAY z $C_CYAN c $C_RESET u $C_YELLOW m $C_YELLOW k $C_GRAY)
    fi
}
setup_colors

die() { printf '%s\n' "${C_RED}✖${C_RESET}  ${C_RED}$*${C_RESET}" >&2; exit 1; }

# --- Help ------------------------------------------------------------------
usage() {
    local me="$SCRIPT_NAME"
    printf '%s\n' "${C_BOLD}${me}${C_RESET} ${C_GRAY}— a live, animated dashboard of your Mac's vital signs${C_RESET}"
    printf '\n'
    printf '%s\n' "${C_BOLD}USAGE${C_RESET}"
    printf '  %s\n' "${me} [--interval SECONDS] [--fahrenheit]"
    printf '  %s\n' "${me} --once"
    printf '\n'
    printf '%s\n' "${C_BOLD}SHOWS${C_RESET}"
    printf '  %s\n' "CPU usage per core and load, GPU usage, memory and pressure, chip, SSD"
    printf '  %s\n' "and battery temperatures, fan speeds, battery and power draw, network and"
    printf '  %s\n' "disk throughput, system facts and the busiest processes. Everything macOS"
    printf '  %s\n' "reports without sudo. The turtle walks faster the busier your CPU gets,"
    printf '  %s\n' "and takes a nap when the Mac is idle."
    printf '\n'
    printf '%s\n' "${C_BOLD}OPTIONS${C_RESET}"
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-i, --interval N" "$C_RESET" "Seconds between samples, 1 to 60 (default: 2)."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-F, --fahrenheit" "$C_RESET" "Show temperatures in °F."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-1, --once"       "$C_RESET" "Print one snapshot and exit, no animation."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-h, --help"       "$C_RESET" "Show this help and exit."
    printf '\n'
    printf '%s\n' "${C_BOLD}KEYS${C_RESET}"
    printf '  %s%-18s%s %s\n' "$C_CYAN" "q"                "$C_RESET" "Quit (Ctrl-C works too)."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "p, space"         "$C_RESET" "Pause and resume."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "f"                "$C_RESET" "Switch between °C and °F."
    printf '\n'
    printf '%s\n' "${C_BOLD}EXAMPLES${C_RESET}"
    printf '  %s\n' "${me}                 ${C_GRAY}# live dashboard, a sample every 2 s${C_RESET}"
    printf '  %s\n' "${me} -i 5 -F         ${C_GRAY}# every 5 s, in Fahrenheit${C_RESET}"
    printf '  %s\n' "${me} --once | less   ${C_GRAY}# a single snapshot${C_RESET}"
    printf '\n'
    printf '%s\n' "${C_GRAY}Temperatures, fans and per-core load need the Xcode Command Line Tools"
    printf '%s\n' "(xcode-select --install) to build a small helper on first run."
    printf '%s\n' "Set NO_COLOR=1 to disable colors. Output that isn't a terminal gets --once.${C_RESET}"
}

# --- The sensor helper -----------------------------------------------------
# macOS has no command for temperatures, fans or per-core load, but all three
# are readable without sudo through IOKit. This C program asks for them and
# prints one fact per line:
#   core <n> <user> <system> <idle> <nice>   CPU ticks per logical core
#   temp <celsius> <sensor name>             HID temperature sensors
#   smc <key> <celsius>                      SMC temperatures (Intel Macs)
#   fan <n> <rpm> <min rpm> <max rpm>        fans, via the SMC

probe_source() {
    cat <<'EOF'
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdio.h>
#include <string.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
double IOHIDEventGetFloatValue(IOHIDEventRef, int32_t);

#define TEMPERATURE_EVENT 15

static void cores(void) {
    natural_t n;
    processor_info_array_t info;
    mach_msg_type_number_t count;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) != KERN_SUCCESS)
        return;
    processor_cpu_load_info_t load = (processor_cpu_load_info_t)info;
    for (natural_t i = 0; i < n; i++)
        printf("core %u %u %u %u %u\n", i, load[i].cpu_ticks[CPU_STATE_USER], load[i].cpu_ticks[CPU_STATE_SYSTEM],
               load[i].cpu_ticks[CPU_STATE_IDLE], load[i].cpu_ticks[CPU_STATE_NICE]);
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
}

static void hid_temperatures(void) {
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!system) return;
    int page = 0xff00, usage = 5;
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") }, *values[] = { p, u };
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(system, match);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services) {
        for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, TEMPERATURE_EVENT, 0, 0);
            if (name && event && CFGetTypeID(name) == CFStringGetTypeID()) {
                char buf[128];
                double t = IOHIDEventGetFloatValue(event, TEMPERATURE_EVENT << 16);
                if (CFStringGetCString(name, buf, sizeof buf, kCFStringEncodingUTF8) && t > 0 && t < 150)
                    printf("temp %.2f %s\n", t, buf);
            }
            if (event) CFRelease(event);
            if (name) CFRelease(name);
        }
        CFRelease(services);
    }
    CFRelease(match);
    CFRelease(p);
    CFRelease(u);
    CFRelease(system);
}

typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    char result, status, data8;
    uint32_t data32;
    unsigned char bytes[32];
} SMCKeyData;

static io_connect_t smc;

static int smc_read(const char *key, double *value) {
    SMCKeyData in = {0}, out = {0};
    size_t size = sizeof out;
    in.key = (uint32_t)key[0] << 24 | (uint32_t)key[1] << 16 | (uint32_t)key[2] << 8 | (uint32_t)key[3];
    in.data8 = 9; /* read key info */
    if (IOConnectCallStructMethod(smc, 2, &in, sizeof in, &out, &size) != KERN_SUCCESS || out.result)
        return 0;
    uint32_t type = out.keyInfo.dataType, length = out.keyInfo.dataSize;
    in.keyInfo.dataSize = length;
    in.data8 = 5; /* read bytes */
    memset(&out, 0, sizeof out);
    size = sizeof out;
    if (IOConnectCallStructMethod(smc, 2, &in, sizeof in, &out, &size) != KERN_SUCCESS || out.result)
        return 0;
    if (type == 'flt ' && length == 4) { float f; memcpy(&f, out.bytes, 4); *value = f; }
    else if (type == 'fpe2' && length == 2) *value = ((out.bytes[0] << 8) | out.bytes[1]) / 4.0;
    else if (type == 'sp78' && length == 2) *value = (int16_t)((out.bytes[0] << 8) | out.bytes[1]) / 256.0;
    else if (type == 'ui8 ') *value = out.bytes[0];
    else if (type == 'ui16') *value = (out.bytes[0] << 8) | out.bytes[1];
    else return 0;
    return 1;
}

static void smc_facts(void) {
    io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!service) return;
    kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &smc);
    IOObjectRelease(service);
    if (r != KERN_SUCCESS) return;

    double n = 0, rpm, lo, hi, t;
    char key[5];
    if (smc_read("FNum", &n))
        for (int i = 0; i < (int)n && i < 8; i++) {
            snprintf(key, sizeof key, "F%dAc", i);
            if (!smc_read(key, &rpm)) continue;
            snprintf(key, sizeof key, "F%dMn", i);
            if (!smc_read(key, &lo)) lo = 0;
            snprintf(key, sizeof key, "F%dMx", i);
            if (!smc_read(key, &hi)) hi = 0;
            printf("fan %d %.0f %.0f %.0f\n", i, rpm, lo, hi);
        }

    const char *temps[] = { "TC0P", "TC0D", "TC0E", "TCXC", "TG0P", "TG0D", "TB0T", "TH0a", "TH0x", "Tm0P", "TW0P" };
    for (size_t i = 0; i < sizeof temps / sizeof *temps; i++)
        if (smc_read(temps[i], &t) && t > 0 && t < 150)
            printf("smc %s %.2f\n", temps[i], t);
    IOServiceClose(smc);
}

int main(void) {
    cores();
    hid_temperatures();
    smc_facts();
    return 0;
}
EOF
}

# Build the helper once per version of its source and keep it in the cache.
# Without the Command Line Tools (or a working compiler) PROBE stays empty and
# the dashboard simply leaves those readings out.
PROBE=""
ensure_probe() {
    local src hash dir tmp
    # Without the tools, /usr/bin/cc would pop up an install dialog instead.
    xcode-select -p >/dev/null 2>&1 || return 1
    src=$(probe_source)
    hash=$(md5 -q -s "$src" 2>/dev/null) || return 1
    dir=${XDG_CACHE_HOME:-$HOME/Library/Caches}/simple-shell-scripts
    if [[ -x $dir/system_stats_probe-${hash[1,12]} ]]; then
        PROBE=$dir/system_stats_probe-${hash[1,12]}
        return 0
    fi
    mkdir -p -m 700 "$dir" 2>/dev/null || return 1
    tmp=$dir/.system_stats_probe.$$
    if print -r -- "$src" | cc -O2 -x c -o "$tmp" - -framework IOKit -framework CoreFoundation >/dev/null 2>&1; then
        rm -f "$dir"/system_stats_probe-*(N)
        mv -f "$tmp" "$dir/system_stats_probe-${hash[1,12]}" && PROBE=$dir/system_stats_probe-${hash[1,12]}
    else
        rm -f "$tmp"
        return 1
    fi
}

# --- Formatting helpers ----------------------------------------------------
# These return through REPLY instead of printing, so drawing a frame never
# forks a subshell.

human_bytes() {   # 1536 -> 1.5K
    local -F b=${1:-0}
    local -a units=(B K M G T P)
    local i=1
    while (( b >= 1000 && i < $#units )); do
        (( b /= 1024.0, i++ ))
    done
    if (( i == 1 )); then
        REPLY="$(( int(b) ))B"
    elif (( b < 10 )); then
        printf -v REPLY '%.1f%s' $b $units[i]
    else
        printf -v REPLY '%.0f%s' $b $units[i]
    fi
}

human_rate() {    # bytes per second, or empty while there's no second sample
    if [[ -z $1 ]]; then REPLY="…"; else human_bytes $1; REPLY+="/s"; fi
}

human_duration() {   # 97200 -> 1d 3h
    local s=${1:-0} d h m
    (( d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60 ))
    if (( d )); then REPLY="${d}d ${h}h"
    elif (( h )); then REPLY="${h}h ${m}m"
    else REPLY="${m}m"; fi
}

pct() { printf -v REPLY '%.0f%%' ${1:-0}; }

degrees() {   # celsius -> "41°C" or "106°F"
    if (( FAHRENHEIT )); then printf -v REPLY '%.0f°F' $(( ${1:-0} * 9 / 5.0 + 32 ))
    else printf -v REPLY '%.0f°C' ${1:-0}; fi
}

heat() {   # color for a percentage where high is bad
    local i=$(( int(${1:-0} / 10) + 1 ))
    (( i < 1 )) && i=1
    (( i > 10 )) && i=10
    REPLY=$PAL_HEAT[i]
}

BAR_FULL=${(l:300::█:)}
BAR_EMPTY=${(l:300::░:)}
EIGHTHS=('' ▏ ▎ ▍ ▌ ▋ ▊ ▉)
SPARKS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
typeset -gA GRADIENT

bar() {   # percent width [palette-name|color] -> a bar with eighth-block precision
    local -F v=${1:-0}
    local w=$2 ink=${3:-PAL_HEAT}
    (( v < 0 )) && v=0
    (( v > 100 )) && v=100
    local -F cells=$(( v * w / 100.0 ))
    local full=$(( int(cells) ))
    local part=$(( int((cells - full) * 8) )) rest=0 out='' i
    (( full < w )) && rest=$(( w - full - (part > 0 ? 1 : 0) ))
    if [[ $ink == PAL_* ]]; then
        # A gradient along the bar: each cell takes the color of its position
        local -a pal=("${(@P)ink}")
        local key=${ink}_$w
        if [[ -z ${GRADIENT[$key]} ]]; then
            for (( i = 0; i < w; i++ )); do GRADIENT[$key]+="${pal[i * $#pal / w + 1]}█"$'\n'; done
        fi
        local -a cell=("${(@f)GRADIENT[$key]}")
        out=${(j::)cell[1,full]}
        (( part && full < w )) && out+="${pal[full * $#pal / w + 1]}${EIGHTHS[part + 1]}"
    else
        out="${ink}${BAR_FULL[1,full]}"
        (( part && full < w )) && out+=${EIGHTHS[part + 1]}
    fi
    REPLY="${out}${C_RESET}${C_TRACK}${BAR_EMPTY[1,rest]}${C_RESET}"
}

spark() {   # width max palette values... -> sparkline of the newest values (max 0 = auto)
    local w=$1 pal=$3 v i out='' pad
    local -F top=$2
    shift 3
    local -a vals=("$@") ink=("${(@P)pal}")
    (( $#vals > w )) && vals=("${(@)vals[-w,-1]}")
    if (( top <= 0 )); then
        top=1
        for v in $vals; do (( v > top )) && top=$v; done
    fi
    for v in $vals; do
        i=$(( int(v / top * 7 + 0.5) ))
        (( i < 0 )) && i=0
        (( i > 7 )) && i=7
        out+="${ink[i * $#ink / 8 + 1]}${SPARKS[i+1]}"
    done
    pad=$(( w - $#vals ))
    REPLY="${(l:pad:: :)}${out}${C_RESET}"
}

spark2() {   # width max palette values... -> reply: a sparkline two rows tall
    local w=$1 pal=$3 v i c top_row='' bottom_row='' pad
    local -F top=$2
    shift 3
    local -a vals=("$@") ink=("${(@P)pal}")
    (( $#vals > w )) && vals=("${(@)vals[-w,-1]}")
    if (( top <= 0 )); then
        top=1
        for v in $vals; do (( v > top )) && top=$v; done
    fi
    for v in $vals; do
        i=$(( int(v / top * 16 + 0.5) ))
        (( i < 1 )) && i=1
        (( i > 16 )) && i=16
        c=${ink[(i - 1) * $#ink / 16 + 1]}
        if (( i > 8 )); then
            top_row+="${c}${SPARKS[i-8]}"
            bottom_row+="${c}█"
        else
            top_row+=' '
            bottom_row+="${c}${SPARKS[i]}"
        fi
    done
    pad=$(( w - $#vals ))
    reply=("${(l:pad:: :)}${top_row}${C_RESET}" "${(l:pad:: :)}${bottom_row}${C_RESET}")
}

fit() {   # text width -> text padded (or cut) to exactly width columns
    local t=$1 w=$2
    local plain=${t//$'\e'\[[0-9;]#m/}
    local n=${#plain}
    if (( n <= w )); then
        REPLY="$t${(l:w-n:: :)}"
    else
        REPLY="${plain[1,w-1]}…"
    fi
}

signed64() {   # ioreg prints negative currents as unsigned 64-bit numbers
    local v=$1
    if (( ${#v} == 20 )) && [[ $v == 1844674407* ]]; then
        REPLY=$(( 10#${v[11,20]} - 3709551616 ))
    else
        REPLY=${v:-0}
    fi
}

# --- Collecting ------------------------------------------------------------
# Every reading lands in an S_* variable. The live view runs the collector in
# the background and hands the values over through a small state file, so slow
# commands never stall the animation.

sc() { sysctl -n "$1" 2>/dev/null; }

unit_bytes() {   # 512.00M -> 536870912
    local n=${1%[KMGT]} i
    i=${${:-KMGT}[(i)${1[-1]}]}
    (( i > 4 )) && i=0
    REPLY=$(( int(${n:-0} * 1024.0 ** i) ))
}

net_kind() {   # en0 -> Wi-Fi
    networksetup -listallhardwareports 2>/dev/null | awk -v dev="$1" '
        /^Hardware Port:/ { port = substr($0, index($0, ":") + 2) }
        /^Device:/ && $2 == dev { print port; exit }'
}

collect_static() {
    local profile p e
    profile=$(system_profiler SPHardwareDataType SPDisplaysDataType 2>/dev/null)
    S_HOST=$(scutil --get ComputerName 2>/dev/null || hostname -s)
    S_MODEL_NAME=$(awk -F': ' '/Model Name/ { print $2; exit }' <<<"$profile")
    S_GPU_NAME=$(awk -F': ' '/Chipset Model/ { print $2; exit }' <<<"$profile")
    S_GPU_CORES=$(awk -F': ' '/Total Number of Cores/ { n = $2 } END { print n }' <<<"$profile")
    S_OS="macOS $(sw_vers -productVersion 2>/dev/null)"
    S_BUILD=$(sw_vers -buildVersion 2>/dev/null)
    S_KERNEL=$(uname -r)
    S_MODEL=$(sc hw.model)
    S_CHIP=$(sc machdep.cpu.brand_string)
    S_NCPU=$(sc hw.logicalcpu)
    S_MEM_TOTAL=$(sc hw.memsize)
    p=$(sc kern.boottime)
    S_BOOT=${${p#*sec = }%%,*}
    [[ $S_BOOT == <-> ]] && strftime -s S_BOOT_STR '%a %e %b %H:%M' $S_BOOT
    p=$(sc hw.perflevel0.logicalcpu) e=$(sc hw.perflevel1.logicalcpu)
    S_PERF_NAME=$(sc hw.perflevel0.name)
    if [[ -n $e ]]; then
        S_CORES="$p ${(L)S_PERF_NAME:-performance} + $e ${(L)$(sc hw.perflevel1.name):-efficiency}"
        # Which logical CPU sits in which cluster, e.g. EEEEEEPPPP
        S_CORE_TYPES=$(ioreg -l -p IODeviceTree -r -n cpus -w0 2>/dev/null | awk '
            /\+-o cpu[0-9]+@/ { if (id != "" && t != "") a[id] = t; id = ""; t = "" }
            /"cluster-type" = <"/ { t = $0; sub(/.*<"/, "", t); sub(/".*/, "", t) }
            /"logical-cpu-id" = / { id = $NF }
            END { if (id != "" && t != "") a[id] = t; for (i = 0; i in a; i++) printf "%s", a[i]; print "" }')
    else
        S_CORES="${S_NCPU} cores"
        S_CORE_TYPES=""
    fi
    if ensure_probe; then S_PROBE=ok; else S_PROBE=missing; fi
}

parse_top_line() {   # returns 0 on the last header line of a top sample
    local l=$1
    case $l in
        Processes:*)
            # Processes: 1085 total, 17 running, 1068 sleeping, 5041 threads
            S_PROCS=${${l#Processes: }%% total*}
            S_RUNNING=${${l#*total, }%% running*}
            S_THREADS=${${${l%% threads*}##*, }}
            ;;
        "Load Avg:"*)
            local -a a=(${=${${l#Load Avg: }//,/}})
            S_LOAD1=$a[1] S_LOAD5=$a[2] S_LOAD15=$a[3]
            ;;
        "CPU usage:"*)
            # CPU usage: 53.77% user, 14.18% sys, 32.4% idle
            S_CPU_USER=${${l#CPU usage: }%%\% user*}
            S_CPU_SYS=${${l#*user, }%%\% sys*}
            S_CPU_IDLE=${${l#*sys, }%%\% idle*}
            ;;
        Disks:*)
            return 0
            ;;
    esac
    return 1
}

typeset -gA PREV_CORE
collect_probe() {
    unset -m 'S_TEMP_*'
    S_FANS="" S_CORE_PCT=""
    [[ -n $PROBE && -x $PROBE ]] || return
    local line g i busy total
    local -a f cores
    local -A tmax tsum tn smax
    for line in "${(@f)$("$PROBE" 2>/dev/null)}"; do
        f=(${=line})
        case $f[1] in
            core)
                (( busy = f[3] + f[4] + f[6], total = busy + f[5], i = f[2] ))
                if [[ -n ${PREV_CORE[$i]} ]] && (( total > ${PREV_CORE[$i]#* } )); then
                    cores+=($(( int(100.0 * (busy - ${PREV_CORE[$i]% *}) / (total - ${PREV_CORE[$i]#* }) + 0.5) )))
                else
                    cores+=(0)
                fi
                PREV_CORE[$i]="$busy $total"
                ;;
            temp)
                case ${(L)${f[3,-1]}} in
                    *tcal*) continue ;;                       # calibration, not a reading
                    *gpu*) g=GPU ;;
                    *pacc*|*eacc*|*cpu*) g=CPU ;;
                    *tdie*|*soc*|*pmgr*|*ane*|*isp*) g=DIE ;;
                    *tdev*) g=BOARD ;;
                    *nand*|*ssd*) g=SSD ;;
                    *batt*|*gas\ gauge*) g=BATTERY ;;
                    *) g=OTHER ;;
                esac
                (( f[2] > ${tmax[$g]:-0} )) && tmax[$g]=$f[2]
                (( tsum[$g] += f[2], tn[$g] += 1 ))
                ;;
            smc)
                case $f[2] in
                    TC*) g=CPU ;; TG*) g=GPU ;; TB*) g=BATTERY ;; TH*) g=SSD ;; *) g=BOARD ;;
                esac
                (( f[3] > ${smax[$g]:-0} )) && smax[$g]=$f[3]
                ;;
            fan)
                S_FANS+="${f[2,5]}"$'\n'
                ;;
        esac
    done
    # Intel Macs have no HID sensors; their SMC keys stand in
    (( $#tmax )) || tmax=("${(@kv)smax}")
    for g in ${(k)tmax}; do
        typeset -g "S_TEMP_$g=$tmax[$g]"
        (( ${tn[$g]:-0} > 1 )) && typeset -g "S_TEMP_${g}_AVG=$(( tsum[$g] / tn[$g] ))"
    done
    S_CORE_PCT=${cores[*]}
    S_FANS=${S_FANS%$'\n'}
}

COLLECT_TICK=0
collect_dynamic() {
    local now=$EPOCHREALTIME line out k v
    local -F dt=0
    [[ -n $PREV_T ]] && dt=$(( now - PREV_T ))
    (( COLLECT_TICK++ ))
    strftime -s S_TIME '%H:%M:%S' $EPOCHSECONDS

    # Memory, counted the way Activity Monitor does
    local -A vm
    local page=16384
    for line in "${(@f)$(vm_stat 2>/dev/null)}"; do
        case $line in
            *"page size of "*) page=${${line##*page size of }%% *} ;;
            *:*) k=${line%%:*} v=${line##*:}; vm[$k]=${v//[^0-9]/} ;;
        esac
    done
    local anon=${vm[Anonymous pages]:-0} purge=${vm[Pages purgeable]:-0}
    S_MEM_APP=$(( (anon > purge ? anon - purge : 0) * page ))
    S_MEM_WIRED=$(( ${vm[Pages wired down]:-0} * page ))
    S_MEM_COMPRESSED=$(( ${vm[Pages occupied by compressor]:-0} * page ))
    S_MEM_CACHED=$(( (${vm[File-backed pages]:-0} + purge) * page ))
    S_MEM_USED=$(( S_MEM_APP + S_MEM_WIRED + S_MEM_COMPRESSED ))
    v=$(sc kern.memorystatus_level)
    S_MEM_PRESSURE=$(( ${v:-100} > 100 ? 0 : 100 - ${v:-100} ))
    line=$(sc vm.swapusage)   # total = 0.00M  used = 0.00M  free = 0.00M
    unit_bytes ${${line#*total = }%% *}; S_SWAP_TOTAL=$REPLY
    unit_bytes ${${line#*used = }%% *}; S_SWAP_USED=$REPLY

    # GPU
    out=$(ioreg -r -d 1 -c IOAccelerator -w0 2>/dev/null)
    S_GPU="" S_GPU_RENDER="" S_GPU_TILER="" S_GPU_MEM=""
    [[ $out =~ '"Device Utilization %"=([0-9]+)' ]] && S_GPU=$match[1]
    [[ $out =~ '"Renderer Utilization %"=([0-9]+)' ]] && S_GPU_RENDER=$match[1]
    [[ $out =~ '"Tiler Utilization %"=([0-9]+)' ]] && S_GPU_TILER=$match[1]
    [[ $out =~ '"In use system memory"=([0-9]+)' ]] && S_GPU_MEM=$match[1]

    # Battery and power
    out=$(pmset -g batt 2>/dev/null)
    S_POWER_SOURCE=${${out#*\'}%%\'*}
    S_BATT_PCT="" S_BATT_STATE="" S_BATT_TIME=""
    if [[ $out == *InternalBattery* ]]; then
        line=${${(f)out}[2]}
        local -a f=("${(@s:; :)${line#*$'\t'}}")
        S_BATT_PCT=${f[1]%\%}
        S_BATT_STATE=$f[2]
        S_BATT_TIME=${f[3]%% present*}
    fi
    out=$(ioreg -rn AppleSmartBattery -w0 2>/dev/null)
    S_BATT_CYCLES="" S_BATT_HEALTH="" S_BATT_VOLTS="" S_BATT_WATTS="" S_SYS_WATTS="" S_ADAPTER_WATTS=""
    if [[ -n $out ]]; then
        local design="" full="" mv="" ma=""
        [[ $out =~ '"CycleCount" = ([0-9]+)' ]] && S_BATT_CYCLES=$match[1]
        [[ $out =~ '"DesignCapacity" ?= ?([0-9]+)' ]] && design=$match[1]
        [[ $out =~ '"NominalChargeCapacity" ?= ?([0-9]+)' ]] && full=$match[1]
        [[ $out =~ '"Voltage" = ([0-9]+)' ]] && mv=$match[1]
        [[ $out =~ '"InstantAmperage" = ([0-9]+)' ]] && { signed64 $match[1]; ma=$REPLY; }
        [[ $out =~ '"SystemLoad"=([0-9]+)' ]] && S_SYS_WATTS=$(( match[1] / 1000.0 ))
        [[ $out == *'"ExternalConnected" = Yes'* && $out =~ '"Watts"=([0-9]+)' ]] && S_ADAPTER_WATTS=$match[1]
        (( design && full )) && S_BATT_HEALTH=$(( 100 * full / design ))
        [[ -n $mv ]] && S_BATT_VOLTS=$(( mv / 1000.0 ))
        [[ -n $mv && -n $ma ]] && S_BATT_WATTS=$(( mv * ma / 1000000.0 ))
    fi
    out=$(pmset -g therm 2>/dev/null)
    if [[ $out =~ 'CPU_Speed_Limit[^0-9]*([0-9]+)' ]] && (( match[1] < 100 )); then
        S_THERMAL="CPU limited to ${match[1]}%"
    elif [[ $out =~ '[Ww]arning [Ll]evel[^0-9]*([0-9]+)' ]] && (( match[1] > 0 )); then
        S_THERMAL="warning level ${match[1]}"
    else
        S_THERMAL="nominal"
    fi

    # Temperatures, fans and per-core load
    collect_probe

    # Network: the interface the default route goes out of. Slow-changing
    # facts are only refreshed every few samples.
    if (( COLLECT_TICK % 5 == 1 )); then
        v=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
        if [[ $v != "$S_NET_IF" ]]; then
            S_NET_IF=$v PREV_RX=""
            S_NET_KIND=$([[ -n $v ]] && net_kind $v)
        fi
        S_NET_IP=$([[ -n $v ]] && ipconfig getifaddr $v 2>/dev/null)
        S_USERS=${$(who 2>/dev/null | wc -l)//[^0-9]/}
    fi
    S_NET_RX="" S_NET_TX=""
    if [[ -n $S_NET_IF ]]; then
        line=$(netstat -ibn -I $S_NET_IF 2>/dev/null | awk '/<Link#/ { print $(NF-4), $(NF-1); exit }')
        S_NET_RX_TOTAL=${line% *} S_NET_TX_TOTAL=${line#* }
        if [[ -n $PREV_RX ]] && (( dt > 0 )); then
            S_NET_RX=$(( (S_NET_RX_TOTAL - PREV_RX) / dt ))
            S_NET_TX=$(( (S_NET_TX_TOTAL - PREV_TX) / dt ))
        fi
        PREV_RX=$S_NET_RX_TOTAL PREV_TX=$S_NET_TX_TOTAL
    fi

    # Disk space on the data volume, and I/O across every disk
    line=${${(f)"$(df -k /System/Volumes/Data 2>/dev/null || df -k / 2>/dev/null)"}[-1]}
    local -a d=(${=line})
    S_DISK_TOTAL=$(( ${d[2]:-0} * 1024 ))
    S_DISK_FREE=$(( ${d[4]:-0} * 1024 ))
    S_DISK_USED=$(( S_DISK_TOTAL - S_DISK_FREE ))
    line=$(ioreg -c IOBlockStorageDriver -r -w0 -k Statistics -d 1 2>/dev/null | awk -F'[=,}]' '
        { for (i = 1; i < NF; i++) {
              if ($i ~ /"Bytes \(Read\)"$/) r += $(i + 1)
              if ($i ~ /"Bytes \(Write\)"$/) w += $(i + 1) } }
        END { printf "%.0f %.0f\n", r, w }')
    S_DISK_READ_TOTAL=${line% *} S_DISK_WRITE_TOTAL=${line#* }
    S_DISK_READ="" S_DISK_WRITE=""
    if [[ -n $PREV_DR ]] && (( dt > 0 )); then
        S_DISK_READ=$(( (S_DISK_READ_TOTAL - PREV_DR) / dt ))
        S_DISK_WRITE=$(( (S_DISK_WRITE_TOTAL - PREV_DW) / dt ))
    fi
    PREV_DR=$S_DISK_READ_TOTAL PREV_DW=$S_DISK_WRITE_TOTAL

    # Busiest processes
    S_TOP_CPU=$(ps -Aceo pcpu=,rss=,comm= -r 2>/dev/null | head -n 5)
    S_TOP_MEM=$(ps -Aceo pcpu=,rss=,comm= -m 2>/dev/null | head -n 5)

    PREV_T=$now
}

dump_state() {
    local v
    for v in ${(ok)parameters[(I)S_*]}; do
        print -r -- "$v=${(qq)${(P)v}}"
    done
}

collector_loop() {
    trap - EXIT INT TERM HUP
    local line
    collect_static
    top -l 0 -s $INTERVAL -n 0 2>/dev/null | while IFS= read -r line; do
        parse_top_line "$line" || continue
        collect_dynamic
        (( S_SEQ++ ))
        dump_state >| "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
        kill -0 $MAIN_PID 2>/dev/null || break
    done
}

# --- Animation state -------------------------------------------------------

typeset -gA T D           # target and displayed (eased) values
typeset -ga H_CPU H_MEM H_GPU H_WATTS H_TEMP H_RX H_TX H_DR H_DW
typeset -gF TX=4 TDIST=0  # turtle position and distance walked
LAST_SEQ=0
FRAME=0

push() {   # history-name value
    local name=$1
    set -A $name "${(@P)name}" "${2:-0}"
    (( ${#${(P)name}} > 300 )) && shift $name
}

hottest() {   # the most telling chip temperature this Mac reports
    REPLY=${S_TEMP_CPU:-${S_TEMP_DIE:-${S_TEMP_GPU:-}}}
}

on_sample() {
    local i=0 c v
    T[cpu_user]=${S_CPU_USER:-0}
    T[cpu_sys]=${S_CPU_SYS:-0}
    T[cpu]=$(( T[cpu_user] + T[cpu_sys] ))
    T[mem]=$(( ${S_MEM_TOTAL:-0} > 0 ? 100.0 * S_MEM_USED / S_MEM_TOTAL : 0 ))
    T[pressure]=${S_MEM_PRESSURE:-0}
    T[gpu]=${S_GPU:-0}
    T[gpu_render]=${S_GPU_RENDER:-0}
    T[gpu_tiler]=${S_GPU_TILER:-0}
    T[batt]=${S_BATT_PCT:-0}
    T[disk]=$(( ${S_DISK_TOTAL:-0} > 0 ? 100.0 * S_DISK_USED / S_DISK_TOTAL : 0 ))
    for c in ${=S_CORE_PCT}; do T[core$(( ++i ))]=$c; done
    for c in CPU GPU DIE BOARD SSD BATTERY; do
        v=S_TEMP_$c
        [[ -n ${(P)v} ]] && T[temp_$c]=${(P)v}
    done
    push H_CPU $T[cpu]
    push H_MEM $T[mem]
    push H_GPU $T[gpu]
    push H_WATTS ${S_SYS_WATTS:-${S_BATT_WATTS#-}}
    hottest; push H_TEMP $REPLY
    push H_RX $S_NET_RX
    push H_TX $S_NET_TX
    push H_DR $S_DISK_READ
    push H_DW $S_DISK_WRITE
}

ease() {   # move every displayed value a step towards its target
    local k
    for k in ${(k)T}; do
        D[$k]=$(( ${D[$k]:-0} + (T[$k] - ${D[$k]:-0}) * ${1:-0.25} ))
    done
}

# --- The turtle and its sky ------------------------------------------------
# Each sprite row has a matching mask row naming the ink of every character:
# o shell rim, s shell plates, h head, l legs, e speed lines, z sleepy z's.

SPRITE_TOP='      _____      '
MASK_TOP='      ooooo      '
SPRITE_MID='    _/_|_|_\_  _ '
MASK_MID='    oosssssoo  h '
SPRITE_BOT='   /_|_|_|_|_\(°)'
MASK_BOT='   ossssssssoohhh'
LEGS_A='     /\    /\    '
LEGS_B='     ||    ||    '
MASK_LEGS='     ll    ll    '
SPRITE_W=17
CLOUD_TOP=' .-~~-. '
CLOUD_BOT='(______)'

typeset -ga STARS SPRITE MASK CLOUDS LANE_CH LANE_INK
SKY_W=0
LANE_W=0

make_sky() {   # width -> scattered stars, and clouds at random places
    local w=$1 i r row
    STARS=()
    for r in 1 2; do
        row=''
        for (( i = 0; i < w; i++ )); do
            if (( RANDOM % 40 == 0 )); then row+=${${:-'.·+*'}[RANDOM % 4 + 1]}; else row+=' '; fi
        done
        STARS+=("$row")
    done
    CLOUDS=()
    for (( i = 0; i < w / 45 + 1; i++ )); do
        CLOUDS+=("$(( RANDOM % w + 1 )) $(( RANDOM % 2 + 1 )) 0.$(( RANDOM % 5 + 3 ))")
    done
    SKY_W=$w
}

twinkle() {
    (( SKY_W )) || return
    local r=$(( RANDOM % 2 + 1 )) c=$(( RANDOM % SKY_W + 1 )) row
    row=$STARS[r]
    [[ ${row[c]} == ' ' ]] && return
    row[c]=${${:-'.·+*'}[RANDOM % 4 + 1]}
    STARS[r]=$row
}

drift_clouds() {   # seconds -> clouds float left, against the turtle
    local -F dt=$1 x
    local i
    local -a c
    for (( i = 1; i <= $#CLOUDS; i++ )); do
        c=(${=CLOUDS[i]})
        x=$(( c[1] - c[3] * dt ))
        (( x < -8 )) && x=$SKY_W
        CLOUDS[i]="$x $c[2] $c[3]"
    done
}

move_turtle() {   # seconds since the last frame, lane width
    local -F dt=$1 cpu=${D[cpu]:-0} speed
    local w=$2 eyes='(°)'
    local top=$SPRITE_TOP mid=$SPRITE_MID bot=$SPRITE_BOT legs
    local mtop=$MASK_TOP mmid=$MASK_MID mbot=$MASK_BOT
    if (( cpu < 12 )); then
        # Napping: eyes closed, a growing row of z's
        speed=0
        eyes='(-)'
        top="${SPRITE_TOP[1,13]}${${:-'    z   zZ  zZz '}[(FRAME / 8 % 4) * 4 + 1, (FRAME / 8 % 4) * 4 + 4]}"
        mtop="${MASK_TOP[1,13]}zzzz"
    else
        speed=$(( 2 + cpu * 0.25 ))
        if (( cpu >= 75 )); then
            # Sprinting: speed lines trail behind
            if (( FRAME % 2 )); then mid=" -  ${SPRITE_MID[5,-1]}" bot="=  ${SPRITE_BOT[4,-1]}"
            else mid=" =  ${SPRITE_MID[5,-1]}" bot="-  ${SPRITE_BOT[4,-1]}"; fi
            mmid=" e  ${MASK_MID[5,-1]}" mbot="e  ${MASK_BOT[4,-1]}"
        fi
    fi
    (( TX += speed * dt, TDIST += speed * dt ))
    (( TX > w )) && TX=$(( 1 - SPRITE_W ))
    if (( speed == 0 || int(TDIST / 1.5) % 2 )); then legs=$LEGS_B; else legs=$LEGS_A; fi
    SPRITE=("$top" "$mid" "${bot[1,-4]}$eyes" "$legs")
    MASK=("$mtop" "$mmid" "$mbot" "$MASK_LEGS")
}

stamp() {   # row col text ink -> paint text into the lane; spaces stay see-through
    local r=$1 x=$2 text=$3 ink=$4 j k
    for (( j = 1; j <= ${#text}; j++ )); do
        (( k = x + j - 1 ))
        (( k < 1 || k > LANE_W )) && continue
        [[ ${text[j]} == ' ' ]] && continue
        (( k += (r - 1) * LANE_W ))
        LANE_CH[k]=${text[j]}
        LANE_INK[k]=$ink
    done
}

draw_lane() {   # width -> reply: four rows of sky with the turtle walking in them
    local w=$1 r i k c s m ink prev out hour night first last
    local -a cl
    LANE_W=$w
    strftime -s hour '%H' $EPOCHSECONDS
    (( night = 10#$hour >= 20 || 10#$hour < 7 ))
    LANE_CH=()
    for r in 1 2 3 4; do
        if (( night && r <= 2 )); then LANE_CH+=("${(@s::)STARS[r]}")
        else LANE_CH+=("${(@s::)${(l:w:: :)}}"); fi
    done
    LANE_INK=("${(@)LANE_CH/*/k}")
    if (( night )); then
        stamp 1 $(( w * 4 / 5 )) '☾' m
    else
        stamp 1 $(( w * 4 / 5 )) '☼' u
        for c in $CLOUDS; do
            cl=(${=c})
            stamp $cl[2] $(( int(cl[1]) )) "$CLOUD_TOP" c
            stamp $(( cl[2] + 1 )) $(( int(cl[1]) )) "$CLOUD_BOT" c
        done
    fi
    # The turtle goes on top, and is solid: the sky never shows through its shell
    for r in 1 2 3 4; do
        s=$SPRITE[r] m=$MASK[r]
        first=${#${s%%[^ ]*}} last=${#${s%%[ ]#}}
        for (( i = first + 1; i <= last; i++ )); do
            (( k = int(TX) + i - 1 ))
            (( k < 1 || k > w )) && continue
            (( k += (r - 1) * w ))
            LANE_CH[k]=${s[i]}
            LANE_INK[k]=${m[i]:- }
        done
    done
    reply=()
    for r in 1 2 3 4; do
        out='' prev=''
        for (( i = 1; i <= w; i++ )); do
            k=$(( (r - 1) * w + i ))
            ink=$LANE_INK[k]
            if [[ $ink != "$prev" ]]; then out+=${INK[$ink]:-$C_RESET}; prev=$ink; fi
            out+=$LANE_CH[k]
        done
        reply+=("$out$C_RESET")
    done
}

# --- Panels ----------------------------------------------------------------

panel() {   # width title accent lines... -> reply: the boxed panel
    local w=$1 title=" $2 " acc=$3 l
    shift 3
    local iw=$(( w - 4 )) dash=$(( w - 3 - ${#title} ))
    (( dash < 1 )) && { title=" ${title[2,w-6]}… "; dash=$(( w - 3 - ${#title} )); }
    reply=("${C_FRAME}╭─${C_RESET}${C_BOLD}${acc}${title}${C_RESET}${C_FRAME}${(l:dash::─:)}╮${C_RESET}")
    for l in "$@"; do
        fit "$l" $iw
        reply+=("${C_FRAME}│${C_RESET} ${REPLY} ${C_FRAME}│${C_RESET}")
    done
    reply+=("${PANEL_GROUND:-$C_FRAME}╰${(l:w-2::─:)}╯${C_RESET}")
}

labeled_bar() {   # label percent width text [palette|color] -> "label  ████░░  text"
    local label=$1 v=$2 w=$3 text=$4 ink=${5:-PAL_HEAT}
    local tw=$(( ${#text} > 10 ? ${#text} : 10 ))
    local bw=$(( w - 10 - tw ))
    (( bw < 4 )) && bw=4
    bar $v $bw $ink
    REPLY="${C_GRAY}${(r:9:)label}${C_RESET}${REPLY} ${(l:tw:)text}"
}

cpu_lines() {
    local w=$1 i n c lvl types=$S_CORE_TYPES label prev='' cores=''
    local -F v
    local -a pcts=(${=S_CORE_PCT}) lines
    lines=("${C_BOLD}${S_CHIP:-CPU}${C_RESET}${C_GRAY} · ${S_CORES}${C_RESET}")
    pct $D[cpu_user]; labeled_bar user $D[cpu_user] $w "$REPLY"; lines+=("$REPLY")
    pct $D[cpu_sys];  labeled_bar system $D[cpu_sys] $w "$REPLY"; lines+=("$REPLY")
    if (( $#pcts )); then
        # One column per core, grouped by cluster
        n=$#pcts
        for (( i = 1; i <= n; i++ )); do
            c=${types[i]:-}
            if [[ $c != "$prev" ]]; then
                if [[ $c == P ]]; then label=${S_PERF_NAME[1]:-P}; else label=${c:-·}; fi
                cores+="${cores:+ }${C_GRAY}${label}${C_RESET} "
                prev=$c
            fi
            v=${D[core$i]:-0}
            lvl=$(( int(v / 100.0 * 7 + 0.5) ))
            heat $v
            cores+="${REPLY}${SPARKS[lvl+1]}${C_RESET}"
            (( w > 2 * n + 20 )) && cores+=' '
        done
        lines+=("${C_GRAY}cores    ${C_RESET}${cores}")
    fi
    heat $(( ${S_LOAD1:-0} * 100.0 / ${S_NCPU:-1} ))
    lines+=("${C_GRAY}load     ${C_RESET}${REPLY}${S_LOAD1:-…}${C_RESET}  ${S_LOAD5:-…}  ${S_LOAD15:-…}  ${C_GRAY}1 · 5 · 15 min${C_RESET}")
    if (( ! ONCE )); then
        spark2 $w 100 PAL_HEAT $H_CPU
        lines+=("${reply[@]}")
    fi
    reply=("${lines[@]}")
}

mem_lines() {
    local w=$1 used total app wired comp cached swap
    local -a lines
    human_bytes $S_MEM_USED; used=$REPLY
    human_bytes $S_MEM_TOTAL; total=$REPLY
    human_bytes $S_MEM_APP; app=$REPLY
    human_bytes $S_MEM_WIRED; wired=$REPLY
    human_bytes $S_MEM_COMPRESSED; comp=$REPLY
    human_bytes $S_MEM_CACHED; cached=$REPLY
    human_bytes $S_SWAP_USED; swap=$REPLY
    human_bytes $S_SWAP_TOTAL; swap+="${C_GRAY} of ${C_RESET}$REPLY"
    labeled_bar used $D[mem] $w "$used / $total"; lines=("$REPLY")
    pct $D[pressure]; labeled_bar pressure $D[pressure] $w "$REPLY"; lines+=("$REPLY")
    lines+=("${C_GRAY}app ${C_RESET}$app${C_GRAY} · wired ${C_RESET}$wired${C_GRAY} · compressed ${C_RESET}$comp")
    lines+=("${C_GRAY}cached files ${C_RESET}$cached${C_GRAY} · swap ${C_RESET}$swap${C_RESET}")
    if (( ! ONCE )); then
        spark2 $w 100 PAL_VIOLET $H_MEM
        lines+=("${reply[@]}")
    fi
    reply=("${lines[@]}")
}

temp_lines() {
    local w=$1 g label v any=0 line rpm hi
    local -F t
    local -a lines f
    if [[ $S_PROBE != ok ]]; then
        reply=("${C_GRAY}Temperatures and fans need a small helper,${C_RESET}"
               "${C_GRAY}built with the Xcode Command Line Tools:${C_RESET}"
               "  xcode-select --install")
        return
    fi
    for g label in CPU cpu GPU gpu DIE 'chip die' BOARD board SSD ssd BATTERY battery; do
        v=S_TEMP_$g
        [[ -n ${(P)v} ]] || continue
        any=1
        t=${D[temp_$g]:-${(P)v}}
        degrees $t
        # 20 °C to 105 °C spans the bar
        labeled_bar "$label" $(( (t - 20) * 100 / 85.0 )) $w "$REPLY"
        lines+=("$REPLY")
    done
    (( any )) || lines+=("${C_GRAY}This Mac reports no temperature sensors.${C_RESET}")
    if [[ -n $S_FANS ]]; then
        for line in "${(@f)S_FANS}"; do
            f=(${=line})
            rpm=$f[2] hi=$f[4]
            if (( rpm < 1 )); then
                labeled_bar "fan $(( f[1] + 1 ))" 0 $w "off" PAL_COOL
            else
                labeled_bar "fan $(( f[1] + 1 ))" $(( hi > 0 ? 100.0 * rpm / hi : 0 )) $w "$rpm rpm" PAL_COOL
            fi
            lines+=("$REPLY")
        done
    elif (( any )); then
        lines+=("${C_GRAY}fans     ${C_RESET}none, cooled passively")
    fi
    if [[ $S_THERMAL == nominal ]]; then
        lines+=("${C_GRAY}pressure ${C_RESET}${PAL_HEAT[1]}nominal${C_RESET}")
    else
        lines+=("${C_GRAY}pressure ${C_RESET}${C_RED}${S_THERMAL}${C_RESET}")
    fi
    if (( ! ONCE && any )); then
        spark $w 105 PAL_HEAT $H_TEMP
        lines+=("$REPLY")
    fi
    reply=("${lines[@]}")
}

power_lines() {
    local w=$1 s ink
    local -a parts lines
    if [[ -n $S_BATT_PCT ]]; then
        if (( S_BATT_PCT <= 20 )); then ink=$PAL_HEAT[10]
        elif (( S_BATT_PCT <= 50 )); then ink=$PAL_HEAT[6]
        else ink=$PAL_HEAT[2]; fi
        labeled_bar battery $D[batt] $w "${S_BATT_PCT}%" "$ink"; lines+=("$REPLY")
        lines+=("${S_BATT_STATE}${C_GRAY}${S_BATT_TIME:+ · $S_BATT_TIME}${C_RESET}")
    else
        lines+=("${S_POWER_SOURCE:-AC Power}${C_GRAY} · no battery${C_RESET}")
    fi
    if [[ -n $S_SYS_WATTS ]]; then
        printf -v s '%.1f' $S_SYS_WATTS
        parts+=("${C_GRAY}system draw ${C_RESET}${s}W")
    fi
    if [[ -n $S_BATT_WATTS ]]; then
        printf -v s '%+.1f' $S_BATT_WATTS
        parts+=("${C_GRAY}battery ${C_RESET}${s}W")
    fi
    (( $#parts )) && lines+=("${(j: · :)parts}")
    [[ -n $S_ADAPTER_WATTS ]] && lines+=("${C_GRAY}charger ${C_RESET}${S_ADAPTER_WATTS}W")
    if [[ -n $S_BATT_CYCLES ]]; then
        s=''
        [[ -n $S_BATT_VOLTS ]] && printf -v s '%s · %s%.2fV' "$C_GRAY" "$C_RESET" $S_BATT_VOLTS
        lines+=("${C_GRAY}health ${C_RESET}${S_BATT_HEALTH:-…}%${C_GRAY} · cycles ${C_RESET}${S_BATT_CYCLES}${s}")
    fi
    if (( ! ONCE )) && [[ -n $S_SYS_WATTS$S_BATT_WATTS ]]; then
        spark2 $w 0 PAL_WARM $H_WATTS
        lines+=("${reply[@]}")
    fi
    reply=("${lines[@]}")
}

gpu_lines() {
    local w=$1 mem
    local -a lines
    lines=("${C_BOLD}${S_GPU_NAME:-GPU}${C_RESET}${S_GPU_CORES:+${C_GRAY} · ${S_GPU_CORES} cores${C_RESET}}")
    if [[ -z $S_GPU ]]; then
        lines+=("${C_GRAY}No usage figures from this GPU.${C_RESET}")
        reply=("${lines[@]}")
        return
    fi
    pct $D[gpu];        labeled_bar device   $D[gpu]        $w "$REPLY"; lines+=("$REPLY")
    pct $D[gpu_render]; labeled_bar renderer $D[gpu_render] $w "$REPLY"; lines+=("$REPLY")
    pct $D[gpu_tiler];  labeled_bar tiler    $D[gpu_tiler]  $w "$REPLY"; lines+=("$REPLY")
    human_bytes $S_GPU_MEM; mem=$REPLY
    lines+=("${C_GRAY}memory in use ${C_RESET}$mem")
    if (( ! ONCE )); then spark $w 100 PAL_COOL $H_GPU; lines+=("$REPLY"); fi
    reply=("${lines[@]}")
}

rate_line() {   # label rate width palette history... -> "label  1.2M/s  ▁▂▃"
    local label=$1 rate=$2 w=$3 pal=$4 text
    shift 4
    human_rate $rate
    text="${C_GRAY}${(r:9:)label}${C_RESET}${(l:8:)REPLY}"
    if (( ONCE )); then
        REPLY=$text
    else
        spark $(( w - 19 )) 0 $pal "$@"
        REPLY="$text  $REPLY"
    fi
}

net_lines() {
    local w=$1 rx tx
    local -a lines
    if [[ -z $S_NET_IF ]]; then
        reply=("${C_GRAY}Offline: no default route.${C_RESET}")
        return
    fi
    lines=("${C_BOLD}${S_NET_IF}${C_RESET}${S_NET_KIND:+${C_GRAY} · ${S_NET_KIND}}${S_NET_IP:+${C_GRAY} · ${C_RESET}${S_NET_IP}}")
    rate_line "↓ in" "$S_NET_RX" $w PAL_COOL $H_RX; lines+=("$REPLY")
    rate_line "↑ out" "$S_NET_TX" $w PAL_HEAT $H_TX; lines+=("$REPLY")
    human_bytes $S_NET_RX_TOTAL; rx=$REPLY
    human_bytes $S_NET_TX_TOTAL; tx=$REPLY
    lines+=("${C_GRAY}since boot ${C_RESET}$rx${C_GRAY} in · ${C_RESET}$tx${C_GRAY} out${C_RESET}")
    reply=("${lines[@]}")
}

disk_lines() {
    local w=$1 used free total r wr
    local -a lines
    human_bytes $S_DISK_USED; used=$REPLY
    human_bytes $S_DISK_FREE; free=$REPLY
    human_bytes $S_DISK_TOTAL; total=$REPLY
    labeled_bar used $D[disk] $w "$used / $total"; lines=("$REPLY")
    lines+=("${C_GRAY}free     ${C_RESET}$free")
    rate_line read "$S_DISK_READ" $w PAL_COOL $H_DR; lines+=("$REPLY")
    rate_line write "$S_DISK_WRITE" $w PAL_VIOLET $H_DW; lines+=("$REPLY")
    human_bytes $S_DISK_READ_TOTAL; r=$REPLY
    human_bytes $S_DISK_WRITE_TOTAL; wr=$REPLY
    lines+=("${C_GRAY}since boot ${C_RESET}$r${C_GRAY} read · ${C_RESET}$wr${C_GRAY} written${C_RESET}")
    reply=("${lines[@]}")
}

system_lines() {
    local w=$1 up clock zone total
    local -a lines
    human_duration $(( EPOCHSECONDS - ${S_BOOT:-$EPOCHSECONDS} )); up=$REPLY
    strftime -s clock '%a %e %b · %H:%M:%S' $EPOCHSECONDS
    strftime -s zone '%Z' $EPOCHSECONDS
    human_bytes $S_MEM_TOTAL; total=$REPLY
    lines=("${S_OS}${C_GRAY} (${S_BUILD}) · Darwin ${S_KERNEL}${C_RESET}")
    lines+=("${C_GRAY}up ${C_RESET}${up}${C_GRAY} · since ${S_BOOT_STR:-…}${C_RESET}")
    lines+=("${S_PROCS:-…}${C_GRAY} processes · ${C_RESET}${S_RUNNING:-…}${C_GRAY} running · ${C_RESET}${S_THREADS:-…}${C_GRAY} threads${C_RESET}")
    lines+=("${S_MODEL}${C_GRAY} · ${C_RESET}${total}${C_GRAY} memory · ${C_RESET}${S_USERS:-…}${C_GRAY} logged in${C_RESET}")
    lines+=("${C_BOLD}${clock}${C_RESET}${C_GRAY} ${zone}${C_RESET}")
    reply=("${lines[@]}")
}

proc_lines() {   # cpu|mem -> reply: the five busiest processes with mini bars
    local which=$1 line mem text pal=PAL_HEAT tag=CPU
    local -F share
    local -a f lines
    [[ $which == mem ]] && pal=PAL_VIOLET tag=RAM
    lines=("${C_BOLD}${(r:6:)tag}${C_RESET}${C_GRAY} %CPU  MEMORY  NAME${C_RESET}")
    for line in "${(@f)${(P)${:-S_TOP_${(U)which}}}}"; do
        f=(${=line})
        (( $#f >= 3 )) || continue
        if [[ $which == cpu ]]; then share=$f[1]
        # A quarter of all memory fills the bar
        else share=$(( ${S_MEM_TOTAL:-0} > 0 ? 400.0 * f[2] * 1024 / S_MEM_TOTAL : 0 )); fi
        bar $share 4 $pal
        text=$REPLY
        human_bytes $(( f[2] * 1024 )); mem=$REPLY
        printf -v line '%s %6.1f  %6s  %s' "$text" $f[1] "$mem" "${f[3,-1]}"
        lines+=("$line")
    done
    reply=("${lines[@]}")
}

# --- Layout ----------------------------------------------------------------

typeset -ga OUT
add_block() {   # lines... -> appended to OUT if the whole block still fits
    (( FULL )) && return 1
    if (( $#OUT + $# > MAXL )); then FULL=1; return 1; fi
    OUT+=("$@")
}

row() {   # titleA builderA accentA titleB builderB accentB
    local -a a b pa pb lines
    local i n
    $2 $IW; a=("${reply[@]}")
    $5 $IW; b=("${reply[@]}")
    if (( TWO )); then
        n=$(( $#a > $#b ? $#a : $#b ))
        while (( $#a < n )); do a+=(''); done
        while (( $#b < n )); do b+=(''); done
        panel $PW "$1" "$3" "${a[@]}"; pa=("${reply[@]}")
        panel $PW "$4" "$6" "${b[@]}"; pb=("${reply[@]}")
        for (( i = 1; i <= $#pa; i++ )); do lines+=("${pa[i]} ${pb[i]}"); done
        add_block "${lines[@]}"
    else
        panel $PW "$1" "$3" "${a[@]}"; add_block "${reply[@]}"
        panel $PW "$4" "$6" "${b[@]}"; add_block "${reply[@]}"
    fi
}

processes_block() {   # both process lists, side by side when there's room
    local -a a b lines
    local i n half
    proc_lines cpu; a=("${reply[@]}")
    proc_lines mem; b=("${reply[@]}")
    if (( TWO )); then
        half=$(( (HW - 4 - 3) / 2 ))
        n=$(( $#a > $#b ? $#a : $#b ))
        for (( i = 1; i <= n; i++ )); do
            fit "${a[i]:-}" $half
            lines+=("$REPLY ${C_FRAME}│${C_RESET} ${b[i]:-}")
        done
        panel $HW "▸ PROCESSES" "$ACCENT[proc]" "${lines[@]}"; add_block "${reply[@]}"
    else
        panel $PW "▸ PROCESSES" "$ACCENT[proc]" "${a[@]}" "" "${b[@]}"; add_block "${reply[@]}"
    fi
}

build_frame() {   # columns rows -> OUT
    local W=$1 H=$2 title up temp=''
    OUT=() FULL=0 MAXL=$H
    if (( W < 64 )); then
        OUT=("${C_YELLOW}Make the window wider: the dashboard needs 64 columns.${C_RESET}")
        return
    fi
    TWO=$(( W >= 110 ))
    if (( TWO )); then PW=$(( (W - 1) / 2 )) HW=$(( PW * 2 + 1 )); else PW=$(( W > 84 ? 84 : W )) HW=$PW; fi
    IW=$(( PW - 4 ))

    # Header: who and what this Mac is, with the turtle lane underneath
    human_duration $(( EPOCHSECONDS - ${S_BOOT:-$EPOCHSECONDS} )); up=$REPLY
    hottest; [[ -n $REPLY ]] && { degrees $REPLY; temp=" · $REPLY"; }
    title="${S_HOST:-system_stats}${S_MODEL_NAME:+ · $S_MODEL_NAME}${S_OS:+ · $S_OS}${S_BOOT:+ · up $up}$temp"
    (( SKY_W != HW - 4 )) && make_sky $(( HW - 4 ))
    draw_lane $(( HW - 4 ))
    PANEL_GROUND=$C_GROUND panel $HW "$title" "$ACCENT[cpu]" "${reply[@]}"
    add_block "${reply[@]}"

    if (( ${S_SEQ:-0} == 0 )); then
        panel $HW "Starting" "$ACCENT[sys]" "${C_GRAY}Taking the first sample…${C_RESET}"
        add_block "${reply[@]}"
        return
    fi
    row "◆ CPU" cpu_lines "$ACCENT[cpu]" "▦ MEMORY" mem_lines "$ACCENT[mem]"
    row "▲ THERMALS" temp_lines "$ACCENT[temp]" "ϟ POWER" power_lines "$ACCENT[power]"
    row "◈ GPU" gpu_lines "$ACCENT[gpu]" "⇅ NETWORK" net_lines "$ACCENT[net]"
    row "◍ DISK" disk_lines "$ACCENT[disk]" "● SYSTEM" system_lines "$ACCENT[sys]"
    processes_block
}

# --- Live mode -------------------------------------------------------------

ROWS=24 COLS=80
get_size() {
    local s
    s=$(stty size </dev/tty 2>/dev/null)
    if [[ $s == <->' '<-> ]]; then ROWS=${s% *} COLS=${s#* }; fi
}

RESIZED=0
TRAPWINCH() { RESIZED=1; }

TERM_READY=0
cleanup() {
    if [[ -n ${COLLECTOR_PID:-} ]]; then
        pkill -P $COLLECTOR_PID 2>/dev/null
        kill $COLLECTOR_PID 2>/dev/null
    fi
    [[ -n ${STATE_DIR:-} ]] && rm -rf "$STATE_DIR"
    if (( TERM_READY )); then
        [[ -n ${STTY_SAVED:-} ]] && stty "$STTY_SAVED" </dev/tty 2>/dev/null
        # Show the cursor, wrap lines again, leave the alternate screen
        printf '\033[?25h\033[?7h\033[?1049l'
    fi
}

live() {
    local key now last state paused=0
    local -a spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local -F dt

    MAIN_PID=$$
    STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/system_stats.XXXXXX") || die "Couldn't create a temporary folder."
    STATE=$STATE_DIR/state
    collector_loop >/dev/null 2>&1 &!
    COLLECTOR_PID=$!

    exec {TTY_FD}</dev/tty
    STTY_SAVED=$(stty -g </dev/tty)
    stty -echo -icanon min 1 time 0 </dev/tty
    TERM_READY=1
    # Alternate screen, no line wrapping, hidden cursor
    printf '\033[?1049h\033[?7l\033[?25l\033[2J'
    get_size

    last=$EPOCHREALTIME
    while :; do
        now=$EPOCHREALTIME
        dt=$(( now - last ))
        last=$now
        (( dt > 0.5 )) && dt=0.5
        if (( RESIZED )); then
            RESIZED=0
            get_size
            printf '\033[2J'
        fi
        if (( ! paused )); then
            if [[ -r $STATE ]]; then
                unset -m 'S_*'
                source "$STATE"
            fi
            if (( ${S_SEQ:-0} != LAST_SEQ )); then
                LAST_SEQ=$S_SEQ
                on_sample
            fi
            ease 0.2
            (( FRAME++ ))
            (( FRAME % 3 == 0 )) && twinkle
            drift_clouds $dt
            move_turtle $dt $(( SKY_W ? SKY_W : COLS - 4 ))
        fi

        build_frame $COLS $(( ROWS - 1 ))
        if (( paused )); then
            state="${C_REV} ❚❚ paused ${C_NOREV}"
        else
            state="${ACCENT[cpu]}${spin[FRAME % $#spin + 1]}${C_RESET} live"
        fi
        OUT+=(" $state${C_GRAY} · every ${INTERVAL}s · updated ${S_TIME:-…}   ${C_RESET}${C_REV} q ${C_NOREV}${C_GRAY} quit  ${C_RESET}${C_REV} p ${C_NOREV}${C_GRAY} pause  ${C_RESET}${C_REV} f ${C_NOREV}${C_GRAY} °C/°F${C_RESET}")
        print -rn -- $'\e[H'"${(pj:\e[K\n:)OUT}"$'\e[K\e[J'

        key=''
        read -s -t 0.08 -k 1 -u $TTY_FD key
        case $key in
            q|Q) break ;;
            p|P|' ') (( paused = !paused )) ;;
            f|F) (( FAHRENHEIT = !FAHRENHEIT )) ;;
        esac
    done
}

# --- Snapshot mode ---------------------------------------------------------

once() {
    local line s
    collect_static
    collect_dynamic
    top -l 2 -s 1 -n 0 2>/dev/null | while IFS= read -r line; do
        parse_top_line "$line"
    done
    collect_dynamic
    S_SEQ=1
    on_sample
    ease 1
    FRAME=0
    COLS=${COLUMNS:-120}
    if [ -t 1 ]; then
        s=$(stty size 2>/dev/null)
        [[ $s == <->' '<-> ]] && COLS=${s#* }
    fi
    (( COLS < 64 )) && COLS=64
    T[cpu]=50 D[cpu]=50   # keep the turtle awake and standing for the photo
    TX=$(( (COLS >= 110 ? COLS : (COLS > 84 ? 84 : COLS)) / 2 - SPRITE_W / 2 - 2 ))
    move_turtle 0 $COLS
    build_frame $COLS 10000
    print -rl -- "${OUT[@]}"
}

# --- Main ------------------------------------------------------------------

while (( $# )); do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--interval)
            [[ ${2:-} == <1-60> ]] || die "--interval needs whole seconds from 1 to 60, e.g. --interval 5"
            INTERVAL=$2
            shift
            ;;
        --interval=*)
            [[ ${1#*=} == <1-60> ]] || die "--interval needs whole seconds from 1 to 60, e.g. --interval=5"
            INTERVAL=${1#*=}
            ;;
        -F|--fahrenheit)
            FAHRENHEIT=1
            ;;
        -1|--once)
            ONCE=1
            ;;
        *)
            usage >&2
            printf '\n' >&2
            die "Unknown option: $1"
            ;;
    esac
    shift
done

[[ $OSTYPE == darwin* ]] || die "$SCRIPT_NAME reads macOS tools (top, vm_stat, ioreg, pmset), so it only runs on macOS."

# No terminal to animate in (piped, redirected): print one snapshot instead.
[ -t 1 ] && [ -r /dev/tty ] || ONCE=1

if (( ONCE )); then
    once
    exit 0
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
live
