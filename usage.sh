#!/usr/bin/env bash

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
	local SOURCE_PATH="${BASH_SOURCE[0]}"
	local SYMLINK_DIR
	local SCRIPT_DIR
	# Resolve symlinks recursively
	while [ -L "$SOURCE_PATH" ]; do
		# Get symlink directory
		SYMLINK_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
		# Resolve symlink target (relative or absolute)
		SOURCE_PATH="$(readlink "$SOURCE_PATH")"
		# Check if candidate path is relative or absolute
		if [[ $SOURCE_PATH != /* ]]; then
			# Candidate path is relative, resolve to full path
			SOURCE_PATH=$SYMLINK_DIR/$SOURCE_PATH
		fi
	done
	# Get final script directory path from fully resolved source path
	SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
	# Return failure if the directory couldn't be resolved
	[[ -z "$SCRIPT_DIR" ]] && return 1
	printf "%s\n" "$SCRIPT_DIR"
}

if [[ -z "${ROOT_DIR:-}" ]]; then
	ROOT_DIR="$(get_script_dir)" || {
		printf "\n\e[31m[ERROR]\e[0m Failed to resolve script directory. Exiting...\n" >&2
		exit 1
	}
	readonly ROOT_DIR
fi

unset -f get_script_dir

cd "$ROOT_DIR" || {
	printf "\e[31m[ERROR]\e[0m Failed to enter root directory: %s\n" "$ROOT_DIR" >&2
	exit 1
}

print_usage() {
	# If a script name is passed as $1, use it. Otherwise, default to the file's own name.
	local target_script="${1:-$(basename "$0")}"

	printf "Usage: bash %s [debug|profile]\n" "$target_script"
	echo ""
	printf "Options:\n"
	printf "  -d, --enable-debug       Enable debug mode\n"
	printf "  -p, --enable-profiling   Enable profiling mode\n"
	printf "  -h, --help               Show this help message\n"
}

# check if the script is being executed directly rather than sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	###################
	# print banner
	if [[ -f "$ROOT_DIR/lib/banner.sh" ]]; then
		source "$ROOT_DIR/lib/banner.sh"
	fi
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
		printf "\e[31m[ERROR]\e[0m Invalid parameter: %s\n" "$arg" >&2
		printf "Run \e[36m'bash %s --help'\e[0m for valid options.\n" "$(basename "$0")" >&2
		exit 1
		;;
	esac
done

unset -f print_usage
