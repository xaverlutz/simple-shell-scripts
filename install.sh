#!/bin/bash

# Install or update simple-shell-scripts on this Mac.
#
#   Fresh Mac:  bash -c "$(curl -fsSL https://raw.githubusercontent.com/xaverlutz/simple-shell-scripts/main/install.sh)"
#   Update:     update_shell_scripts
#
# Run from a checkout (or via the update_shell_scripts symlink), it updates and
# relinks that checkout. Piped in from curl, it clones into
# $SIMPLE_SHELL_SCRIPTS_DIR (default ~/.local/share/simple-shell-scripts).
#
# Each clone remembers its update channel in its git config:
#   release   newest vX.Y.Z tag (default for fresh installs)
#   main      tip of main
#   pinned    stay on the tag given with --tag
# A checkout with no channel set (e.g. one you develop in) just pulls its
# current branch.
#
# --only narrows an install to some scripts with a sparse checkout and
# remembers the pick in git config, too; --all widens it back. A checkout you
# develop in is left whole.

set -euo pipefail

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
warning() { echo -e "${BOLD}${YELLOW}⚠ $1${RESET}"; }
git_log() { echo -e "${DIM}  $1${RESET}"; }

run_git() {
  git "$@" 2>&1 | while IFS= read -r line; do
    git_log "$line"
  done
  return "${PIPESTATUS[0]}"
}

REPO_URL="${SIMPLE_SHELL_SCRIPTS_REPO:-https://github.com/xaverlutz/simple-shell-scripts.git}"
DEFAULT_BINDIR="$HOME/.local/bin"
BINDIR="${BINDIR:-$DEFAULT_BINDIR}"
CHANNEL_KEY="simple-shell-scripts.channel"
ONLY_KEY="simple-shell-scripts.only"

show_help() {
  cat <<EOF

$(echo -e "${BOLD}Usage:${RESET}") $(basename "$0") [OPTIONS]

  Install simple-shell-scripts, or update an existing install.
  Clones (or updates) the repo, then symlinks its scripts into BINDIR:
  all of them, or the ones picked with --only.
  By default a fresh install follows the newest release tag (vX.Y.Z).

$(echo -e "${BOLD}OPTIONS:${RESET}")
  --release     Follow the newest release tag (remembered)
  --main        Follow the tip of main (remembered)
  --tag <tag>   Pin to a specific tag, e.g. v1.2.0 (remembered)
  --only <names>
                Check out and link only these scripts, e.g.
                --only send_location or --only create_branch,reset_build
                (remembered; replaces the previous selection)
  --all         Check out and link every script again (the default)
  -h, --help    Show this help message and exit

$(echo -e "${BOLD}ENVIRONMENT:${RESET}")
  BINDIR                      Where to link the scripts (default: ~/.local/bin)
  SIMPLE_SHELL_SCRIPTS_DIR    Where to clone on a fresh install
                              (default: ~/.local/share/simple-shell-scripts)

EOF
}

