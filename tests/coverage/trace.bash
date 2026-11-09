# Line tracer for `make coverage`, bash side.
#
# `make coverage` exports BASH_ENV pointing here, so every non-interactive
# bash sources this file before running its script. Nothing happens unless
# COV_DIR is set too.
#
# $0 is still "bash" while this file runs, so the decision is put off to the
# first DEBUG trap, by which point $0 names the script: a *.sh gets a
# recording trap (functrace carries it into functions and subshells), anything
# else (bats itself, mostly) drops the trap again. Each command then appends
# "file:line" to $COV_DIR/trace. bash 3.2 has no BASH_XTRACEFD, hence a trap
# rather than xtrace, which would mix into the stderr the tests check.

[ -n "${COV_DIR:-}" ] || return 0

__cov_hit() {
  printf '%s:%s\n' "${BASH_SOURCE[1]-}" "${BASH_LINENO[0]-}" >>"$COV_DIR/trace" 2>/dev/null || :
}

# The arming trap runs one call deeper, hence [2] and [1]: it records the
# command it fired for, which would otherwise be missed.
__cov_arm() {
  case $0 in
    *.sh)
      set -o functrace
      trap __cov_hit DEBUG
      printf '%s:%s\n' "${BASH_SOURCE[1]-}" "${BASH_LINENO[0]-}" >>"$COV_DIR/trace" 2>/dev/null || :
      ;;
    *) trap - DEBUG ;;
  esac
}

trap __cov_arm DEBUG
