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
error()   { echo -e "${BOLD}${RED}❌ $1${RESET}" >&2; }
warning() { echo -e "${BOLD}${YELLOW}⚠ $1${RESET}" >&2; }
git_log() { echo -e "${DIM}  $1${RESET}"; }

# Wrap git calls to prefix output
run_git() {
  git "$@" 2>&1 | while IFS= read -r line; do
    git_log "$line"
  done
  return "${PIPESTATUS[0]}"
}

# Where the script started, so a failure before the new branch exists can
# put the user back there instead of leaving them on the base branch.
start_ref=""

# Run a git step through run_git, and stop if it fails, so a failed checkout
# or pull never ends in a branch off the wrong base and a success message.
# $1 is the error to show; the rest is the git command.
git_step() {
  local message="$1"; shift
  if ! run_git "$@"; then
    error "$message"
    if [ -n "$start_ref" ]; then
      if git checkout -q "$start_ref" -- >/dev/null 2>&1; then
        warning "Switched back to '${start_ref}'."
      else
        warning "Still on '$(git symbolic-ref --quiet --short HEAD || git rev-parse --short HEAD)' — could not switch back to '${start_ref}'."
      fi
    fi
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
    -*)
      # A typo'd option must not end up as a branch name, or reach
      # `git checkout` as an option (`-f` would discard local changes).
      error "Unknown option: $arg"
      show_help >&2
      exit 1
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

if ! git check-ref-format --branch "$branch_name" >/dev/null 2>&1; then
  error "'${branch_name}' is not a valid branch name."
  exit 1
fi

# Check if the feature branch exists. An exact ref lookup: grepping
# `git branch` matched any branch containing the name.
if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
  error "The branch '${branch_name}' already exists!"
  exit 1
fi

# Fetch origin. Without an origin, or offline, carry on with the local base
# branch rather than refusing to branch at all.
fetched=false
if ! git remote get-url origin >/dev/null 2>&1; then
  warning "No 'origin' remote — using the local '${base_branch}' as it is."
else
  log "Fetching origin changes ..."
  if run_git fetch --prune origin; then
    fetched=true
  else
    warning "Could not fetch origin — using the local '${base_branch}' as it is."
  fi
fi

# Ensure that we are on the base branch ... The `--` makes git take the base
# as a branch only: without it, a name that is not a branch but matches a
# file or folder checks that path out, throwing away local edits there.
orig_ref="$(git symbolic-ref --quiet --short HEAD || git rev-parse --short HEAD)"
log "Switching to '${BOLD}${base_branch}${RESET}' ..."
git_step "Could not switch to '${base_branch}' — no branch was created." \
  checkout "$base_branch" --
[ "$orig_ref" = "$base_branch" ] || start_ref="$orig_ref"

# ... fast-forward it to origin, if it is there at all. --ff-only, so a base
# branch that has diverged stops the script cleanly instead of leaving a
# merge or rebase half done ...
if [ "$fetched" = "true" ] && git show-ref --verify --quiet "refs/remotes/origin/${base_branch}"; then
  log "Pulling latest changes ..."
  git_step "Could not fast-forward '${base_branch}' to origin — no branch was created." \
    pull --ff-only origin "$base_branch"
  log "'${BOLD}${base_branch}${RESET}' is up to date 🔁"
elif [ "$fetched" = "true" ]; then
  warning "'${base_branch}' is not on origin — using the local branch as it is."
fi

# ... and create new branch
log "Creating branch '${BOLD}${branch_name}${RESET}' ..."
git_step "Could not create '${branch_name}' — no branch was created." \
  checkout -b "$branch_name"
start_ref=""

# Optional commit message. --allow-empty, since a freshly created branch
# usually has nothing staged and the commit would otherwise fail.
if [ -n "$commit_message" ]; then
  log "Creating initial commit ..."
  git_step "Branch '${branch_name}' was created, but the initial commit failed." \
    commit --allow-empty -m "$commit_message"
fi

success "Branch '${branch_name}' created successfully!"
