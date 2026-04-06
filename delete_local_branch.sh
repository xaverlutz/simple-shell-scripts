#!/bin/bash

# Colors and formatting
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

log()     { echo -e "${BOLD}▶${RESET} $1"; }
success() { echo -e "${BOLD}${GREEN}✅ $1${RESET}"; }
error()   { echo -e "${BOLD}${RED}❌ $1${RESET}"; }
git_log() { echo -e "${DIM}  $1${RESET}"; }

run_git() {
  git "$@" 2>&1 | while IFS= read -r line; do
    git_log "$line"
  done
  return "${PIPESTATUS[0]}"
}

log "Fetching origin changes ..."
run_git fetch --prune origin

log "Searching for branches to delete ..."
branches=$(git branch -r | awk '{print $1}' | egrep -v -f /dev/fd/0 <(git branch -vv | grep origin) | awk '{print $1}')

if [ -z "$branches" ]; then
  success "No stale branches found — nothing to delete!"
  exit 0
fi

log "The following branches will be deleted:"
while IFS= read -r branch; do
  git_log "$branch"
done <<< "$branches"

echo "$branches" | xargs git branch -D 2>&1 | while IFS= read -r line; do
  git_log "$line"
done

success "Stale branches deleted!"