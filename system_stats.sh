#!/bin/zsh

# ---------------------------------------------------------------------------
# system_stats.sh — a live, animated dashboard of your Mac's vital signs
#
# Usage: ./system_stats.sh [--interval N] [--fahrenheit] [--theme NAME] [--sky MODE]
#        ./system_stats.sh --once
#
# Shows CPU (per core), GPU, memory, temperatures and fans, power and battery,
# Bluetooth device batteries, network, disk, system facts and the busiest
# processes: everything macOS hands out without sudo. A turtle strolls along
# the top, faster the busier the CPU is, under the sun by day and the stars by
# night (with snow in winter and fireworks at New Year), and naps when idle.
#
# Temperatures, fans and per-core load come from a tiny helper compiled once
# with the Xcode Command Line Tools and cached in ~/Library/Caches.
#
# Keys: q quits, p pauses, 1-0 hide panels, z zooms one, t switches the
# theme, f switches °C/°F. NO_COLOR=1 disables colors.
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
SKY_MODE=auto
THEMES=(turtle ocean sunset mono)
THEME=${SYSTEM_STATS_THEME:-turtle}
(( ${THEMES[(Ie)$THEME]} )) || THEME=turtle

# --- Colors ----------------------------------------------------------------
# With a 256-color terminal, bars and sparklines get smooth gradients; with 8
# colors they step through green, yellow and red; with NO_COLOR they're plain.

C_RESET=""; C_BOLD=""; C_REV=""; C_NOREV=""
C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GRAY=""
C_FRAME=""; C_TRACK=""; C_GROUND=""
C256=0
typeset -ga PAL_HEAT PAL_COOL PAL_WARM PAL_VIOLET
typeset -gA ACCENT INK GRADIENT
# Turtle and sky inks: o shell rim, s shell plates, h head, l legs, e speed
# lines, z sleepy z's, c clouds, u sun, m moon, k stars, w sweat, b battery
# case, B battery cells, f snow, fw1-fw6 fireworks
INK_KEYS=(o s h l e z c u m k w b B f fw1 fw2 fw3 fw4 fw5 fw6)

setup_colors() {
    local k
    PAL_HEAT=('' '' '' '' '' '' '' '' '' '')
    PAL_COOL=("${PAL_HEAT[@]}") PAL_WARM=("${PAL_HEAT[@]}") PAL_VIOLET=("${PAL_HEAT[@]}")
    ACCENT=(cpu '' mem '' temp '' power '' gpu '' net '' disk '' sys '' bt '' proc '')
    INK=()
    for k in $INK_KEYS; do INK[$k]=''; done
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] || return 0

    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_REV=$'\e[7m' C_NOREV=$'\e[27m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
    C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m' C_GRAY=$'\e[90m'

    if [[ $TERM == *256color* || $TERM == *(kitty|ghostty|alacritty|wezterm)* || -n ${COLORTERM:-} ]]; then
        C256=1
        apply_theme $THEME
    else
        PAL_HEAT=($C_GREEN $C_GREEN $C_GREEN $C_GREEN $C_GREEN $C_YELLOW $C_YELLOW $C_YELLOW $C_RED $C_RED)
        PAL_COOL=($C_BLUE $C_BLUE $C_BLUE $C_BLUE $C_BLUE $C_CYAN $C_CYAN $C_CYAN $C_CYAN $C_CYAN)
        PAL_WARM=("${(@)PAL_HEAT/*/$C_YELLOW}")
        PAL_VIOLET=("${(@)PAL_HEAT/*/$C_MAGENTA}")
        C_FRAME=$C_GRAY C_TRACK=$C_GRAY C_GROUND=$C_GREEN
        ACCENT=(cpu $C_BLUE mem $C_MAGENTA temp $C_RED power $C_YELLOW gpu $C_CYAN net $C_GREEN
                disk $C_MAGENTA sys $C_RESET bt $C_BLUE proc $C_GREEN)
        INK=(o $C_GREEN s $C_GREEN h $C_YELLOW l $C_GREEN e $C_GRAY z $C_CYAN c $C_RESET u $C_YELLOW
             m $C_YELLOW k $C_GRAY w $C_CYAN b $C_RESET B $C_GREEN f $C_RESET fw1 $C_RED fw2 $C_YELLOW
             fw3 $C_GREEN fw4 $C_CYAN fw5 $C_MAGENTA fw6 $C_BLUE)
    fi
}

