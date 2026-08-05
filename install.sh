#!/usr/bin/env bash

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

# validate input and check for help flag
source "$DIR/usage.sh" "$(basename "$0")" "$@"

# --- Platform Detection ---
IS_WINDOWS=false
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
	IS_WINDOWS=true
fi

printf "Pulling latest changes from git..."
git pull origin main || printf "\033[33mWarning: Git pull failed, continuing with local files.\033[0m"

# Tell bash to include hidden files
shopt -s dotglob

# copy sync-settings to platform location
SYNC_DIR="$DIR/sync-settings"
if [ -d "$SYNC_DIR" ]; then
	if [ -f "$SYNC_DIR"/settings.yml ]; then
		printf "\nCopying sync-settings config...\n"

		printf "# FIXME: platform specific\n"

	else
		printf "\n\033[31m[ERROR]\033[0m unable to locate sync file: %s/settings.yml.\nSkipping...\n" "$SYNC_DIR"
	fi
else
	printf "\n\033[31m[ERROR]\033[0m unable to locate sync directory: %s\nSkipping...\n" "$SYNC_DIR"
fi

# NOTE: keep .exports first
BARE_FILES=("$DIR/.exports" "$DIR/.paths" "$DIR/.curlrc" "$DIR/.wgetrc")
for file in "${BARE_FILES[@]}"; do
	target_path="$file"
	if [ ! -f "$target_path" ]; then
		printf "\033[31m[ERROR]\033[0m file not found: %s\n" "$target_path"
		printf "Exiting...\n"
		exit 1
	fi
done

# git
GIT_DIR="$DIR/git" # TODO: function check_exists
if [ ! -d "$GIT_DIR" ]; then
	printf "\033[31m[ERROR]\033[0m git directory not found: %s\n" "$GIT_DIR"
	printf "Exiting...\n"
	exit 1
fi

# zsh
ZSH_DIR="$DIR/zsh"
if [ ! -d "$ZSH_DIR" ]; then
	printf "\033[31m[ERROR]\033[0m zsh directory not found: %s\n" "$ZSH_DIR"
	printf "Exiting...\n"
	exit 1
fi

# PowerShell (Windows only)
PS1_DIR="$DIR/ps1"

printf "\nInstalling config files...\n"

# --- Install helper: symlink a single file ---
install_file() {
	local src="$1"
	local dest="$2"
	local filename
	filename=$(basename "$src")

	printf "\nInstalling %s...\n" "$filename"

	# Backup existing file or symlink to prevent data loss
	if [ -e "$dest" ] || [ -L "$dest" ]; then
		printf "Found existing %s. Backing up to %s.bak...\n" "$dest" "$dest"
		mv "$dest" "${dest}.bak"
	fi

	if $IS_WINDOWS; then
		# Use mklink on Windows (requires admin)
		if cmd //c mklink "$dest" "$src" 2>/dev/null; then
			printf "Symlinked (mklink): %s -> %s\n" "$dest" "$src"
		else
			# Fallback: copy if mklink fails (no admin)
			printf "\033[33mWarning: mklink failed (need admin?). Copying instead.\033[0m\n"
			cp "$src" "$dest"
			printf "Copied: %s -> %s\n" "$dest" "$src"
		fi
	else
		# Use ln -s on Unix
		ln -s "$src" "$dest"
		printf "Symlinked: %s -> %s\n" "$dest" "$src"
	fi
}

