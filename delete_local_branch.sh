#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# delete_local_branch.sh — delete local branches whose upstream is gone
#
# Fetches with --prune, then removes local branches whose tracked remote
# branch no longer exists. Branches without an upstream are never touched.
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME=$(basename -- "$0")

# --- Colors ----------------------------------------------------------------
BOLD=""; DIM=""; GREEN=""; RED=""; YELLOW=""; CYAN=""; RESET=""
if { [ -t 1 ] || [ -t 2 ]; } && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'
  GREEN=$'\033[0;32m'; RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'; RESET=$'\033[0m'
fi

log()     { printf '%s\n' "${BOLD}${CYAN}▶${RESET} $1"; }
success() { printf '%s\n' "${BOLD}${GREEN}✅ $1${RESET}"; }
error()   { printf '%s\n' "${BOLD}${RED}❌ $1${RESET}" >&2; }
warning() { printf '%s\n' "${BOLD}${YELLOW}⚠ $1${RESET}"; }
git_log() { printf '%s\n' "${DIM}  $1${RESET}"; }

# --- Options ---------------------------------------------------------------
REMOTE="origin"
DRY_RUN=false
FORCE=false
ASSUME_YES=false
DO_FETCH=true

show_help() {
  cat <<EOF

${BOLD}Usage:${RESET} ${SCRIPT_NAME} [OPTIONS]

  Delete local branches whose upstream branch no longer exists on the remote.
  Branches with no upstream configured are always left alone.

${BOLD}OPTIONS:${RESET}
  -h, --help            Show this help message and exit
  -n, --dry-run         List what would be deleted, then exit
  -f, --force           Use 'git branch -D', deleting unmerged branches too
  -y, --yes             Do not ask for confirmation
      --no-fetch        Skip 'git fetch --prune' (use the current refs)
      --remote <name>   Remote to check against (default: origin)

${BOLD}EXAMPLES:${RESET}
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --dry-run
  ${SCRIPT_NAME} --force --yes
  ${SCRIPT_NAME} --remote upstream

EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    show_help; exit 0 ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    -f|--force)   FORCE=true; shift ;;
    -y|--yes)     ASSUME_YES=true; shift ;;
    --no-fetch)   DO_FETCH=false; shift ;;
    --remote)
      [ $# -ge 2 ] || { error "--remote requires a value"; exit 1; }
      REMOTE="$2"; shift 2 ;;
    *)
      error "Unknown argument: $1"
      show_help >&2
      exit 1 ;;
  esac
done

# --- Preconditions ---------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  error "Not inside a git repository."
  exit 1
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  error "Remote '${REMOTE}' does not exist."
  exit 1
fi

# --- Find branches whose upstream is gone ----------------------------------
if [ "$DO_FETCH" = true ]; then
  log "Fetching ${BOLD}${REMOTE}${RESET} changes ..."
  git fetch --prune "$REMOTE" 2>&1 | while IFS= read -r line; do
    git_log "$line"
  done
fi

log "Searching for branches to delete ..."

# %(upstream:track) is literally "[gone]" when the tracked branch is missing.
# --format avoids the "* " current-branch marker that plain `git branch` adds.
candidates=$(
  git for-each-ref --format='%(refname:short)%09%(upstream:track)%09%(upstream:remotename)' refs/heads \
    | awk -F'\t' -v remote="$REMOTE" '$2 == "[gone]" && $3 == remote { print $1 }'
)

# `git branch --show-current` needs git 2.22+; rev-parse works everywhere.
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
branches=()
skipped_current=""

while IFS= read -r branch; do
  [ -z "$branch" ] && continue
  if [ "$branch" = "$current_branch" ]; then
    skipped_current="$branch"
    continue
  fi
  branches+=("$branch")
done <<< "$candidates"

if [ -n "$skipped_current" ]; then
  warning "Skipping '${skipped_current}' — it is the current branch."
fi

if [ ${#branches[@]} -eq 0 ]; then
  success "No stale branches found — nothing to delete!"
  exit 0
fi

log "The following branches will be deleted:"
for branch in "${branches[@]}"; do
  git_log "$branch"
done

if [ "$DRY_RUN" = true ]; then
  warning "Dry run — nothing was deleted."
  exit 0
fi

# --- Confirm ---------------------------------------------------------------
if [ "$ASSUME_YES" != true ]; then
  if [ ! -t 0 ]; then
    error "Refusing to delete without confirmation. Re-run with --yes (or --dry-run)."
    exit 1
  fi
  printf '%s' "${BOLD}Delete ${#branches[@]} branch(es)? [y/N] ${RESET}"
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) warning "Aborted — nothing was deleted."; exit 1 ;;
  esac
fi

# --- Delete ----------------------------------------------------------------
delete_flag="-d"
[ "$FORCE" = true ] && delete_flag="-D"

failed=0
for branch in "${branches[@]}"; do
  if output=$(git branch "$delete_flag" "$branch" 2>&1); then
    git_log "$output"
  else
    failed=$((failed + 1))
    if [ "$FORCE" != true ]; then
      warning "Kept '${branch}' — not fully merged. Use --force to delete it anyway."
    else
      error "Could not delete '${branch}': $output"
    fi
  fi
done

if [ "$failed" -gt 0 ]; then
  warning "Deleted $(( ${#branches[@]} - failed )) of ${#branches[@]} branch(es)."
  exit 1
fi

success "Stale branches deleted!"
