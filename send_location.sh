#!/bin/zsh

# ---------------------------------------------------------------------------
# send_location.sh — set an iOS Simulator's location from a city name
#
# Usage: ./send_location.sh "City Name" [device_id]
#   With no device_id, the location is sent to ALL booted simulators.
#
# Examples:
#   ./send_location.sh "New York"
#   ./send_location.sh "Paris" "iPhone 15 Pro"
#   ./send_location.sh "Tokyo" "F1B2C3D4-1234-5678-9ABC-DEF012345678"
#
# Set NO_COLOR=1 to disable colored output.
# ---------------------------------------------------------------------------

set -e

# In zsh, $0 inside a function is the *function* name (FUNCTION_ARGZERO is on by
# default), so capture the script name once here at top level.
SCRIPT_NAME=$(basename -- "$0")

# --- Colors ----------------------------------------------------------------
# Only colorize when attached to a terminal, so piped/redirected output stays
# clean. Honors the NO_COLOR convention (https://no-color.org).
C_RESET=""; C_BOLD=""; C_DIM=""
C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GRAY=""

if { [ -t 1 ] || [ -t 2 ]; } && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_GRAY=$'\033[90m'
fi

# --- Output helpers --------------------------------------------------------
# Everything informational goes to stderr so that stdout stays usable for
# command substitution.

banner() {
    printf '%s\n' "${C_CYAN}${C_BOLD}╭──────────────────────────────────────────────╮${C_RESET}" >&2
    printf '%s\n' "${C_CYAN}${C_BOLD}│${C_RESET}  🌍  ${C_BOLD}City Location → iOS Simulator${C_RESET}           ${C_CYAN}${C_BOLD}│${C_RESET}" >&2
    printf '%s\n' "${C_CYAN}${C_BOLD}╰──────────────────────────────────────────────╯${C_RESET}" >&2
}

step()  { printf '%s\n' "${C_BLUE}▸${C_RESET} $*" >&2; }
info()  { printf '%s\n' "${C_GRAY}  $*${C_RESET}" >&2; }
ok()    { printf '%s\n' "${C_GREEN}✔${C_RESET} $*" >&2; }
warn()  { printf '%s\n' "${C_YELLOW}⚠${C_RESET}  $*" >&2; }
die()   { printf '%s\n' "${C_RED}✖${C_RESET}  ${C_RED}$*${C_RESET}" >&2; exit 1; }
rule()  { printf '%s\n' "${C_GRAY}──────────────────────────────────────────────${C_RESET}" >&2; }

# --- Help ------------------------------------------------------------------
usage_text() {
    local me="$SCRIPT_NAME"
    printf '%s\n' "${C_BOLD}${me}${C_RESET} ${C_GRAY}— set an iOS Simulator's location from a city name${C_RESET}"
    printf '\n'
    printf '%s\n' "${C_BOLD}USAGE${C_RESET}"
    printf '  %s\n' "${me} \"City Name\" [device]"
    printf '  %s\n' "${me} --list"
    printf '  %s\n' "${me} --help"
    printf '\n'
    printf '%s\n' "${C_BOLD}ARGUMENTS${C_RESET}"
    printf '  %s%-14s%s %s\n' "$C_CYAN" "City Name" "$C_RESET" "Place to geocode. Add a region to disambiguate,"
    printf '  %s%-14s%s %s\n' ""        ""          ""         "e.g. \"Springfield, Illinois\"."
    printf '  %s%-14s%s %s\n' "$C_CYAN" "device"    "$C_RESET" "Simulator name or UDID. Omit to target ${C_BOLD}all${C_RESET}"
    printf '  %s%-14s%s %s\n' ""        ""          ""         "booted simulators."
    printf '\n'
    printf '%s\n' "${C_BOLD}OPTIONS${C_RESET}"
    printf '  %s%-14s%s %s\n' "$C_CYAN" "-h, --help" "$C_RESET" "Show this help and exit."
    printf '  %s%-14s%s %s\n' "$C_CYAN" "-l, --list" "$C_RESET" "List currently booted simulators and exit."
    printf '  %s%-14s%s %s\n' "$C_CYAN" "-c, --clear" "$C_RESET" "Clear the simulated location instead of setting it."
    printf '\n'
    printf '%s\n' "${C_BOLD}EXAMPLES${C_RESET}"
    printf '  %-42s %s\n' "${me} \"New York\"" "${C_GRAY}# every booted simulator${C_RESET}"
    printf '  %-42s %s\n' "${me} \"Paris\" \"iPhone 15 Pro\"" "${C_GRAY}# one, by name${C_RESET}"
    printf '  %-42s %s\n' "${me} \"Tokyo\" \"F1B2C3D4-...\"" "${C_GRAY}# one, by UDID${C_RESET}"
    printf '  %-42s %s\n' "${me} --clear" "${C_GRAY}# reset all to real location${C_RESET}"
    printf '\n'
    printf '%s\n' "${C_BOLD}ENVIRONMENT${C_RESET}"
    printf '  %s%-14s%s %s\n' "$C_CYAN" "NO_COLOR" "$C_RESET" "Set to any value to disable colored output."
}