# Directory this script really lives in, following symlinks. Empty when the
# script is read from stdin or `bash -c`.
script_dir() {
  local path="${BASH_SOURCE[0]:-}" target
  [ -n "$path" ] && [ -f "$path" ] || return 0
  while [ -L "$path" ]; do
    target=$(readlink "$path")
    case "$target" in
      /*) path="$target" ;;
      *)  path="$(dirname "$path")/$target" ;;
    esac
  done
  (cd "$(dirname "$path")" && pwd -P)
}

pull_latest() {
  local dir="$1" before after

  if ! git -C "$dir" symbolic-ref -q HEAD >/dev/null \
    || ! git -C "$dir" rev-parse -q --verify '@{u}' >/dev/null; then
    warning "$dir is not on a tracking branch — skipping pull"
    return 0
  fi

  before=$(git -C "$dir" rev-parse HEAD)
  log "Pulling latest changes into $dir ..."
  if ! run_git -C "$dir" pull --ff-only; then
    warning "Could not fast-forward $dir — relinking what is there"
    return 0
  fi
  after=$(git -C "$dir" rev-parse HEAD)

  if [ "$before" != "$after" ]; then
    run_git -C "$dir" log --oneline "$before..$after"
  fi
}

# Newest stable release tag (vX.Y.Z, no pre-release suffix), or nothing.
latest_tag() {
  git -C "$1" tag -l 'v[0-9]*' --sort=-v:refname | grep -v -- '-' | head -1 || true
}

checkout_ref() {
  local dir="$1" ref="$2" before after

  if ! git -C "$dir" rev-parse -q --verify "$ref^{commit}" >/dev/null; then
    error "No such tag or branch: $ref"
    exit 1
  fi

  before=$(git -C "$dir" rev-parse HEAD)
  after=$(git -C "$dir" rev-parse "$ref^{commit}")
  if [ "$before" = "$after" ] && ! git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
    git_log "Already at $ref."
    return 0
  fi

  log "Switching to $ref ..."
  if ! run_git -C "$dir" -c advice.detachedHead=false checkout -q "$ref"; then
    warning "Could not check out $ref in $dir — relinking what is there"
    return 0
  fi
  if [ "$before" != "$after" ]; then
    run_git -C "$dir" log --oneline "$before..$after"
  fi
}

update_repo() {
  local dir="$1" channel="$2" pin="$3" tag

  case "$channel" in
    release)
      log "Fetching releases ..."
      run_git -C "$dir" fetch --quiet --tags origin || warning "Fetch failed — using local tags"
      tag=$(latest_tag "$dir")
      if [ -z "$tag" ]; then
        warning "No release tags yet — staying at $(git -C "$dir" describe --tags --always)"
      else
        checkout_ref "$dir" "$tag"
      fi
      ;;
    main)
      if [ "$(git -C "$dir" symbolic-ref -q --short HEAD || true)" != "main" ]; then
        log "Switching to main ..."
        run_git -C "$dir" checkout -q main
      fi
      pull_latest "$dir"
      ;;
    pinned)
      if [ -n "$pin" ]; then
        run_git -C "$dir" fetch --quiet --tags origin || warning "Fetch failed — using local tags"
        checkout_ref "$dir" "$pin"
      else
        git_log "Pinned at $(git -C "$dir" describe --tags --always) — run with --release or --main to unpin."
      fi
      ;;
    *)
      pull_latest "$dir"
      ;;
  esac
}

# User scripts in the checked-out commit, by name, one per line.
available_scripts() {
  git -C "$1" ls-tree --name-only HEAD | sed -n 's/\.sh$//p' | grep -vx install || true
}

# Scripts the install is narrowed to, space-separated; empty for all.
selected_scripts() {
  git -C "$1" config --get "$ONLY_KEY" || true
}

# Fail unless every name is a script in the checked-out commit.
check_scripts() {
  local dir="$1" names="$2" available name
  available=$(available_scripts "$dir")
  for name in $names; do
    if ! grep -qxF -- "$name" <<<"$available"; then
      error "No script named $name. Available: $(paste -sd ' ' - <<<"$available")"
      return 1
    fi
  done
}

# Check out only the installer and the given scripts, or everything with
# "all". Uses the core.sparseCheckout file, which every git version reads the
# same way, instead of `git sparse-checkout`, whose options keep changing.
sparse_checkout() {
  local dir="$1" names="$2" gitdir name file
  gitdir=$(git -C "$dir" rev-parse --absolute-git-dir)
  file="$gitdir/info/sparse-checkout"

  # read-tree resets the index to HEAD, which would drop staged changes.
  # Unstaged edits survive, and files that have them stay checked out.
  if [ -f "$gitdir/index" ] && ! git -C "$dir" diff --cached --quiet; then
    error "$dir has staged changes. Commit or unstage them first."
    exit 1
  fi

  mkdir -p "$gitdir/info"
  if [ "$names" = all ]; then
    printf '/*\n' >"$file"
  else
    printf '/install.sh\n/Makefile\n' >"$file"
    for name in $names; do
      printf '/%s.sh\n' "$name" >>"$file"
    done
    git -C "$dir" config core.sparseCheckout true
    git -C "$dir" config core.sparseCheckoutCone false
  fi
  run_git -C "$dir" read-tree -mu HEAD

  if [ "$names" = all ]; then
    git -C "$dir" config core.sparseCheckout false
    rm -f "$file"
  fi
}

# Warn about unselected scripts that local edits kept in the working tree:
# `make link` links whatever is there.
warn_kept_scripts() {
  local dir="$1" names="$2" f name
  for f in "$dir"/*.sh; do
    name=$(basename "$f" .sh)
    case " install $names " in
      *" $name "*) ;;
      *) warning "Kept $name.sh because it has local changes, so it stays linked" ;;
    esac
  done
}

# Put BINDIR on PATH for future shells. Only touches ~/.zshrc for the default
# location; a custom BINDIR is the caller's business.
ensure_path() {
  case ":$PATH:" in *":$BINDIR:"*) return 0 ;; esac

  if [ "$BINDIR" != "$DEFAULT_BINDIR" ]; then
    warning "$BINDIR is not on your PATH"
    return 0
  fi

  local rc="$HOME/.zshrc"
  # shellcheck disable=SC2016  # written literally, expanded by zsh later
  local line='export PATH="$HOME/.local/bin:$PATH"'
  if ! grep -qsF "$line" "$rc"; then
    log "Adding ~/.local/bin to PATH in $rc ..."
    printf '\n# simple-shell-scripts\n%s\n' "$line" >>"$rc"
  fi
  warning "Open a new terminal (or run: source $rc) to pick up the PATH change"
}

main() {
  local requested="" pin="" only="" before name

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      --release)
        requested="release"
        ;;
      --main)
        requested="main"
        ;;
      --tag)
        if [ -z "${2:-}" ]; then
          error "--tag needs a tag name, e.g. --tag v1.2.0"
          exit 1
        fi
        requested="pinned"
        pin="$2"
        shift
        ;;
      --only)
        if [ "$only" = all ]; then
          only=""
        fi
        before="$only"
        case "${2:-}" in
          *[!A-Za-z0-9_.,-]*) ;;
          *)
            for name in $(tr ',' ' ' <<<"${2:-}"); do
              name="${name%.sh}"
              if [ -n "$name" ]; then
                only="${only:+$only }$name"
              fi
            done
            ;;
        esac
        if [ "$only" = "$before" ]; then
          error "--only needs script names, e.g. --only send_location"
          exit 1
        fi
        shift
        ;;
      --all)
        only="all"
        ;;
      *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done

  for tool in git make; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      error "$tool not found. Install the Xcode Command Line Tools: xcode-select --install"
      exit 1
    fi
  done

  local dir fresh="" channel
  dir=$(script_dir)

  if [ -z "$dir" ] || [ ! -e "$dir/.git" ] || [ ! -f "$dir/Makefile" ]; then
    dir="${SIMPLE_SHELL_SCRIPTS_DIR:-$HOME/.local/share/simple-shell-scripts}"
    if [ ! -e "$dir/.git" ]; then
      log "Cloning $REPO_URL into $dir ..."
      mkdir -p "$(dirname "$dir")"
      if [ -n "$only" ] && [ "$only" != all ]; then
        # Start from just the installer and fetch file contents only as they
        # are checked out; the chosen scripts are added once they are checked.
        run_git clone --quiet --no-checkout --filter=blob:none "$REPO_URL" "$dir"
        sparse_checkout "$dir" ""
      else
        run_git clone --quiet "$REPO_URL" "$dir"
      fi
      fresh=1
      requested="${requested:-release}"
    fi
  fi

  channel="${requested:-$(git -C "$dir" config --get "$CHANNEL_KEY" || true)}"
  if [ -n "$only" ] && [ "$only" != all ] && [ -z "$channel" ]; then
    error "$dir has no update channel, so it looks like a checkout you develop in. --only would hide its other files; add --release or --main to treat it as an install."
    exit 1
  fi

  # Remember a requested channel only once switching to it has worked.
  update_repo "$dir" "$channel" "$pin"
  if [ -n "$requested" ]; then
    git -C "$dir" config "$CHANNEL_KEY" "$requested"
  fi

  if [ "$only" = all ]; then
    if [ "$(git -C "$dir" config --bool --get core.sparseCheckout || true)" = true ]; then
      log "Checking out all scripts ..."
      sparse_checkout "$dir" all
    fi
    git -C "$dir" config --unset "$ONLY_KEY" || true
  elif [ -n "$only" ]; then
    if ! check_scripts "$dir" "$only"; then
      if [ -n "$fresh" ]; then
        rm -rf "$dir"
        git_log "Removed the new clone at $dir."
      fi
      exit 1
    fi
    log "Checking out only $only ..."
    sparse_checkout "$dir" "$only"
    git -C "$dir" config "$ONLY_KEY" "$only"
    warn_kept_scripts "$dir" "$only"
  fi

  log "Linking scripts into $BINDIR ..."
  # BINDIR on make's PATH silences its path-check note; ensure_path covers that.
  PATH="$BINDIR:$PATH" make --no-print-directory -C "$dir" link BINDIR="$BINDIR" | while IFS= read -r line; do
    git_log "$line"
  done

  ensure_path
  local selected
  selected=$(selected_scripts "$dir")
  success "simple-shell-scripts is at $(git -C "$dir" describe --tags --always)${selected:+ (only $selected)}. Run update_shell_scripts to update again."
}

# Exit on the same line: this file may be swapped for another version mid-run.
main "$@"; exit $?
