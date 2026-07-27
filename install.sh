#!/usr/bin/env bash

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZSH_DIR="$DIR/zsh"

if [ ! -d "$ZSH_DIR" ]; then
	echo "Directory not found: $ZSH_DIR"
	echo "Exiting..."
	exit 1
fi

echo "Installing zsh config files..."
# Tell bash to include hidden files
shopt -s dotglob

for file in "$ZSH_DIR"/*; do
	# Check if the current item is a regular file
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		dest="$HOME/$filename"

		echo "Installing $filename..."
		# Backup existing file or symlink to prevent data loss
		if [ -e "$dest" ] || [ -L "$dest" ]; then
			echo "Found existing $dest. Backing up to ${dest}.bak..."
			mv "$dest" "${dest}.bak"
		fi

		# Create the symlink
		ln -s "$file" "$dest"
		echo "Symlinked: $dest -> $file"
	fi
done

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
if [[ ! -f "$HOME/.zshrc.local" ]]; then
	echo "Warning: No $HOME/.zshrc.local file found!"
	echo "Local overrides disabled (DEBUG_MODE, ENABLE_PROFILING)."
else
	LOCAL_RC="$HOME/.zshrc.local"
	# Create a temporary file to rebuild the config
	tmp_file=$(mktemp)

	if [ "$ENABLE_DEBUG" = true ]; then
		echo "\Debug mode enabled!"
		echo -e "\033[33mUncommenting DEBUG_MODE in ~/.zshrc.local...\033[0m"
		# Removes '#' from the start of the line
		sed 's/^# *DEBUG_MODE=true/DEBUG_MODE=true/' "$LOCAL_RC" >"$tmp_file"
	else
		echo "DEBUG_MODE disabled locally."
		# Adds '#' to the start of the line
		sed 's/^DEBUG_MODE=true/#DEBUG_MODE=true/' "$LOCAL_RC" >"$tmp_file"
	fi

	if [ "$ENABLE_PROFILING" = true ]; then
		echo "\nProfiling enabled!"
		echo -e "\033[33mUncommenting ENABLE_PROFILING in ~/.zshrc.local...\033[0m"
		sed 's/^# *ENABLE_PROFILING=true/ENABLE_PROFILING=true/' "$tmp_file" >"${tmp_file}.tmp" && mv "${tmp_file}.tmp" "$tmp_file"
	else
		echo "ENABLE_PROFILING disabled locally."
		sed 's/^ENABLE_PROFILING=true/#ENABLE_PROFILING=true/' "$tmp_file" >"${tmp_file}.tmp" && mv "${tmp_file}.tmp" "$tmp_file"
	fi

	mv "$tmp_file" "$LOCAL_RC"
fi

echo -e "\nInstall complete! Run 'exec zsh' or restart your terminal to apply."
