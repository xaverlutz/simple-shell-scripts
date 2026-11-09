# Line tracer for `make coverage`, zsh side.
#
# Sourced by zdotdir/.zshenv for zsh scripts run as commands, and directly by
# tests that use `zsh -f` (which skips .zshenv). Nothing happens unless
# COV_DIR is set.
#
# TRAPDEBUG runs before every command and appends "file:line" to
# $COV_DIR/trace. $funcfiletrace[1] is where the trap was triggered from,
# that is the command about to run, as a line in its file. The function form
# matters: a `trap '...' DEBUG` list overwrites $pipestatus for the command
# that follows, the function form leaves it (and $?) alone. It always returns
# 0: a TRAPDEBUG that returns non-zero makes a script with ERR_EXIT exit.

[[ -n ${COV_DIR:-} ]] || return 0
exec {__cov_fd}>>"$COV_DIR/trace" || return 0
typeset -g __cov_fd

TRAPDEBUG() {
  print -ru $__cov_fd -- "${funcfiletrace[1]-}" 2>/dev/null
  return 0
}
