#!/usr/bin/env bash
# Toggle .zshrc.local environment overrides

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

# validate input and check for help flag
source "$DIR/usage.sh" "$(basename "$0")" "$@"

# Set default path if not already provided by an external script
LOCAL_ZSH="$HOME/.local/.zshrc"
if [[ ! -f "$LOCAL_ZSH" ]]; then
	printf "\033[31m[ERROR]\033[0m $HOME/.local/.zshrc could not be found.\n"
	printf "Run \033[36mbash install.sh\033[0m' first before attempting to change the mode/variables.\n"
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

# --- Handle Local Overrides ---
if [ ! "$ENABLE_DEBUG" = true ] && [ ! "$ENABLE_PROFILING" = true ]; then
	printf "Local overrides disabled\n"
fi

tmp_file=$(mktemp)
cat "$LOCAL_ZSH" >"$tmp_file"

if [ "$ENABLE_DEBUG" = true ]; then
	printf "\nDebug mode enabled!\n"
	printf "\033[33mUncommenting DEBUG_MODE in ~/.zshrc.local...\033[0m\n"
	# Removes '#' from the start of the line
	sed 's/^# *DEBUG_MODE=true/DEBUG_MODE=true/' "$LOCAL_ZSH" >"$tmp_file"
else
	printf "\nDEBUG_MODE disabled locally.\n"
	# Adds '#' to the start of the line
	sed 's/^DEBUG_MODE=true/#DEBUG_MODE=true/' "$LOCAL_ZSH" >"$tmp_file"
fi

if [ "$ENABLE_PROFILING" = true ]; then
	printf "\nProfiling enabled!\n"
	printf "\033[33mUncommenting ENABLE_PROFILING in ~/.zshrc.local...\033[0m\n"
	sed 's/^# *ENABLE_PROFILING=true/ENABLE_PROFILING=true/' "$tmp_file" >"${tmp_file}.tmp" && mv "${tmp_file}.tmp" "$tmp_file"
else
	printf "\nENABLE_PROFILING disabled locally.\n"
	sed 's/^ENABLE_PROFILING=true/#ENABLE_PROFILING=true/' "$tmp_file" >"${tmp_file}.tmp" && mv "${tmp_file}.tmp" "$tmp_file"
fi

mv "$tmp_file" "$LOCAL_ZSH"
