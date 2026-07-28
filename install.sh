#!/usr/bin/env bash

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

echo "Pulling latest changes from git..."
git pull origin main || echo -e "\033[33mWarning: Git pull failed, continuing with local files.\033[0m"

# Tell bash to include hidden files
shopt -s dotglob

# copy sync-settings to platform location
SYNC_DIR= "$DIR/sync-settings"
if [ -d "$SYNC_DIR" ]; then
	if [ -f "$SYNC_DIR"/settings.yml ]; then
		echo "Copying sync-settings config..."

		echo "# FIXME: platform specific"

	else
		echo "Error: unable to locate sync file: $SYNC_DIR/settings.yml.\nSkipping."
		continue
	fi
else
	echo "Error: unable to locate sync directory: $SYNC_DIR\nSkipping."
fi

# NOTE: keep .exports first
BARE_FILES=("$DIR/.exports" "$DIR/.paths" "$DIR/.curlrc" "$DIR/.wgetrc")
for file in "${BARE_FILES[@]}"; do
	target_path="$file"
	if [ ! -f $target_path ]; then
		echo "[ERROR] file not found: $target_path"
		echo "Exiting..."
		exit 1
	fi
done

# git
GIT_DIR="$DIR/git" # TODO: function check_exists
if [ ! -d "$GIT_DIR" ]; then
	echo "[ERROR] git directory not found: $GIT_DIR"
	echo "Exiting..."
	exit 1
fi

# zsh
ZSH_DIR="$DIR/zsh"
if [ ! -d "$ZSH_DIR" ]; then
	echo "[ERROR] zsh directory not found: $ZSH_DIR"
	echo "Exiting..."
	exit 1
fi

echo "Installing config files..."
# NOTE: keep BARE_FILES first
for file in "${BARE_FILES[@]}" "$GIT_DIR"/* "$ZSH_DIR"/*; do
	# Check if the current item is a regular file
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		dest="$HOME/$filename"

		# Special handling for .gitconfig
		if [ "$filename" = ".gitconfig" ]; then
			if [ -f "$dest" ]; then
				echo "Updating $dest while preserving the first 8 lines..."
				# Extract the first 8 lines from the existing destination file
				# and append everything from the new template file starting from line 9 onward
				{
					head -n 8 "$dest"
					tail -n +9 "$file"
				} >"${dest}.tmp" && mv "${dest}.tmp" "$dest"
				continue
			else
				echo "Installing initial .gitconfig..."
				cp "$file" "$dest"
				continue
			fi
		fi

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
