#!/usr/bin/env bash

# Toggle .zshrc.local environment overrides

# Check if 'debug' was passed as the first argument
ENABLE_DEBUG=false
ENABLE_PROFILING=false

for arg in "$@"; do
	clean_arg=$(echo "$arg" | tr '[:upper:]' '[:lower:]')

	if [[ "$clean_arg" == "debug" ]]; then
		ENABLE_DEBUG=true
	elif [[ "$clean_arg" == "profile" || "$clean_arg" == "profiling" ]]; then
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