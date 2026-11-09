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

# Run a git step through run_git, and stop if it fails, so a failed checkout
# or pull never ends in a branch off the wrong base and a success message.
git_step() {
  local what="$1"; shift
  if ! run_git "$@"; then
    error "${what} failed — no branch was created."
    exit 1
  fi
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

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  error "Not inside a git repository."
  exit 1
fi

# Determine base branch
if [ "$use_current_branch" = "true" ]; then
  # `git branch --show-current` needs git 2.22+; symbolic-ref works everywhere.
  base_branch="$(git symbolic-ref --quiet --short HEAD)"
  if [ -z "$base_branch" ]; then
    error "Not on a branch (detached HEAD), so --on-base-branch has no base to use."
    exit 1
  fi
  log "Using current branch '${BOLD}${base_branch}${RESET}' as base 🌿"
else
  base_branch="${args[1]:-main}"
  commit_message="${args[2]}"
fi

# Check if the feature branch exists. An exact ref lookup: grepping
# `git branch` matched any branch containing the name.
if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
  error "The branch '${branch_name}' already exists!"
  exit 1
fi

# Fetch origin
log "Fetching origin changes ..."
git_step "Fetching origin" fetch --prune origin

# Ensure that we are on the base branch ...
log "Switching to '${BOLD}${base_branch}${RESET}' ..."
git_step "Switching to '${base_branch}'" checkout "$base_branch"

# ... pull any changes, if the base branch exists on origin at all ...
if git show-ref --verify --quiet "refs/remotes/origin/${base_branch}"; then
  log "Pulling latest changes ..."
  git_step "Pulling '${base_branch}'" pull origin "$base_branch"
  log "'${BOLD}${base_branch}${RESET}' is up to date 🔁"
else
  warning "'${base_branch}' is not on origin — using the local branch as it is."
fi

# ... and create new branch
log "Creating branch '${BOLD}${branch_name}${RESET}' ..."
git_step "Creating '${branch_name}'" checkout -b "$branch_name"

# Optional commit message. --allow-empty, since a freshly created branch
# usually has nothing staged and the commit would otherwise fail.
if [ -n "$commit_message" ]; then
  log "Creating initial commit ..."
  if ! run_git commit --allow-empty -m "$commit_message"; then
    error "Branch '${branch_name}' was created, but the initial commit failed."
    exit 1
  fi
fi

success "Branch '${branch_name}' created successfully!"