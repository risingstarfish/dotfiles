#!/usr/bin/env bash

print_usage() {
	# If a script name is passed as $1, use it. Otherwise, default to the file's own name.
	local target_script="${1:-$(basename "$0")}"

	printf "Usage: bash %s [debug|profile]\n\n" "$target_script"
	printf "Options:\n"
	printf "  -d, --enable-debug       Enable debug mode\n"
	printf "  -p, --enable-profiling   Enable profiling mode\n"
	printf "  -h, --help               Show this help message\n"
}

# check if the script is being executed directly rather than sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	print_usage
	exit 0
fi

# $1 = the name of the calling script (e.g., install.sh or mode.sh)
SCRIPT_NAME="$1"
shift # remove script_name from array

# $@ potentially contains user's parameters
for arg in "$@"; do
	case "$arg" in
	-h | --help)
		print_usage "$SCRIPT_NAME"
		exit 0
		;;
	-d | --enable-debug | -p | --enable-profiling)
		# continue
		;;
	*)
		printf "\e[31m[ERROR]\e[0m Invalid parameter: %s\n" "$arg"
		printf "Run \e[36m'bash %s --help'\e[0m for valid options.\n" "$(basename "$0")"
		exit 1
		;;
	esac
done
