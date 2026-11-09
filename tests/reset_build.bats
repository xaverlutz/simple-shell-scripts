#!/usr/bin/env bats
#
# Tests for reset_build.sh
#
#   bats tests/
#
# Every test runs in a throwaway directory, so nothing near your real
# projects is touched.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../reset_build.sh"
  TMP="$(mktemp -d)"
  cd "$TMP"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# A .build folder with some nested content, like SwiftPM leaves behind.
make_build_dir() {
  mkdir -p "${1:-.}/.build/debug/Module.build"
  echo "artifact" > "${1:-.}/.build/debug/Module.build/main.o"
}

# --- Core behaviour --------------------------------------------------------

@test "deletes the .build folder in the current directory" {
  make_build_dir
  touch Package.swift

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e .build ]
  [ -f Package.swift ]
  [[ "$output" == *".build folder deleted"* ]]
}

@test "warns and exits 0 when there is no .build folder" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to delete"* ]]
}

@test "only looks in the current directory, not in subfolders" {
  make_build_dir "nested"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -d nested/.build ]
  [[ "$output" == *"nothing to delete"* ]]
}

# --- Safety ----------------------------------------------------------------

@test "leaves a file named .build alone" {
  echo "not a folder" > .build

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f .build ]
}

@test "removes a .build symlink without emptying the folder it points to" {
  make_build_dir "elsewhere"
  ln -s elsewhere/.build .build

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e .build ] && [ ! -L .build ]
  [ -f elsewhere/.build/debug/Module.build/main.o ]
}

@test "rejects unknown arguments without deleting anything" {
  # A typo like `reset_build --dry-run` must not go ahead and delete.
  make_build_dir

  run "$SCRIPT" --dry-run
  [ "$status" -eq 1 ]
  [ -d .build ]
  [[ "$output" == *"Unknown argument: --dry-run"* ]]
}

# --- Help ------------------------------------------------------------------

@test "--help prints usage and deletes nothing" {
  make_build_dir

  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [ -d .build ]
  [[ "$output" == *"Usage:"* ]]
}
