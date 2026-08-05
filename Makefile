# simple-shell-scripts
#
#   make install     copy scripts into $(BINDIR), dropping the .sh suffix
#   make link        symlink instead (edits take effect immediately)
#   make uninstall   remove whatever was installed
#   make lint        shellcheck the bash scripts, syntax-check the zsh ones
#                    (stricter: make lint SHELLCHECK_SEVERITY=style)
#
# Override the destination with PREFIX or BINDIR:
#   make install PREFIX=/usr/local
#   make install BINDIR=~/bin

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

# Raise to "style" once the remaining `egrep` in delete_local_branch.sh is
# changed to `grep -E`; "warning" keeps the current tree green.
SHELLCHECK_SEVERITY ?= warning

SCRIPTS := $(sort $(wildcard *.sh))
NAMES   := $(basename $(SCRIPTS))
TARGETS := $(addprefix $(BINDIR)/,$(NAMES))

# Split by interpreter, based on each file's shebang line.
BASH_SCRIPTS := $(shell for f in $(SCRIPTS); do head -1 $$f | grep -q bash && echo $$f; done)
ZSH_SCRIPTS  := $(shell for f in $(SCRIPTS); do head -1 $$f | grep -q zsh  && echo $$f; done)

.DEFAULT_GOAL := help
.PHONY: help install link uninstall lint list path-check

help:
	@echo "Targets:"
	@echo "  install     Copy scripts to $(BINDIR)"
	@echo "  link        Symlink scripts to $(BINDIR)"
	@echo "  uninstall   Remove installed scripts from $(BINDIR)"
	@echo "  lint        Run shellcheck / syntax checks"
	@echo "  list        Show what would be installed"
	@echo
	@echo "Destination: $(BINDIR)   (override with PREFIX= or BINDIR=)"

list:
	@for n in $(NAMES); do echo "  $$n"; done

install: | $(BINDIR)
	@for f in $(SCRIPTS); do \
		n=$${f%.sh}; \
		install -m 0755 "$$f" "$(BINDIR)/$$n"; \
		echo "  installed $$n"; \
	done
	@$(MAKE) --no-print-directory path-check

link: | $(BINDIR)
	@for f in $(SCRIPTS); do \
		n=$${f%.sh}; \
		chmod +x "$$f"; \
		ln -sf "$(CURDIR)/$$f" "$(BINDIR)/$$n"; \
		echo "  linked    $$n -> $(CURDIR)/$$f"; \
	done
	@$(MAKE) --no-print-directory path-check

uninstall:
	@for n in $(NAMES); do \
		if [ -e "$(BINDIR)/$$n" ] || [ -L "$(BINDIR)/$$n" ]; then \
			rm -f "$(BINDIR)/$$n"; \
			echo "  removed   $$n"; \
		fi; \
	done

$(BINDIR):
	@mkdir -p "$(BINDIR)"

# Warn (without failing) if the install dir is not on PATH.
path-check:
	@case ":$$PATH:" in \
		*":$(BINDIR):"*) ;; \
		*) echo; \
		   echo "  NOTE: $(BINDIR) is not on your PATH. Add this to ~/.zshrc:"; \
		   echo "        export PATH=\"$(BINDIR):\$$PATH\""; \
		   ;; \
	esac

lint:
	@fail=0; \
	for f in $(BASH_SCRIPTS); do \
		echo "shellcheck  $$f"; \
		shellcheck -S $(SHELLCHECK_SEVERITY) "$$f" || fail=1; \
	done; \
	if command -v zsh >/dev/null 2>&1; then \
		for f in $(ZSH_SCRIPTS); do \
			echo "zsh -n      $$f"; \
			zsh -n "$$f" || fail=1; \
		done; \
	else \
		echo "zsh not found - skipping $(ZSH_SCRIPTS)"; \
	fi; \
	exit $$fail