if $IS_WINDOWS; then
	# --- Windows installation ---

	# Bare files -> ~
	for file in "${BARE_FILES[@]}"; do
		install_file "$file" "$HOME/$(basename "$file")"
	done

	# Git config -> ~
	for file in "$GIT_DIR"/*; do
		if [ -f "$file" ]; then
			install_file "$file" "$HOME/$(basename "$file")"
		fi
	done

	# Zsh files -> ~ (for Git Bash usage on Windows)
	for file in "$ZSH_DIR"/*; do
		if [ -f "$file" ]; then
			install_file "$file" "$HOME/$(basename "$file")"
		fi
	done

	# PowerShell profile -> $HOME/Documents/PowerShell/
	if [ -d "$PS1_DIR" ]; then
		PWSH_PROFILE_DIR="$HOME/Documents/PowerShell"
		mkdir -p "$PWSH_PROFILE_DIR"

		printf "\n\033[32mInstalling PowerShell profile...\033[0m\n"
		for file in "$PS1_DIR"/*; do
			if [ -f "$file" ]; then
				filename=$(basename "$file")
				# oh-my-posh config goes to ~/.config/
				if [[ "$filename" == "oh-my-posh.jsonc" ]]; then
					mkdir -p "$HOME/.config"
					dest="$HOME/.config/oh-my-posh.omp.json"
				else
					dest="$PWSH_PROFILE_DIR/$filename"
				fi
				install_file "$file" "$dest"
			fi
		done
	else
		printf "\n\033[33mWarning: PowerShell profile directory not found: %s\nSkipping...\033[0m\n" "$PS1_DIR"
	fi

	# Create local override files
	LOCAL_PATH="$HOME/.paths.local"
	if [[ ! -f "$LOCAL_PATH" ]]; then
		printf "\nCreating empty ~/.paths.local...\n"
		cat <<'EOF' >"$LOCAL_PATH"
#!/usr/bin/env zsh

# --- Local Path Overrides ---
EOF
	else
		printf "\n~/.paths.local already exists. Verifying...\n"
		printf "# TODO: ensure all default values present\n"
	fi

	LOCAL_ZSH="$HOME/.zshrc.local"
	if [[ ! -f "$LOCAL_ZSH" ]]; then
		printf "\nCreating default ~/.zshrc.local...\n"
		cat <<'EOF' >"$LOCAL_ZSH"
#!/usr/bin/env zsh

# --- Local Environment Overrides ---
#ENABLE_PROFILING=true  # Enable profiling to analyze performance
#DEBUG_MODE=true        # Only prints PROFILE, ERROR, and WARNING messages if not set
EOF
	else
		printf "\n~/.zshrc.local already exists. Verifying...\n"
		printf "# TODO: ensure all default values present\n"
	fi

	# PowerShell local overrides
	LOCAL_PS="$HOME/.profile.local.ps1"
	if [[ ! -f "$LOCAL_PS" ]]; then
		printf "\nCreating default .profile.local.ps1...\n"
		cat <<'EOF' >"$LOCAL_PS"
# --- Local PowerShell Overrides ---
#ENABLE_PROFILING=true  # Enable profiling to analyze performance
#DEBUG_MODE=true        # Only prints PROFILE, ERROR, and WARNING messages if not set
EOF
	else
		printf "\n.profile.local.ps1 already exists. Verifying...\n"
		printf "# TODO: ensure all default values present\n"
	fi

	source "$DIR/mode.sh" "$@"

	printf "\n\033[32mInstall complete!\033[0m Run '\033[36mexec zsh\033[0m' (Git Bash) or restart PowerShell to apply.\n"
else
	# --- Unix installation ---

	# NOTE: keep BARE_FILES first
	for file in "${BARE_FILES[@]}" "$GIT_DIR"/* "$ZSH_DIR"/*; do
		if [ -f "$file" ]; then
			install_file "$file" "$HOME/$(basename "$file")"
		fi
	done

	# FIXME: function
	LOCAL_PATH="$HOME/.paths.local"
	if [[ ! -f "$LOCAL_PATH" ]]; then
		printf "\nCreating empty ~/.paths.local...\n"
		cat <<'EOF' >"$LOCAL_PATH"
#!/usr/bin/env zsh

# --- Local Path Overrides ---
EOF
	else
		printf "\n~/.paths.local already exists. Verifying...\n"
		printf "# TODO: ensure all default values present\n"
	fi

	# FIXME: function
	LOCAL_ZSH="$HOME/.zshrc.local"
	if [[ ! -f "$LOCAL_ZSH" ]]; then
		printf "\nCreating default ~/.zshrc.local...\n"
		cat <<'EOF' >"$LOCAL_ZSH"
#!/usr/bin/env zsh

# --- Local Environment Overrides ---
#ENABLE_PROFILING=true  # Enable profiling to analyze performance
#DEBUG_MODE=true        # Only prints PROFILE, ERROR, and WARNING messages if not set
EOF
	else
		printf "\n~/.zshrc.local already exists. Verifying...\n"
		printf "# TODO: ensure all default values present\n"
	fi

	source "$DIR/mode.sh" "$@"

	printf "\n\033[32mInstall complete!\033[0m Run '\033[36mexec zsh\033[0m' or restart your terminal to apply.\n"
fi
