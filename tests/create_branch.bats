#!/usr/bin/env bats
#
# Tests for create_branch.sh
#
#   bats tests/
#
# Every test runs against a throwaway repo with a local bare "remote", so
# nothing touches the network or your real branches. A second clone stands in
# for a teammate pushing work the script should pull.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../create_branch.sh"
  TMP="$(mktemp -d)"
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1

  git config --global user.email "test@example.com"
  git config --global user.name "Test"
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false
  git config --global pull.ff only

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

# Push a commit to $1 on the remote from a separate clone, as a teammate
# would. The branch is created on the remote if it doesn't exist yet.
push_from_elsewhere() {
  local branch="$1" subject="$2"
  [ -d "$TMP/other" ] || git clone -q "$TMP/remote.git" "$TMP/other"
  (
    cd "$TMP/other"
    git fetch -q origin
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git checkout -q -B "$branch" "origin/$branch"
    else
      git checkout -q -B "$branch" origin/main
    fi
    echo "$subject" >> work.txt
    git add . && git commit -qm "$subject"
    git push -q origin "$branch"
  )
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

current_branch() {
  git rev-parse --abbrev-ref HEAD
}

subject_of() {
  git log -1 --format=%s "$1"
}

# --- Core behaviour --------------------------------------------------------

@test "creates the branch from main with the latest remote commits" {
  push_from_elsewhere main "teammate work"

  run "$SCRIPT" feature
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
  [ "$(subject_of feature)" = "teammate work" ]
  [ "$(subject_of main)" = "teammate work" ]
  [[ "$output" == *"created successfully"* ]]
}

@test "branches off main even when started on another branch" {
  git checkout -q -b other
  echo "local" > local.txt
  git add . && git commit -qm "local only"

  run "$SCRIPT" feature
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
  ! git merge-base --is-ancestor other feature
}

@test "uses the base branch given as the second argument" {
  push_from_elsewhere develop "develop work"

  # develop only exists on the remote; checkout picks up origin/develop.
  run "$SCRIPT" feature develop
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
  [ "$(subject_of feature)" = "develop work" ]
}

@test "creates an initial commit when given a message" {
  run "$SCRIPT" feature main "Start the feature"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
  [ "$(subject_of feature)" = "Start the feature" ]
  [ "$(git rev-parse feature~1)" = "$(git rev-parse main)" ]
}

# --- --on-base-branch ------------------------------------------------------

@test "--on-base-branch branches off the current branch after pulling it" {
  git checkout -q -b topic
  git push -q -u origin topic
  push_from_elsewhere topic "topic work"

  run "$SCRIPT" --on-base-branch feature
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
  [ "$(subject_of feature)" = "topic work" ]
}

@test "--on-base-branch takes the commit message as the second argument" {
  git checkout -q -b topic
  git push -q -u origin topic

  run "$SCRIPT" --on-base-branch feature "Start the feature"
  [ "$status" -eq 0 ]
  [ "$(subject_of feature)" = "Start the feature" ]
  [ "$(git rev-parse feature~1)" = "$(git rev-parse topic)" ]
}

@test "--on-base-branch works on a branch that was never pushed" {
  git checkout -q -b local-topic
  echo "local" > local.txt
  git add . && git commit -qm "local topic work"

  run "$SCRIPT" --on-base-branch feature
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
  [ "$(subject_of feature)" = "local topic work" ]
  [[ "$output" == *"not on origin"* ]]
}

@test "--on-base-branch refuses to run on a detached HEAD" {
  git checkout -q --detach

  run "$SCRIPT" --on-base-branch feature
  [ "$status" -eq 1 ]
  ! branch_exists feature
  [[ "$output" == *"Not on a branch"* ]]
}

# --- Regressions -----------------------------------------------------------

@test "refuses a branch name that already exists" {
  git branch feature

  run "$SCRIPT" feature
  [ "$status" -eq 1 ]
  [ "$(current_branch)" = "main" ]
  [[ "$output" == *"already exists"* ]]
}

@test "creates a branch whose name is part of an existing one" {
  # The old check grepped `git branch -l` for the name, so an existing
  # feature-login blocked creating feature.
  git branch feature-login

  run "$SCRIPT" feature
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "feature" ]
}

@test "treats dots in the name literally when checking for an existing branch" {
  git branch fix-1x2

  run "$SCRIPT" fix-1.2
  [ "$status" -eq 0 ]
  branch_exists fix-1.2
}

@test "stops without creating a branch when the base branch doesn't exist" {
  # The old script ignored the failed checkout and branched off whatever
  # was checked out, then reported success.
  run "$SCRIPT" feature nope
  [ "$status" -eq 1 ]
  ! branch_exists feature
  [ "$(current_branch)" = "main" ]
  [[ "$output" != *"created successfully"* ]]
}

@test "stops when the base branch can't be fast-forwarded" {
  push_from_elsewhere main "teammate work"
  echo "mine" > mine.txt
  git add . && git commit -qm "diverging local work"

  run "$SCRIPT" feature
  [ "$status" -eq 1 ]
  ! branch_exists feature
  [[ "$output" != *"is up to date"* ]]
}

# --- Help and environment --------------------------------------------------

@test "prints usage and creates nothing without a branch name" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [ "$(git branch --format='%(refname:short)')" = "main" ]
}

@test "--help prints usage even with other arguments" {
  run "$SCRIPT" feature --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  ! branch_exists feature
}

@test "errors when run outside a git repository" {
  cd "$TMP"
  run "$SCRIPT" feature
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not inside a git repository"* ]]
}
