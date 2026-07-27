#!/usr/bin/env bash

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

echo "Pulling latest changes from git..."
git pull origin main || echo -e "\033[33mWarning: Git pull failed, continuing with local files.\033[0m"

SYMLINK_DIR="$DIR/symlink"

if [ ! -d "$SYMLINK_DIR" ]; then
	echo "Directory not found: $SYMLINK_DIR"
	echo "Exiting..."
	exit 1
fi

echo "Installing zsh config files..."
# Tell bash to include hidden files
shopt -s dotglob

for file in "$SYMLINK_DIR"/*; do
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

LOCAL_RC="$HOME/.zshrc.local"
if [[ ! -f "$LOCAL_RC" ]]; then
	echo "Creating default ~/.zshrc.local..."
	cat <<'EOF' >"$LOCAL_RC"
# --- Local Environment Overrides ---
#ENABLE_PROFILING=true  # Enable profiling to analyze performance
#DEBUG_MODE=true        # Only prints PROFILE, ERROR, and WARNING messages if not set
EOF
fi

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
	echo "Local overrides disabled"
fi

tmp_file=$(mktemp)
cat "$LOCAL_RC" >"$tmp_file"

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

echo -e "\nInstall complete! Run 'exec zsh' or restart your terminal to apply."
