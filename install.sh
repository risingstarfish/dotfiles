#!/usr/bin/env bash

###################
# functions

prompt_continue() {
	local prompt_message="${1:-Do you want to continue? (y/n): }"

	while true; do
		read -p "$prompt_message" choice
		case "$choice" in
		[Yy]*)
			break
			;;
		[Nn]*)
			printf "Exiting script...\n"
			exit 1
			;;
		*)
			printf "Please answer yes (y) or no (n).\n"
			;;
		esac
	done
}

# Get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

if [[ ! -f "$DIR/usage.sh" ]]; then
	printf "\n\033[31m[ERROR]\033[0m unable to locate usage file that should be located at '%s'\n" "$DIR/usage.sh]]"
	printf "        you may need to reset the git repo or create one yourself"
else
	# validate input and check for help flag
	source "$DIR/usage.sh" "$(basename "$0")" "$@"
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

# template
TEMPLATE_DIR="$DIR/template"
if [ ! -d "$TEMPLATE_DIR" ]; then
	printf "\033[31m[ERROR]\033[0m template directory not found: %s\n" "$TEMPLATE_DIR"
	printf "Exiting...\n"
	exit 1
fi

printf "\nInstalling config files...\n"
# NOTE: keep BARE_FILES first
for file in "${BARE_FILES[@]}" "$GIT_DIR"/* "$ZSH_DIR"/*; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")
		dest="$HOME/$filename"

		printf "\nInstalling %s...\n" "$filename"
		# Backup existing file or symlink to prevent data loss
		if [ -e "$dest" ] || [ -L "$dest" ]; then
			printf "Found existing %s. Backing up to %s.bak...\n" "$dest" "$dest"
			mv "$dest" "${dest}.bak"
		fi

		# Create the symlink
		ln -s "$file" "$dest"
		printf "Symlinked: %s -> %s\n" "$dest" "$file"
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
ZSH_TEMPLATE="./zshrc.local.template"
if [[ -f "$LOCAL_ZSH" ]]; then
    printf "$HOME/.zshrc.local already exists. Verifying...\n"
    printf "TODO: ensure all default values present.\n"
else
    printf "Could not find ${LOCAL_ZSH}! Creating from template...\n"
    
    if [[ -f "$ZSH_TEMPLATE" ]]; then
        cp "$ZSH_TEMPLATE" "$LOCAL_ZSH"
    else
        printf "Template file $ZSH_TEMPLATE not found!\n"
    fi
fi

# FIXME: function
GIT_CONFIG="$HOME/.gitconfig"
GIT_CONFIG_TEMPLATE="$TEMPLATE_DIR/gitconfig.template"
if [[ ! -f "$GIT_CONFIG" ]]; then
	printf "\nCreating default ~/.gitconfig...\n"
	# FIXME: check if installed
	cred_helper=""

	if [[ "$OS" == "Windows_NT" ]]; then
        cred_helper="git-credential-manager.exe"
	else
		case "$(uname -s)" in
			Darwin*)
				cred_helper="osxkeychain"
				;;
			Linux*)
				if uname -r | grep -qi "microsoft"; then
					cred_helper="git-credential-manager.exe"
				else
					cred_helper="libsecret"
				fi            ;;
			CYGWIN*|MINGW*|MSYS*)
				cred_helper="git-credential-manager.exe" 
				;;
			*)
				# fallback
				cred_helper="FIXME:" 
				;;
		esac
	fi

	if [[ ! -f "$GIT_CONFIG_TEMPLATE" ]]; then
        printf "Template file $GIT_CONFIG_TEMPLATE not found!\nExiting..."
        return 1
    fi

	sed "s/{{CRED_HELPER}}/$cred_helper/g" "$GIT_CONFIG_TEMPLATE" > "$GIT_CONFIG"
else
	printf "\n~/.gitconfig already exists...\n"
fi

source "$DIR/mode.sh" "$@"

printf "\n\033[32mInstall complete!\033[0m Run \033[36m'exec zsh'\033[0m or restart your terminal to apply.\n"