# usage <exit_code>: help goes to stdout on success, stderr on error.
usage() {
    local code="${1:-0}"
    if [ "$code" -eq 0 ]; then
        usage_text
    else
        usage_text >&2
    fi
    exit "$code"
}

# --- Globals ---------------------------------------------------------------
CITY_NAME=""
DEVICE_ID=""
CLEAR_MODE=0
LIST_MODE=0

# Matches a simulator UDID, e.g. F1B2C3D4-1234-5678-9ABC-DEF012345678
UUID_RE='[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}'

# Literal tab, used as the field separator in helper output
TAB=$'\t'

# --- Geocoding -------------------------------------------------------------
get_coordinates() {
    local city="$1"
    local encoded_city=$(echo "$city" | sed 's/ /%20/g')
    local url="https://nominatim.openstreetmap.org/search?q=${encoded_city}&format=json&limit=1"

    step "Looking up ${C_BOLD}${city}${C_RESET} ${C_GRAY}(OpenStreetMap Nominatim)${C_RESET}"

    # Nominatim's usage policy requires a descriptive User-Agent.
    local response=$(curl -s -H "User-Agent: send_location.sh/1.0" "$url")

    if [ -z "$response" ] || [ "$response" = "[]" ]; then
        die "City '$city' not found. Try adding a region, e.g. \"Springfield, Illinois\"."
    fi

    # Emit "lat,lon<TAB>display name"
    local parsed=$(echo "$response" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        d = data[0]
        print(d["lat"] + "," + d["lon"], d.get("display_name", ""), sep="\t")
except Exception:
    pass
')

    [ -z "$parsed" ] && die "Could not extract coordinates from the API response."

    local coordinates="${parsed%%$TAB*}"
    local display="${parsed#*$TAB}"

    info "📍 ${coordinates%%,*}, ${coordinates##*,}"
    [ -n "$display" ] && info "🏷  ${display}"

    echo "$coordinates"
}

# --- Simulator discovery ---------------------------------------------------
# Prints "udid<TAB>name" for every booted simulator
get_booted_simulators() {
    xcrun simctl list devices booted -j | python3 -c '
import sys, json
data = json.load(sys.stdin)
for devices in data["devices"].values():
    for d in devices:
        if d.get("state") == "Booted":
            print(d["udid"], d["name"], sep="\t")
'
}

list_booted() {
    local any=0
    while IFS=$'\t' read -r udid name; do
        [ -z "$udid" ] && continue
        printf '     %s%-26s%s %s%s%s\n' \
            "$C_BOLD" "$name" "$C_RESET" "$C_GRAY" "$udid" "$C_RESET" >&2
        any=1
    done < <(get_booted_simulators)
    [ "$any" -eq 0 ] && info "(none)"
}

# --- Sending ---------------------------------------------------------------
# Applies (or clears) the location on one device.
apply_to_device() {
    local udid="$1" lat="$2" lon="$3"
    if [ "$CLEAR_MODE" -eq 1 ]; then
        xcrun simctl location "$udid" clear
    else
        xcrun simctl location "$udid" set "$lat,$lon"
    fi
}

send_location_to_all() {
    local coordinates="$1"
    local lat="${coordinates%%,*}"
    local lon="${coordinates##*,}"
    local count=0

    if [ "$CLEAR_MODE" -eq 1 ]; then
        step "Clearing location on ${C_BOLD}all booted simulators${C_RESET}"
    else
        step "Sending to ${C_BOLD}all booted simulators${C_RESET}"
    fi

    while IFS=$'\t' read -r udid name; do
        [ -z "$udid" ] && continue
        apply_to_device "$udid" "$lat" "$lon"
        printf '  %s📱%s %s%-26s%s %s%s%s  %s✔%s\n' \
            "$C_MAGENTA" "$C_RESET" \
            "$C_BOLD" "$name" "$C_RESET" \
            "$C_GRAY" "$udid" "$C_RESET" \
            "$C_GREEN" "$C_RESET" >&2
        count=$((count + 1))
    done < <(get_booted_simulators)

    if [ "$count" -eq 0 ]; then
        die "No booted simulator found. Boot one first, then try again."
    fi

    echo "$count"
}

send_location_to_simulator() {
    local coordinates="$1"
    local device="$2"
    local lat="${coordinates%%,*}"
    local lon="${coordinates##*,}"

    step "Resolving simulator ${C_BOLD}${device}${C_RESET}"

    # Resolve a device name to a booted UDID; fall back to treating the
    # argument as a UDID itself.
    local match=$(get_booted_simulators | grep -F "$device" | head -1 || true)
    local device_uuid=$(echo "$match" | grep -Eio "$UUID_RE" || true)
    local device_name="${match#*$TAB}"

    if [ -z "$device_uuid" ]; then
        if echo "$device" | grep -Eiq "^$UUID_RE$"; then
            device_uuid="$device"
            device_name="$device"
        else
            warn "No booted simulator matching '${device}'."
            info "Booted simulators:"
            list_booted
            exit 1
        fi
    fi

    apply_to_device "$device_uuid" "$lat" "$lon"
    printf '  %s📱%s %s%-26s%s %s%s%s  %s✔%s\n' \
        "$C_MAGENTA" "$C_RESET" \
        "$C_BOLD" "$device_name" "$C_RESET" \
        "$C_GRAY" "$device_uuid" "$C_RESET" \
        "$C_GREEN" "$C_RESET" >&2

    echo "1"
}

# --- Main ------------------------------------------------------------------
main() {
    banner

    local coordinates="" count

    if [ "$CLEAR_MODE" -eq 0 ]; then
        coordinates=$(get_coordinates "$CITY_NAME")
    fi

    if [ -n "$DEVICE_ID" ]; then
        count=$(send_location_to_simulator "$coordinates" "$DEVICE_ID")
    else
        count=$(send_location_to_all "$coordinates")
    fi

    local plural="s"
    [ "$count" -eq 1 ] && plural=""

    rule
    if [ "$CLEAR_MODE" -eq 1 ]; then
        ok "Simulated location cleared on ${C_BOLD}${count}${C_RESET} simulator${plural} 🧭"
    else
        ok "${C_BOLD}${CITY_NAME}${C_RESET} ${C_GRAY}(${coordinates%%,*}, ${coordinates##*,})${C_RESET} set on ${C_BOLD}${count}${C_RESET} simulator${plural} 🎉"
    fi
}

# --- Argument parsing ------------------------------------------------------
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)  usage 0 ;;
            -l|--list)       LIST_MODE=1; shift ;;
            -c|--clear)      CLEAR_MODE=1; shift ;;
            --)              shift; break ;;
            -*)              printf '%s\n' "${C_RED}✖${C_RESET}  Unknown option: ${C_BOLD}$1${C_RESET}" >&2
                             printf '\n' >&2
                             usage 1 ;;
            *)               break ;;
        esac
    done

    CITY_NAME="${1:-}"
    DEVICE_ID="${2:-}"
}

parse_args "$@"

if [ "$LIST_MODE" -eq 1 ]; then
    banner
    step "Booted simulators"
    list_booted
    exit 0
fi

# A city is required unless we are only clearing.
if [ "$CLEAR_MODE" -eq 0 ] && [ -z "$CITY_NAME" ]; then
    usage 1
fi

main
