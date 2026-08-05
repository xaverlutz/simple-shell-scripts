#!/usr/bin/env bats
#
# Tests for delete_local_branch.sh
#
#   bats tests/
#
# Every test runs against a throwaway repo with a local bare "remote", so
# nothing touches the network or your real branches.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../delete_local_branch.sh"
  TMP="$(mktemp -d)"
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export NO_COLOR=1

  git config --global user.email "test@example.com"
  git config --global user.name "Test"
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false

  git init -q --bare "$TMP/remote.git"
  git clone -q "$TMP/remote.git" "$TMP/work"
  cd "$TMP/work"

  echo "initial" > README.md
  git add . && git commit -qm "initial commit"
  git push -q -u origin main
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Create a branch, push it, then delete it on the remote so its upstream is
# "gone". $2, if given, is a commit subject making the branch unmerged.
make_gone_branch() {
  local name="$1" subject="${2:-}"
  git checkout -q -b "$name"
  if [ -n "$subject" ]; then
    echo "$name" > "$name.txt"
    git add . && git commit -qm "$subject"
  fi
  git push -q -u origin "$name"
  git checkout -q main
  git push -q origin --delete "$name"
}

# Create a purely local branch with no upstream at all.
make_local_branch() {
  local name="$1" subject="${2:-work in progress}"
  git checkout -q -b "$name"
  echo "$name" > "$name.txt"
  git add . && git commit -qm "$subject"
  git checkout -q main
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

# --- Regressions -----------------------------------------------------------

@test "keeps a local branch whose commit message contains 'origin'" {
  # The old pipeline grepped for "origin" across the whole `git branch -vv`
  # line, so a commit subject mentioning origin got the branch force-deleted.
  make_local_branch "wip-local" "fix origin remote url"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  branch_exists "wip-local"
}

@test "keeps local branches that never had an upstream" {
  make_local_branch "scratch"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  branch_exists "scratch"
  [[ "$output" == *"No stale branches found"* ]]
}

@test "deletes a gone branch whose name is a prefix of a live remote branch" {
  # Old code matched remote names as regex substrings, so a live origin/feature
  # masked a gone origin/feature-2.
  git checkout -q -b feature
  git push -q -u origin feature
  git checkout -q main
  make_gone_branch "feature-2"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  ! branch_exists "feature-2"
  branch_exists "feature"
}

@test "never passes the '*' current-branch marker to git branch" {
  make_gone_branch "stale"
  make_local_branch "current-work"
  git checkout -q current-work

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"branch '*' not found"* ]]
  branch_exists "current-work"
}

# --- Core behaviour --------------------------------------------------------

@test "deletes a branch whose upstream is gone" {
  make_gone_branch "stale"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  ! branch_exists "stale"
  [[ "$output" == *"Stale branches deleted"* ]]
}

@test "reports success when there is nothing to delete" {
  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"No stale branches found"* ]]
}

@test "skips the current branch even when its upstream is gone" {
  make_gone_branch "stale" "some work"
  git checkout -q stale

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  branch_exists "stale"
  [[ "$output" == *"current branch"* ]]
}

@test "deletes several stale branches in one run" {
  make_gone_branch "stale-1"
  make_gone_branch "stale-2"
  make_gone_branch "stale-3"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  ! branch_exists "stale-1"
  ! branch_exists "stale-2"
  ! branch_exists "stale-3"
}

@test "handles branch names containing slashes" {
  make_gone_branch "feature/JIRA-123"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 0 ]
  ! branch_exists "feature/JIRA-123"
}

# --- Unmerged work ---------------------------------------------------------

@test "keeps an unmerged branch and exits non-zero" {
  make_gone_branch "unmerged" "unpushed work"

  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 1 ]
  branch_exists "unmerged"
  [[ "$output" == *"not fully merged"* ]]
}

@test "--force deletes an unmerged branch" {
  make_gone_branch "unmerged" "unpushed work"

  run "$SCRIPT" --no-fetch --yes --force
  [ "$status" -eq 0 ]
  ! branch_exists "unmerged"
}

# --- Flags -----------------------------------------------------------------

@test "--dry-run lists branches without deleting them" {
  make_gone_branch "stale"

  run "$SCRIPT" --no-fetch --dry-run
  [ "$status" -eq 0 ]
  branch_exists "stale"
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"Dry run"* ]]
}

@test "refuses to delete non-interactively without --yes" {
  make_gone_branch "stale"

  run "$SCRIPT" --no-fetch </dev/null
  [ "$status" -eq 1 ]
  branch_exists "stale"
  [[ "$output" == *"--yes"* ]]
}

@test "--help exits 0 and prints usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "rejects unknown arguments" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "--remote only considers the named remote" {
  git init -q --bare "$TMP/other.git"
  git remote add upstream "$TMP/other.git"
  make_gone_branch "stale-origin"

  # stale-origin tracks origin, so checking upstream should leave it alone.
  run "$SCRIPT" --no-fetch --yes --remote upstream
  [ "$status" -eq 0 ]
  branch_exists "stale-origin"
}

@test "errors on an unknown remote" {
  run "$SCRIPT" --no-fetch --yes --remote nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

# --- Environment -----------------------------------------------------------

@test "errors when run outside a git repository" {
  cd "$TMP"
  run "$SCRIPT" --no-fetch --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not inside a git repository"* ]]
}

@test "emits no ANSI escapes when output is not a terminal" {
  make_gone_branch "stale"

  run "$SCRIPT" --no-fetch --yes
  [[ "$output" != *$'\033['* ]]
}
