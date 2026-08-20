#!/usr/bin/env bash

if [[ -n "${__BANNER_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __BANNER_SH_INCLUDED__=1

print_banner() {
	local -r bold_cyan="\e[1;36m"
	local -r dark_grey="\e[90m"
	local -r reset="\e[0m"

	echo ""
	printf '%b%s%b\n' \
		"$bold_cyan" '  ____        _    __ _ _           ' "$reset" \
		"$bold_cyan" ' |  _ \  ___ | |_ / _(_) | ___  ___ ' "$reset" \
		"$bold_cyan" ' | | | |/ _ \| __| |_| | |/ _ \/ __|' "$reset" \
		"$bold_cyan" ' | |_| | (_) | |_|  _| | |  __/\__ \' "$reset" \
		"$bold_cyan" ' |____/ \___/ \__|_| |_|_|\___||___/' "$reset" \
		"$dark_grey" ' -----------------------------------' "$reset" \
		"" '   Automated Environment Setup' "" \
		"$dark_grey" ' -----------------------------------' "$reset"

	printf '\n'
	printf '\e[90m  Target : \e[0m%s\n\e[90m  System : \e[0m%s\n\n' "$HOME" "$(uname -sm)"
}

print_banner
unset -f print_banner
