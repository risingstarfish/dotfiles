#!/usr/bin/env bash
# mode.sh

# Toggle .zshrc.local environment overrides

set -euo pipefail

if [[ -n "${__MODE_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __MODE_SH_INCLUDED__=1
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
	printf "\e[31m[ERROR]\e[0m Failed to enter root directory: %s. Exiting...\n" "$SCRIPT_DIR" >&2
	exit 1
}
###################
# print banner
if [[ -f "$SCRIPT_DIR/lib/banner.sh" ]]; then
	source "$SCRIPT_DIR/lib/banner.sh"
fi

source "$SCRIPT_DIR/lib/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "log.sh" || exit 1
unset -f source_deps

if [[ -z "${LOCAL_ZSH:-}" ]]; then
	declare -r LOCAL_ZSH="$HOME/.zshrc.local"
fi

# validate input and check for help flag
source "$SCRIPT_DIR/usage.sh" "$(basename "$0")" "$@" || exit 1

###############
# main

log::step "Validating environment"

# Set default path if not already provided by an external script
if [[ ! -f "$LOCAL_ZSH" ]]; then
	log::error "$LOCAL_ZSH could not be found."
	log::error "Run \e[36m'bash install.sh'\e[0m first before attempting to change the mode/variables."
	exit 1
fi

log::success "Found local configuration: $LOCAL_ZSH"
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

log::step "Applying configuration toggles"

tmp_file=$(mktemp)
cat "$LOCAL_ZSH" >"$tmp_file"

for toggle in "${TOGGLES[@]}"; do
	var_name="${toggle%%:*}"
	enabled="${toggle##*:}"

	old_content="$(cat "$tmp_file")"

	echo ""
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

	rm -f "${tmp_file}.bak"
done

mv "$tmp_file" "$LOCAL_ZSH"
