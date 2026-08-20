#!/usr/bin/env bash
# Toggle .zshrc.local environment overrides

# define DIR if it has not been already set
if [[ -z "${DIR:-}" ]]; then
	DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
		printf "\n\e[31m[ERROR]\e[0m Failed to resolve script directory. Exiting...\n"
		exit 1
	}
	declare -r DIR
fi

cd "$DIR" || exit 1

require_lib() {
	local -r lib_name="$1"
	local -r lib_path="$LIB_DIR/$lib_name"

	if [[ ! -f "$lib_path" ]]; then
		printf "\e[31m[ERROR]\e[0m Missing required dependency: %s is required by %s\n" "$lib_name" "$(basename "${BASH_SOURCE[1]}")" >&2
		return 1
	fi

	# --- INCLUDE GUARD ---
	# Determine a unique identifier function or variable for the library to check if it's loaded
	case "$lib_name" in
	log.sh)
		# If log::error already exists, skip sourcing log.sh completely
		declare -F log::error >/dev/null 2>&1 && return 0
		;;
	common.sh)
		# If INVALID_TOKEN is already set, skip sourcing common.sh completely
		[[ -n "${INVALID_TOKEN:-}" ]] && return 0
		;;
	filesystem.sh)
		declare -F filesystem::symlink >/dev/null 2>&1 && return 0
		;;
	git.sh)
		declare -F git::get_credential_helper >/dev/null 2>&1 && return 0
		;;
	template.sh)
		declare -F template::install >/dev/null 2>&1 && return 0
		;;
	esac

	source "$lib_path"
}

require_lib "log.sh" || exit 1
require_lib "common.sh" || exit 1

if [[ -z "${LOCAL_ZSH:-}" ]]; then
	declare -r LOCAL_ZSH="$HOME/.zshrc.local"
fi

# validate input and check for help flag
source "usage.sh" "$(basename "$0")" "$@"

# Set default path if not already provided by an external script
if [[ ! -f "$LOCAL_ZSH" ]]; then
	log::error "$LOCAL_ZSH could not be found."
	printf "Run \e[36m'bash install.sh'\e[0m first before attempting to change the mode/variables.\n"
	exit 1
fi

# Check if 'debug' was passed as the first argument
ENABLE_DEBUG=false
ENABLE_PROFILING=false

for arg in "$@"; do
	#clean_arg=$(echo "$arg" | tr '[:upper:]' '[:lower:]')
	if [[ "$arg" == "--enable-debug" || "$arg" == "-d" ]]; then
		ENABLE_DEBUG=true
	elif [[ "$arg" == "--enable-profiling" || "$arg" == "-p" ]]; then
		ENABLE_PROFILING=true
	fi
done

# zsh toggles
declare -a TOGGLES=(
	"DEBUG_MODE:$ENABLE_DEBUG"
	"ENABLE_PROFILING:$ENABLE_PROFILING"
)

tmp_file=$(mktemp)
cat "$LOCAL_ZSH" >"$tmp_file"

for toggle in "${TOGGLES[@]}"; do
	var_name="${toggle%%:*}"
	enabled="${toggle##*:}"

	old_content="$(cat "$tmp_file")"

	if [[ "$enabled" == true ]]; then
		log::success "${var_name} enabled!"
		# uncomment the line
		sed -i.bak "s/^# *${var_name}=true/${var_name}=true/" "$tmp_file"
	else
		log::info "${var_name} disabled locally."
		# comment out the line
		sed -i.bak "s/^${var_name}=true/#${var_name}=true/" "$tmp_file"
	fi

	new_content="$(cat "$tmp_file")"

	# Check if sed actually changed anything
	if [[ "$old_content" != "$new_content" ]]; then
		log::success "${var_name} successfully updated."
	else
		log::info "${var_name} was already in the requested state (no changes made)."
	fi

	# Clean up sed backup file if created
	rm -f "${tmp_file}.bak"
done

mv "$tmp_file" "$LOCAL_ZSH"
