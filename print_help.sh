#!/usr/bin/env bash

readonly ALL_MODULES=(
	"shells/zsh"
	"shells/bash"
	"apps/git"
	"apps/ssh"
	"apps/curl"
	"apps/oh-my-posh"
	"apps/shellcheck"
	"apps/tmux"
	"apps/wget"
	"apps/iterm2"
)

print_help() {
	cat <<EOF

MODULES
  -i, --install <module>    Run only for the specified modules, semicolon-separated
  -x, --exclude <module>    Run for all modules EXCEPT those specified, semicolon-separated
  -l, --list                List all available modules

AVAILABLE MODULES
  shells
    zsh           | bash

  apps
    git           | ssh          | curl        | oh-my-posh   | shellcheck
    tmux          | wget         | iterm2

EOF
	# 14 wide
}
