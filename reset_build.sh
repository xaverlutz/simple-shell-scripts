#!/bin/bash

# Colors and formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log()     { echo -e "${BOLD}${CYAN}▶${RESET} $1"; }
success() { echo -e "${BOLD}${GREEN}✅ $1${RESET}"; }
error()   { echo -e "${BOLD}${RED}❌ $1${RESET}"; }
warning() { echo -e "${BOLD}${YELLOW}⚠ $1${RESET}"; }

show_help() {
  cat <<EOF

$(echo -e "${BOLD}Usage:${RESET}") $(basename "$0") [OPTIONS]

  Delete the .build folder in the current directory.

$(echo -e "${BOLD}OPTIONS:${RESET}")
  -h, --help    Show this help message and exit

$(echo -e "${BOLD}EXAMPLES:${RESET}")
  $(basename "$0")

EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
  esac
done

if [ -d ".build" ]; then
  log "Deleting .build folder ..."
  rm -rf .build
  success ".build folder deleted!"
else
  warning ".build folder not found — nothing to delete."
fi
