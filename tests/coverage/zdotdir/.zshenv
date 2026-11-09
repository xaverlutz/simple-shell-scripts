# `make coverage` points ZDOTDIR here so zsh scripts run as commands pick up
# the tracer. It also keeps your own ~/.zshenv out of the test run.
if [[ -n ${COV_ZSH:-} ]]; then
  source "$COV_ZSH"
fi
