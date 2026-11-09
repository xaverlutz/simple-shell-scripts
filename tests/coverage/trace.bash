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

# The trap must leave the script's state as it found it. bash restores $?,
# but bash 3.2 lets the trap's own commands overwrite PIPESTATUS, which
# breaks the usual `cmd | filter; return "${PIPESTATUS[0]}"`. So when the
# command about to run reads PIPESTATUS, the trap ends by re-running a
# pipeline of subshells that exit with the saved codes. It has to end in a
# case: if/case keep their last pipeline's PIPESTATUS, a function call or
# eval would not. Those subshells inherit the trap too, and are told apart
# by their command text so they neither record nor touch the saved codes.
# $LINENO counts on through the lines of the trap itself, so it is read on
# the first one.
__cov_trap='__cov_t=("${PIPESTATUS[@]}") __cov_l=$LINENO
case $BASH_COMMAND in
  "exit \"\${__cov_ps["*) ;;
  *)
    __cov_ps=("${__cov_t[@]}")
    printf "%s:%s\n" "${BASH_SOURCE[0]-}" "$__cov_l" >>"$COV_DIR/trace" 2>/dev/null
    case $BASH_COMMAND in
      *PIPESTATUS*)
        case ${#__cov_ps[@]} in
          2) (exit "${__cov_ps[0]}") | (exit "${__cov_ps[1]}") ;;
          3) (exit "${__cov_ps[0]}") | (exit "${__cov_ps[1]}") | (exit "${__cov_ps[2]}") ;;
          4) (exit "${__cov_ps[0]}") | (exit "${__cov_ps[1]}") | (exit "${__cov_ps[2]}") | (exit "${__cov_ps[3]}") ;;
          *) (exit "${__cov_ps[0]}") ;;
        esac
        ;;
    esac
    ;;
esac'

# The arming trap records the command it fired for, which would otherwise be
# missed. It runs one call deeper than the script, hence [1] and [0].
__cov_arm() {
  case $0 in
    *.sh)
      set -o functrace
      trap "$__cov_trap" DEBUG
      printf '%s:%s\n' "${BASH_SOURCE[1]-}" "${BASH_LINENO[0]-}" >>"$COV_DIR/trace" 2>/dev/null || :
      ;;
    *) trap - DEBUG ;;
  esac
}

trap __cov_arm DEBUG
