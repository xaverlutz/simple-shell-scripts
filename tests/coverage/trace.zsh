# Line tracer for `make coverage`, zsh side.
#
# Sourced by zdotdir/.zshenv for zsh scripts run as commands, and directly by
# tests that use `zsh -f` (which skips .zshenv). Nothing happens unless
# COV_DIR is set.
#
# A DEBUG trap appends "file:line" for every command to $COV_DIR/trace. Inside
# a function $LINENO counts from the function's first line, and
# $funcsourcetrace[1] gives "file:line" of its definition, so the two add up
# to the line in the file. At the top level of a script %x and $LINENO are
# already right. The trap is an `if` so it never leaves a failing status
# behind for ERR_EXIT to trip over.

[[ -n ${COV_DIR:-} ]] || return 0
exec {__cov_fd}>>"$COV_DIR/trace" || return 0
typeset -g __cov_fd

trap '
  if [[ -n ${funcsourcetrace[1]-} ]]; then
    print -ru $__cov_fd -- "${funcsourcetrace[1]%:*}:$(( ${funcsourcetrace[1]##*:} + LINENO ))"
  else
    print -ru $__cov_fd -- "${(%):-%x}:$LINENO"
  fi
' DEBUG
