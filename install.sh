#!/usr/bin/env bash

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZSH_DIR="$DIR/zsh"

echo "Installing zsh config files..."
if [ ! -d "$ZSH_DIR" ]; then
	echo "[ERROR] Directory not found: $ZSH_DIR"
	exit 1
fi

for file in "$ZSH_DIR"/*; do
	# Check if the current item is a regular file
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		dest="$HOME/$filename"

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

echo -e "\nInstall complete! Run 'exec zsh' or restart your terminal to apply."
