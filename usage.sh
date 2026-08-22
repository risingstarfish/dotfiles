#!/usr/bin/env bash
# usage.sh

set -euo pipefail

if [[ -n "${__USAGE_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __USAGE_SH_INCLUDED__=1
###################
# get the absolute directory path of this script
# Source - https://stackoverflow.com/a/246128
# Posted by dogbane, modified by community. See post 'Timeline' for change history
# Retrieved 2026-08-20, License - CC BY-SA 4.0
get_script_dir() {
	local source_path="${BASH_SOURCE[0]}"
	local symlink_dir
	local script_dir
	# Resolve symlinks recursively
	while [ -L "$source_path" ]; do
		# Get symlink directory
		symlink_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
		# Resolve symlink target (relative or absolute)
		source_path="$(readlink "$source_path")"
		# Check if candidate path is relative or absolute
		if [[ $source_path != /* ]]; then
			# Candidate path is relative, resolve to full path
			source_path=$symlink_dir/$source_path
		fi
	done
	# Get final script directory path from fully resolved source path
	script_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
	# Return failure if the directory couldn't be resolved
	[[ -z "$script_dir" ]] && return 1
	printf "%s\n" "$script_dir"
}

if [[ -z "${SCRIPT_DIR:-}" ]]; then
	SCRIPT_DIR="$(get_script_dir)" || {
		printf "\n\e[31m[ERROR]\e[0m Failed to resolve script directory. Exiting...\n" >&2
		exit 1
	}
	readonly SCRIPT_DIR
fi

unset -f get_script_dir

cd "$SCRIPT_DIR" || {
	printf "\e[31m[ERROR]\e[0m Failed to enter root directory: %s\n" "$SCRIPT_DIR" >&2
	exit 1
}

print_usage() {
	# If a script name is passed as $1, use it. Otherwise, default to the file's own name.
	local target_script="${1:-$(basename "$0")}"

	printf "Usage: bash %s [debug|profile]\n" "$target_script"
	echo ""
	printf "Options:\n"
	#printf "  -o, --os <type>          Force install for specific OS (linux, win-bash, mac, wsl)\n"
	printf "  -d, --enable-debug       Enable debug mode\n"
	printf "  -p, --enable-profiling   Enable profiling mode\n"
	printf "  -h, --help               Show this help message\n"
}

# check if the script is being executed directly rather than sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	###################
	# print banner
	if [[ -f "$SCRIPT_DIR/lib/banner.sh" ]]; then
		source "$SCRIPT_DIR/lib/banner.sh"
	fi
	print_usage
	exit 0
fi

# $1 = the name of the calling script (e.g., install.sh or mode.sh)
SCRIPT_NAME="$1"
shift # remove script_name from array

# potentially contains user's parameters
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		print_usage "$SCRIPT_NAME"
		exit 0
		;;
	-d | --enable-debug | -p | --enable-profiling)
		shift
		;;
	*)
		printf "\e[31m[ERROR]\e[0m Invalid parameter: %s\n" "$1" >&2
		printf "Run \e[36m'bash %s --help'\e[0m for valid options.\n" "$(basename "$0")" >&2
		exit 1
		;;
	esac
done

unset -f print_usage