# Themes change the 256-color look; 8-color terminals keep the basic colors.
apply_theme() {   # name
    (( C256 )) || return 0
    local e=$'\e[38;5;' c i
    local -a heat cool warm violet ui turtle panels=(cpu mem temp power gpu net disk sys bt proc)
    heat=(41 77 113 149 185 221 215 209 203 197)
    cool=(24 25 31 32 38 39 45 51 87 123)
    warm=(94 130 136 172 178 214 220 221 227 229)
    violet=(54 55 91 92 128 129 135 165 171 177)
    #       o  s  h   l   e   z   c   u   m   k   w   b   B  f   fw1 fw2 fw3 fw4 fw5 fw6
    turtle=(34 28 150 107 244 153 255 220 229 240 117 250 77 255 196 214 226 46  51  201)
    #             frame track gray ground cpu mem temp power gpu net disk sys bt  proc
    case $1 in
        ocean)  ui=(24  236   109  31     81  117 210  229   45  50  147  152 75  86) ;;
        sunset) ui=(95  237   181  136    209 175 203  221   216 180 168  223 211 215) ;;
        mono)   ui=(240 236   245  245    255 252 250  254   253 251 249  247 252 252)
                heat=(238 240 242 244 246 248 250 252 254 255)
                cool=($heat) warm=($heat) violet=($heat)
                turtle=(250 244 252 246 242 252 255 255 255 240 250 248 252 255 255 252 250 248 246 244) ;;
        *)      ui=(240 237   245  71     75  141 209  220   39  43  176  250 33  114) ;;
    esac
    PAL_HEAT=() PAL_COOL=() PAL_WARM=() PAL_VIOLET=()
    for c in $heat; do PAL_HEAT+=("$e${c}m"); done
    for c in $cool; do PAL_COOL+=("$e${c}m"); done
    for c in $warm; do PAL_WARM+=("$e${c}m"); done
    for c in $violet; do PAL_VIOLET+=("$e${c}m"); done
    C_FRAME="$e${ui[1]}m" C_TRACK="$e${ui[2]}m" C_GRAY="$e${ui[3]}m" C_GROUND="$e${ui[4]}m"
    for (( i = 1; i <= $#panels; i++ )); do ACCENT[$panels[i]]="$e${ui[i + 4]}m"; done
    for (( i = 1; i <= $#INK_KEYS; i++ )); do INK[$INK_KEYS[i]]="$e${turtle[i]}m"; done
    GRADIENT=()
    THEME=$1
}
setup_colors

die() { printf '%s\n' "${C_RED}✖${C_RESET}  ${C_RED}$*${C_RESET}" >&2; exit 1; }

# --- Help ------------------------------------------------------------------
usage() {
    local me="$SCRIPT_NAME"
    printf '%s\n' "${C_BOLD}${me}${C_RESET} ${C_GRAY}— a live, animated dashboard of your Mac's vital signs${C_RESET}"
    printf '\n'
    printf '%s\n' "${C_BOLD}USAGE${C_RESET}"
    printf '  %s\n' "${me} [--interval N] [--fahrenheit] [--theme NAME] [--sky MODE]"
    printf '  %s\n' "${me} --once"
    printf '\n'
    printf '%s\n' "${C_BOLD}SHOWS${C_RESET}"
    printf '  %s\n' "CPU usage per core and load, GPU usage, memory and pressure, chip, SSD"
    printf '  %s\n' "and battery temperatures, fan speeds, battery and power draw, Bluetooth"
    printf '  %s\n' "device batteries, network and disk throughput, system facts and the"
    printf '  %s\n' "busiest processes. Everything macOS reports without sudo. The turtle walks"
    printf '  %s\n' "faster the busier your CPU gets, sweats when the chip runs hot, carries a"
    printf '  %s\n' "battery while charging and takes a nap when the Mac is idle."
    printf '\n'
    printf '%s\n' "${C_BOLD}OPTIONS${C_RESET}"
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-i, --interval N" "$C_RESET" "Seconds between samples, 1 to 60 (default: 2)."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-F, --fahrenheit" "$C_RESET" "Show temperatures in °F."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-t, --theme NAME" "$C_RESET" "Colors: ${(j:, :)THEMES} (default: turtle, or"
    printf '  %s%-18s%s %s\n' ""        ""                 ""         "\$SYSTEM_STATS_THEME)."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "--sky MODE"       "$C_RESET" "auto (default), day, night, snow or fireworks."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-1, --once"       "$C_RESET" "Print one snapshot and exit, no animation."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "-h, --help"       "$C_RESET" "Show this help and exit."
    printf '\n'
    printf '%s\n' "${C_BOLD}KEYS${C_RESET}"
    printf '  %s%-18s%s %s\n' "$C_CYAN" "q"                "$C_RESET" "Quit (Ctrl-C works too)."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "p, space"         "$C_RESET" "Pause and resume."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "1 … 9, 0"         "$C_RESET" "Hide or show a panel (its number is in its corner)."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "z, then 1 … 0"    "$C_RESET" "Zoom a panel to full width with big graphs;"
    printf '  %s%-18s%s %s\n' ""        ""                 ""         "z or Esc goes back."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "t"                "$C_RESET" "Switch the color theme."
    printf '  %s%-18s%s %s\n' "$C_CYAN" "f"                "$C_RESET" "Switch between °C and °F."
    printf '\n'
    printf '%s\n' "${C_BOLD}EXAMPLES${C_RESET}"
    printf '  %s\n' "${me}                 ${C_GRAY}# live dashboard, a sample every 2 s${C_RESET}"
    printf '  %s\n' "${me} -i 5 -F         ${C_GRAY}# every 5 s, in Fahrenheit${C_RESET}"
    printf '  %s\n' "${me} -t ocean        ${C_GRAY}# in blues${C_RESET}"
    printf '  %s\n' "${me} --sky snow      ${C_GRAY}# let it snow, whatever the month${C_RESET}"
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

# Connected Bluetooth devices, one per line: name<TAB>kind<TAB>part=percent ...
# AirPods report left, right and case; keyboards and mice a single battery.
collect_bluetooth() {
    local out extra line
    out=$(system_profiler SPBluetoothDataType 2>/dev/null)
    if [[ -z $out ]]; then S_BT_POWER="" S_BT=""; return; fi
    if [[ $out == *"State: On"* ]]; then S_BT_POWER=on; else S_BT_POWER=off; fi
    S_BT=$(parse_bluetooth <<<"$out")
    # Apple keyboards, mice and trackpads also report through IOKit
    extra=$(ioreg -r -l -k BatteryPercent -w0 2>/dev/null | awk -F' = ' '
        /\+-o / { if (p != "" && b != "") print p "\t\tbattery=" b; p = ""; b = "" }
        /"Product" = / { p = $2; gsub(/"/, "", p) }
        /"BatteryPercent" = / { b = $2 + 0 }
        END { if (p != "" && b != "") print p "\t\tbattery=" b }')
    # The separator stays outside double quotes: inside them zsh keeps $'\n'
    # as those four characters, which glued the device onto the line before.
    for line in "${(@f)extra}"; do
        [[ -n $line && $'\n'$S_BT$'\n' != *$'\n'"${line%%$'\t'*}"$'\t'* ]] || continue
        [[ -n $S_BT ]] && S_BT+=$'\n'
        S_BT+=$line
    done
}

parse_bluetooth() {   # system_profiler SPBluetoothDataType on stdin
    awk '
        function flush() { if (name != "") printf "%s\t%s\t%s\n", name, kind, bats; name = "" }
        {
            match($0, /^ */); ind = RLENGTH; line = substr($0, ind + 1)
            if (line == "Connected:") { section = ind; on = 1; dev = 0; next }
            if (on && line != "" && ind <= section) { flush(); on = 0 }
            if (!on || line == "") next
            if (!dev) dev = ind
            if (ind == dev && line ~ /:$/) {
                flush(); name = substr(line, 1, length(line) - 1); kind = ""; bats = ""; next
            }
            if (line ~ /^Minor Type: /) kind = substr(line, 13)
            else if (line ~ /Battery Level: [0-9]+%/) {
                part = line; sub(/ ?Battery Level:.*/, "", part)
                if (part == "") part = "battery"
                pct = line; sub(/.*: /, "", pct); sub(/%.*/, "", pct)
                bats = bats (bats == "" ? "" : " ") tolower(part) "=" pct
            }
        }
        END { flush() }'
}

parse_pmset_batt() {   # pmset -g batt output -> power source and battery state
    # Now drawing from 'Battery Power'
    #  -InternalBattery-0 (id=1234567)<TAB>80%; discharging; 5:12 remaining present: true
    local out=$1 line
    S_POWER_SOURCE=${${out#*\'}%%\'*}
    S_BATT_PCT="" S_BATT_STATE="" S_BATT_TIME=""
    [[ $out == *InternalBattery* ]] || return 0
    line=${${(f)out}[2]}
    local -a f=("${(@s:; :)${line#*$'\t'}}")
    S_BATT_PCT=${f[1]%\%}
    S_BATT_STATE=$f[2]
    S_BATT_TIME=${f[3]%% present*}
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
    parse_pmset_batt "$(pmset -g batt 2>/dev/null)"
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
    S_TOP_CPU=$(ps -Aceo pcpu=,rss=,comm= -r 2>/dev/null | head -n 12)
    S_TOP_MEM=$(ps -Aceo pcpu=,rss=,comm= -m 2>/dev/null | head -n 12)

    # Bluetooth devices change rarely, and asking is the slowest call here
    (( COLLECT_TICK % 8 == 1 )) && collect_bluetooth

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
SPARKS_ON=1               # small sparklines, off in snapshots and zoom

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
    for c in ${=S_CORE_PCT}; do
        (( ++i ))
        T[core$i]=$c
        push H_CORE_$i $c
    done
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

typeset -ga STARS SPRITE MASK CLOUDS LANE_CH LANE_INK FLAKES BURSTS
SKY_W=0
LANE_W=0
SKY_NIGHT=0 SKY_SNOW=0 SKY_FIREWORKS=0

# A firework bursts in five stages, each three rows tall around its center
BURST_STAGES=(
    ''        '*'       ''
    '.'       '-*-'     "'"
    '\ | /'   '-   -'   '/ | \'
    ".  '  ." "'     '" '.  .  .'
    '·     ·' ''        '·     ·'
)

sky_state() {   # what the sky looks like right now
    local now
    local -a t
    strftime -s now '%m %d %H' $EPOCHSECONDS
    t=(${=now})
    (( t[1] = 10#$t[1], t[2] = 10#$t[2], t[3] = 10#$t[3] ))
    SKY_NIGHT=$(( t[3] >= 20 || t[3] < 7 ))
    SKY_SNOW=$(( t[1] == 12 || t[1] <= 2 ))
    SKY_FIREWORKS=$(( (t[1] == 12 && t[2] == 31 && t[3] >= 20) || (t[1] == 1 && t[2] == 1 && t[3] < 3) ))
    case $SKY_MODE in
        day) SKY_NIGHT=0 SKY_SNOW=0 SKY_FIREWORKS=0 ;;
        night) SKY_NIGHT=1 SKY_SNOW=0 SKY_FIREWORKS=0 ;;
        snow) SKY_SNOW=1 ;;
        fireworks) SKY_NIGHT=1 SKY_FIREWORKS=1 ;;
    esac
}

let_it_snow() {   # seconds -> flakes drift down and start over at the top
    local -F dt=$1 x y
    local i
    local -a f
    if (( ! SKY_SNOW || ! SKY_W )); then FLAKES=(); return; fi
    if (( ! $#FLAKES )); then
        for (( i = 0; i < SKY_W / 5; i++ )); do
            FLAKES+=("$(( RANDOM % SKY_W + 1 )) $(( RANDOM % 400 / 100.0 )) 0.$(( RANDOM % 6 + 4 )) ${${:-'*·.'}[RANDOM % 3 + 1]}")
        done
    fi
    for (( i = 1; i <= $#FLAKES; i++ )); do
        f=(${=FLAKES[i]})
        y=$(( f[2] + f[3] * 1.2 * dt ))
        x=$(( f[1] + sin(y * 2 + i) * 0.8 * dt ))
        if (( y >= 4 )); then y=0 x=$(( RANDOM % SKY_W + 1 )); fi
        FLAKES[i]="$x $y $f[3] $f[4]"
    done
}

light_fireworks() {   # seconds -> new rockets burst, old ones fade
    local -F dt=$1 t
    local b
    local -a f keep
    if (( ! SKY_FIREWORKS || SKY_W < 20 )); then BURSTS=(); return; fi
    (( RANDOM % 100 < 5 && $#BURSTS < 4 )) && BURSTS+=("$(( RANDOM % (SKY_W - 12) + 6 )) 0 fw$(( RANDOM % 6 + 1 ))")
    for b in "${BURSTS[@]}"; do
        f=(${=b})
        t=$(( f[2] + dt ))
        (( t < 1.0 )) && keep+=("$f[1] $t $f[3]")
    done
    BURSTS=("${keep[@]}")
}

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
    # Charging: a battery rides on the shell, filling up over and over
    if [[ $S_BATT_STATE == (charging|finishing charge) ]]; then
        local filled=$(( FRAME / 5 % 4 ))
        top="      [${(l:filled::▮:)}${(l:3-filled::▯:)}]ϟ${top[13,-1]}"
        mtop="      bBBBbu${mtop[13,-1]}"
    fi
    # Running hot: beads of sweat fly off its head
    hottest
    if (( speed > 0 )) && [[ -n $REPLY ]] && (( REPLY >= 80 )); then
        if (( FRAME / 4 % 2 )); then
            top="${top[1,13]}  ' " mtop="${mtop[1,13]}  w "
        else
            top="${top[1,13]}   '" mtop="${mtop[1,13]}   w"
            mid="${mid[1,16]}," mmid="${mmid[1,16]}w"
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
    local w=$1 r i k c s m ink prev out night first last stage row piece
    local -a cl
    LANE_W=$w
    sky_state
    night=$SKY_NIGHT
    LANE_CH=()
    for r in 1 2 3 4; do
        if (( night && r <= 2 )); then LANE_CH+=("${(@s::)${(r:w:: :)STARS[r]}}")
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
    for c in "${BURSTS[@]}"; do
        cl=(${=c})
        stage=$(( int(cl[2] / 0.2) ))
        (( stage > 4 )) && stage=4
        for row in 1 2 3; do
            piece=${BURST_STAGES[stage*3+row]}
            [[ -n $piece ]] || continue
            # The last stage fades to the color of the stars
            if (( stage == 4 )); then ink=k; else ink=$cl[3]; fi
            stamp $row $(( cl[1] - (${#piece} - 1) / 2 )) "$piece" $ink
        done
    done
    for c in "${FLAKES[@]}"; do
        cl=(${=c})
        stamp $(( int(cl[2]) + 1 )) $(( int(cl[1]) )) "$cl[4]" f
    done
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
    local w=$1 title=" $2 " acc=$3 l tag=${PANEL_KEY:+" $PANEL_KEY ─"}
    shift 3
    local iw=$(( w - 4 )) dash=$(( w - 3 - ${#title} - ${#tag} ))
    (( dash < 1 )) && { title=" ${title[2,w-8-${#tag}]}… "; dash=$(( w - 3 - ${#title} - ${#tag} )); }
    reply=("${C_FRAME}╭─${C_RESET}${C_BOLD}${acc}${title}${C_RESET}${C_FRAME}${(l:dash::─:)}${tag}╮${C_RESET}")
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
    if (( SPARKS_ON )); then
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
    if (( SPARKS_ON )); then
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
    if (( SPARKS_ON && any )); then
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
    if (( SPARKS_ON )) && [[ -n $S_SYS_WATTS$S_BATT_WATTS ]]; then
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
    if (( SPARKS_ON )); then spark $w 100 PAL_COOL $H_GPU; lines+=("$REPLY"); fi
    reply=("${lines[@]}")
}

rate_line() {   # label rate width palette history... -> "label  1.2M/s  ▁▂▃"
    local label=$1 rate=$2 w=$3 pal=$4 text
    shift 4
    human_rate $rate
    text="${C_GRAY}${(r:9:)label}${C_RESET}${(l:8:)REPLY}"
    if (( ! SPARKS_ON )); then
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

bt_lines() {
    local w=$1 line comp ink n=0
    local -i level
    local -a f parts lines
    if [[ -z $S_BT_POWER ]]; then reply=("${C_GRAY}No Bluetooth on this Mac.${C_RESET}"); return; fi
    if [[ $S_BT_POWER == off ]]; then reply=("${C_GRAY}Bluetooth is off.${C_RESET}"); return; fi
    if [[ -z $S_BT ]]; then reply=("${C_GRAY}No devices connected.${C_RESET}"); return; fi
    for line in "${(@f)S_BT}"; do
        f=("${(@ps:\t:)line}")
        lines+=("${C_BOLD}${f[1]}${C_RESET}${f[2]:+${C_GRAY} · ${(L)f[2]}${C_RESET}}")
        parts=(${=f[3]})
        (( $#parts )) || lines+=("${C_GRAY}connected, no battery reading${C_RESET}")
        for comp in $parts; do
            level=${comp#*=}
            if (( level <= 20 )); then ink=$PAL_HEAT[10]
            elif (( level <= 50 )); then ink=$PAL_HEAT[6]
            else ink=$PAL_HEAT[2]; fi
            labeled_bar "${comp%%=*}" $level $w "$level%" "$ink"
            lines+=("$REPLY")
        done
        (( ++n >= 4 )) && break
    done
    reply=("${lines[@]}")
}

proc_lines() {   # cpu|mem [count] -> reply: the busiest processes with mini bars
    local which=$1 limit=${2:-5} n=0 line mem text pal=PAL_HEAT tag=CPU
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
        (( ++n >= limit )) && break
    done
    reply=("${lines[@]}")
}

fmt_pct() { pct $1; }
fmt_temp() { degrees $1; }
fmt_watts() { printf -v REPLY '%.0fW' ${1:-0}; }
fmt_rate() { human_rate $1; }

typeset -gA CHART_CACHE
chart() {   # width height max palette formatter values... -> reply: an area chart with a y axis
    local w=$1 h=$2 pal=$4 fmt=$5 v r lvl base row lab span pad
    local -F top=$3
    shift 5
    local lw=8 cw=$(( w - 9 ))
    local key="$w $h $pal $fmt $3 $LAST_SEQ $# $THEME $FAHRENHEIT"
    # Charts only change with a new sample, so draw each one once
    if [[ -n ${CHART_CACHE[$key]} ]]; then reply=("${(@f)CHART_CACHE[$key]}"); return; fi
    local -a vals=("$@") ink=("${(@P)pal}") lv
    (( $#vals > cw )) && vals=("${(@)vals[-cw,-1]}")
    if (( top <= 0 )); then
        top=1
        for v in $vals; do (( v > top )) && top=$v; done
    fi
    for v in $vals; do lv+=($(( int(v / top * h * 8 + 0.5) ))); done
    pad=$(( cw - $#lv ))
    reply=()
    for (( r = 1; r <= h; r++ )); do
        base=$(( (h - r) * 8 ))
        row=''
        for lvl in $lv; do
            if (( lvl >= base + 8 )); then row+='█'
            elif (( lvl > base )); then row+=${SPARKS[lvl - base]}
            else row+=' '; fi
        done
        lab=''
        if (( r == 1 )); then $fmt $top; lab=$REPLY
        elif (( r == (h + 1) / 2 )); then $fmt $(( top * (h - r + 1) / h )); lab=$REPLY
        elif (( r == h )); then $fmt 0; lab=$REPLY; fi
        reply+=("${C_GRAY}${(l:lw:)lab}┤${C_RESET}${ink[(h - r) * $#ink / h + 1]}${(l:pad:: :)}${row}${C_RESET}")
    done
    span=$(( cw * INTERVAL ))
    if (( span < 120 )); then lab="${span}s"; else human_duration $span; lab=$REPLY; fi
    lab=" ← ${lab} ago "
    reply+=("${C_GRAY}${(l:lw:)}└─${lab}${(l:cw-${#lab}-6::─:)} now${C_RESET}")
    (( ${#CHART_CACHE} > 12 )) && CHART_CACHE=()
    CHART_CACHE[$key]=${(F)reply}
}

# --- Layout ----------------------------------------------------------------
# Panels are numbered 1-9 and 0 in this order; the numbers hide, show and zoom.

PANELS=(cpu mem temp power gpu net disk sys bt proc)
typeset -gA PANEL_TITLE PANEL_BUILDER HIDDEN
PANEL_TITLE=(cpu "◆ CPU" mem "▦ MEMORY" temp "▲ THERMALS" power "ϟ POWER" gpu "◈ GPU"
             net "⇅ NETWORK" disk "◍ DISK" sys "● SYSTEM" bt "◉ BLUETOOTH" proc "▸ PROCESSES")
PANEL_BUILDER=(cpu cpu_lines mem mem_lines temp temp_lines power power_lines gpu gpu_lines
               net net_lines disk disk_lines sys system_lines bt bt_lines)
ZOOM=""
ZOOM_PICK=0

key_of() { REPLY=$(( ${PANELS[(Ie)$1]} % 10 )); }

typeset -ga OUT
add_block() {   # lines... -> appended to OUT if the whole block still fits
    (( FULL )) && return 1
    if (( $#OUT + $# > MAXL )); then FULL=1; return 1; fi
    OUT+=("$@")
}

pair_row() {   # two panels side by side, padded to the same height
    local a=$1 b=$2 i n
    local -a la lb pa pb lines
    $PANEL_BUILDER[$a] $IW; la=("${reply[@]}")
    $PANEL_BUILDER[$b] $IW; lb=("${reply[@]}")
    n=$(( $#la > $#lb ? $#la : $#lb ))
    while (( $#la < n )); do la+=(''); done
    while (( $#lb < n )); do lb+=(''); done
    key_of $a; PANEL_KEY=$REPLY panel $PW "$PANEL_TITLE[$a]" "$ACCENT[$a]" "${la[@]}"; pa=("${reply[@]}")
    key_of $b; PANEL_KEY=$REPLY panel $PW "$PANEL_TITLE[$b]" "$ACCENT[$b]" "${lb[@]}"; pb=("${reply[@]}")
    for (( i = 1; i <= $#pa; i++ )); do lines+=("${pa[i]} ${pb[i]}"); done
    add_block "${lines[@]}"
}

single_row() {   # name width [extra lines...]
    local p=$1 w=$2
    shift 2
    local -a body
    $PANEL_BUILDER[$p] $(( w - 4 )); body=("${reply[@]}" "$@")
    key_of $p; PANEL_KEY=$REPLY panel $w "$PANEL_TITLE[$p]" "$ACCENT[$p]" "${body[@]}"
    add_block "${reply[@]}"
}

processes_block() {   # count -> both process lists, side by side when there's room
    local -a a b lines
    local i n half count=${1:-5}
    proc_lines cpu $count; a=("${reply[@]}")
    proc_lines mem $count; b=("${reply[@]}")
    if (( TWO )); then
        half=$(( (HW - 4 - 3) / 2 ))
        n=$(( $#a > $#b ? $#a : $#b ))
        for (( i = 1; i <= n; i++ )); do
            fit "${a[i]:-}" $half
            lines+=("$REPLY ${C_FRAME}│${C_RESET} ${b[i]:-}")
        done
        PANEL_KEY=0 panel $HW "$PANEL_TITLE[proc]" "$ACCENT[proc]" "${lines[@]}"
    else
        PANEL_KEY=0 panel $PW "$PANEL_TITLE[proc]" "$ACCENT[proc]" "${a[@]}" "" "${b[@]}"
    fi
    add_block "${reply[@]}"
}

zoom_view() {   # rows -> the zoomed panel at full width, with big graphs
    local H=$1 p=$ZOOM w=$(( HW - 4 )) avail h i n label
    local -a body extra types
    if [[ $p == proc ]]; then processes_block 12; return; fi
    $PANEL_BUILDER[$p] $w; body=("${reply[@]}")
    avail=$(( H - $#OUT - $#body - 3 ))
    (( avail > 24 )) && avail=24
    if (( avail >= 4 )); then
        case $p in
            cpu)
                n=${#${=S_CORE_PCT}}
                h=$(( avail - 2 - (avail - 2 >= n + 4 ? n + 1 : 0) ))
                chart $w $h 100 PAL_HEAT fmt_pct $H_CPU; extra=('' "${reply[@]}")
                if (( avail - 2 >= n + 4 )); then
                    # One sparkline per core, labeled by cluster: E1, E2, …, S1, …
                    extra+=('')
                    local -A seen
                    for (( i = 1; i <= n; i++ )); do
                        label=${S_CORE_TYPES[i]:-·}
                        [[ $label == P ]] && label=${S_PERF_NAME[1]:-P}
                        (( seen[$label]++ ))
                        spark $(( w - 9 )) 100 PAL_HEAT "${(@P)${:-H_CORE_$i}}"
                        extra+=("${C_GRAY}${(l:8:)${:-$label$seen[$label]}} ${C_RESET}$REPLY")
                    done
                fi
                ;;
            mem)   chart $w $(( avail - 2 )) 100 PAL_VIOLET fmt_pct $H_MEM; extra=('' "${reply[@]}") ;;
            temp)  chart $w $(( avail - 2 )) 105 PAL_HEAT fmt_temp $H_TEMP; extra=('' "${reply[@]}") ;;
            power) chart $w $(( avail - 2 )) 0 PAL_WARM fmt_watts $H_WATTS; extra=('' "${reply[@]}") ;;
            gpu)   chart $w $(( avail - 2 )) 100 PAL_COOL fmt_pct $H_GPU; extra=('' "${reply[@]}") ;;
            net|disk)
                h=$(( (avail - 1) / 2 - 2 ))
                if (( h >= 2 )); then
                    if [[ $p == net ]]; then
                        chart $w $h 0 PAL_COOL fmt_rate $H_RX; extra=('' "${C_GRAY}↓ in${C_RESET}" "${reply[@]}")
                        chart $w $h 0 PAL_HEAT fmt_rate $H_TX; extra+=("${C_GRAY}↑ out${C_RESET}" "${reply[@]}")
                    else
                        chart $w $h 0 PAL_COOL fmt_rate $H_DR; extra=('' "${C_GRAY}read${C_RESET}" "${reply[@]}")
                        chart $w $h 0 PAL_VIOLET fmt_rate $H_DW; extra+=("${C_GRAY}write${C_RESET}" "${reply[@]}")
                    fi
                fi
                ;;
        esac
    fi
    key_of $p; PANEL_KEY=$REPLY panel $HW "$PANEL_TITLE[$p]" "$ACCENT[$p]" "${body[@]}" "${extra[@]}"
    add_block "${reply[@]}"
}

build_frame() {   # columns rows -> OUT
    local W=$1 H=$2 title up temp=''
    SPARKS_ON=$(( ! ONCE && ! ${#ZOOM} ))
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
    if [[ -n $ZOOM ]]; then
        SPARKS_ON=0
        zoom_view $H
        return
    fi
    SPARKS_ON=$(( ! ONCE ))
    # Visible panels fill the rows two by two; an odd one out takes the full width
    local p i
    local -a shown
    for p in $PANELS; do
        [[ $p == proc ]] || (( ${HIDDEN[$p]:-0} )) || shown+=($p)
    done
    if (( TWO )); then
        for (( i = 1; i <= $#shown; i += 2 )); do
            if (( i < $#shown )); then pair_row $shown[i] $shown[i+1]; else single_row $shown[i] $HW; fi
        done
    else
        for p in $shown; do single_row $p $PW; done
    fi
    (( ${HIDDEN[proc]:-0} )) || processes_block 5
}

# --- Live mode -------------------------------------------------------------

TOAST="" TOAST_UNTIL=0
toast() { TOAST=$1 TOAST_UNTIL=$(( EPOCHSECONDS + 3 )); }

footer_keys() {   # -> REPLY: the key hints that fit what's on screen
    local out='' name
    local -a hidden
    key() { out+="${C_RESET}${C_REV} $1 ${C_NOREV}${C_GRAY} $2  "; }
    (( EPOCHSECONDS < TOAST_UNTIL )) && out="${C_BOLD}${TOAST}${C_RESET}   "
    if (( ZOOM_PICK )); then
        out+="${C_BOLD}Zoom into which panel?${C_RESET}${C_GRAY} press its number  "
        key z cancel
    elif [[ -n $ZOOM ]]; then
        key z back; key 1…0 'other panels'; key q quit
    else
        key q quit; key p pause; key 1…0 hide/show; key z zoom; key t theme; key f °C/°F
        for name in ${(k)HIDDEN}; do
            (( HIDDEN[$name] )) && { key_of $name; hidden+=($REPLY); }
        done
        (( $#hidden )) && out+="${C_GRAY}hidden: ${(j: :)${(on)hidden}}"
    fi
    unfunction key
    REPLY="$out$C_RESET"
}

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
    local key now last state p paused=0
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
            let_it_snow $dt
            light_fireworks $dt
            move_turtle $dt $(( SKY_W ? SKY_W : COLS - 4 ))
        fi

        build_frame $COLS $(( ROWS - 1 ))
        if (( paused )); then
            state="${C_REV} ❚❚ paused ${C_NOREV}"
        else
            state="${ACCENT[cpu]}${spin[FRAME % $#spin + 1]}${C_RESET} live"
        fi
        footer_keys
        OUT+=(" $state${C_GRAY} · every ${INTERVAL}s · ${S_TIME:-…}   ${C_RESET}$REPLY")
        print -rn -- $'\e[H'"${(pj:\e[K\n:)OUT}"$'\e[K\e[J'

        key=''
        read -s -t 0.08 -k 1 -u $TTY_FD key
        case $key in
            q|Q) break ;;
            p|P|' ') (( paused = !paused )) ;;
            f|F) (( FAHRENHEIT = !FAHRENHEIT )) ;;
            t|T)
                apply_theme $THEMES[$(( ${THEMES[(Ie)$THEME]} % $#THEMES + 1 ))]
                toast "theme: $THEME"
                ;;
            z|Z)
                if [[ -n $ZOOM ]]; then ZOOM=""; else (( ZOOM_PICK = !ZOOM_PICK )); fi
                ;;
            $'\e')
                ZOOM="" ZOOM_PICK=0
                ;;
            [0-9])
                p=$PANELS[$(( key == 0 ? 10 : key ))]
                if (( ZOOM_PICK )) || [[ -n $ZOOM ]]; then
                    ZOOM=$p ZOOM_PICK=0
                elif (( ${HIDDEN[$p]:-0} )); then
                    HIDDEN[$p]=0
                    toast "showing ${PANEL_TITLE[$p]#* }"
                else
                    HIDDEN[$p]=1
                    toast "hid ${PANEL_TITLE[$p]#* }, press $key to bring it back"
                fi
                ;;
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
    sky_state
    make_sky $(( (COLS >= 110 ? (COLS - 1) / 2 * 2 + 1 : (COLS > 84 ? 84 : COLS)) - 4 ))
    let_it_snow 0
    (( SKY_FIREWORKS )) && BURSTS=("$(( SKY_W / 4 )) 0.5 fw1" "$(( SKY_W * 2 / 3 )) 0.3 fw5")
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
        -t|--theme)
            (( ${THEMES[(Ie)${2:-}]} )) || die "--theme needs one of: ${(j:, :)THEMES}"
            THEME=$2
            shift
            ;;
        --sky)
            [[ ${2:-} == (auto|day|night|snow|fireworks) ]] || die "--sky needs one of: auto, day, night, snow, fireworks"
            SKY_MODE=$2
            shift
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

apply_theme $THEME

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
