#!/bin/bash

# Colors and formatting
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log()     { echo -e "${BOLD}${CYAN}▶${RESET} $1"; }
success() { echo -e "${BOLD}${GREEN}✅ $1${RESET}"; }
error()   { echo -e "${BOLD}${RED}❌ $1${RESET}"; }
warning() { echo -e "${BOLD}${YELLOW}⚠ $1${RESET}"; }
git_log() { echo -e "${DIM}  $1${RESET}"; }

# Wrap git calls to prefix output
run_git() {
  git "$@" 2>&1 | while IFS= read -r line; do
    git_log "$line"
  done
  return "${PIPESTATUS[0]}"
}

# Usage/help text
show_help() {
  cat <<EOF

$(echo -e "${BOLD}Usage:${RESET}") $(basename "$0") [OPTIONS] <branch-name> [base-branch] [commit-message]

  Create a new git branch from main (or a specified base branch).

$(echo -e "${BOLD}ARGUMENTS:${RESET}")
  branch-name           Name of the new branch to create
  base-branch           Name of the base branch to use (default: "main")
  commit-message        Optional commit message to create an initial commit

$(echo -e "${BOLD}OPTIONS:${RESET}")
  -h, --help            Show this help message and exit
  --on-base-branch      Use the currently checked out branch as the base branch

$(echo -e "${BOLD}EXAMPLES:${RESET}")
  $(basename "$0") my-feature
  $(basename "$0") my-feature develop
  $(basename "$0") my-feature develop "Initial commit"
  $(basename "$0") --on-base-branch my-feature
  $(basename "$0") --on-base-branch my-feature "Initial commit"

EOF
}

# Parse flags
use_current_branch=false

args=()
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
    --on-base-branch)
      use_current_branch=true
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

# Empty branch name should just print help
if [[ -z "${args[0]}" ]]; then
  show_help
  exit 0
fi

branch_name="${args[0]}"
commit_message="${args[1]}"

# Determine base branch
if [ "$use_current_branch" = "true" ]; then
  base_branch="$(git branch --show-current)"
  log "Using current branch '${BOLD}${base_branch}${RESET}' as base 🌿"
else
  base_branch="${args[1]:-main}"
  commit_message="${args[2]}"
fi

# Check if the feature branch exists
if git branch -l | grep -q "$branch_name"; then
  error "The branch '${branch_name}' already exists!"
  exit 1
fi

# Fetch origin
log "Fetching origin changes ..."
run_git fetch --prune origin

# Ensure that we are on the base branch ...
log "Switching to '${BOLD}${base_branch}${RESET}' ..."
run_git checkout "$base_branch"

# ... pull any changes ...
log "Pulling latest changes ..."
run_git pull origin "$base_branch"

log "'${BOLD}${base_branch}${RESET}' is up to date 🔁"

# ... and create new branch
log "Creating branch '${BOLD}${branch_name}${RESET}' ..."
run_git checkout -b "$branch_name"

# Optional commit message
if [ -n "$commit_message" ]; then
  log "Creating initial commit ..."
  run_git commit -m "$commit_message"
fi

success "Branch '${branch_name}' created successfully!"