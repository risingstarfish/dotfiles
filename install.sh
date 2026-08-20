#!/usr/bin/env bash

###################
# get the absolute directory path of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to resolve script directory. Exiting...\n"
	exit 1
}

declare -r DIR
cd "$DIR" || exit 1

declare -r -a LIBS=(
	"log.sh"
	"common.sh"
	"filesystem.sh"
	"git.sh"
	"template.sh"
)

for lib in "${LIBS[@]}"; do
	lib_path="$DIR/lib/$lib"
	if [[ ! -f "$lib_path" ]]; then
		printf "\e[31m[ERROR]\e[0m Required library missing: %s\n" "$lib" >&2
		exit 1
	fi
	source "$lib_path"
done

###################
# initial checks
# FIXME: move required checks here

###################
# Main script

filesystem::require_file "usage.sh" "Usage script" || {
	log::error "You may need to RESET the git repo or create one yourself."
	exit 1
}
# validate input and check for help flag
source "usage.sh" "$(basename "$0")" "$@"

log::info "Pulling latest changes from git..."
git pull origin main || log::warning "Git pull failed, continuing with local files."

# tell bash to include hidden files
shopt -s dotglob

declare -r GIT_DIR="git"
declare -r ZSH_DIR="zsh"
declare -r TEMPLATE_DIR="template"
# NOTE: keep .exports first
declare -a BARE_FILES=(".exports" ".paths" ".curlrc" ".wgetrc")

declare -i missing_deps=0 # tracker

echo ""
log::info "Validating required files and directories..."

filesystem::require_directory "$GIT_DIR" "Git directory" || missing_deps=1
filesystem::require_directory "$ZSH_DIR" "Zsh directory" || missing_deps=1
filesystem::require_directory "$TEMPLATE_DIR" "Template directory" || missing_deps=1

for file in "${BARE_FILES[@]}"; do
	filesystem::require_file "$file" "Bare file" || missing_deps=1
done

if ((missing_deps > 0)); then
	echo ""
	log::error "One or more required files or directories are missing."
	log::error "Installation cannot proceed. Exiting..."
	exit 1
fi

log::success "All required files and directories are present."

echo ""
log::info "Symlinking config files..."
filesystem::install_symlink "$HOME" "${BARE_FILES[@]}" "$GIT_DIR"/* "$ZSH_DIR"/*

echo ""
log::info "Setting up local configuration templates..."

declare -r LOCAL_ZSH="$HOME/.zshrc.local"
declare -r ZSH_TEMPLATE="$TEMPLATE_DIR/.zshrc.template"

declare -r LOCAL_GITCONFIG="$HOME/.gitconfig.local"
declare -r GITCONFIG_TEMPLATE="$TEMPLATE_DIR/.gitconfig.template"

template::install "$LOCAL_ZSH" "$ZSH_TEMPLATE" || missing_deps=1
template::validate "$LOCAL_ZSH" "${INVALID_TOKEN}" || missing_deps=1

echo ""
cred_helper="$(git::get_credential_helper)"
declare -r cred_helper
git::verify_credential_helper "$cred_helper"

template::install "$LOCAL_GITCONFIG" "$GITCONFIG_TEMPLATE" "s/{{CRED_HELPER}}/$cred_helper/g" || missing_deps=1
template::validate "$LOCAL_GITCONFIG" "${INVALID_TOKEN}" || missing_deps=1

if ((missing_deps > 0)); then
	printf "\n"
	log::error "One or more local configuration files are incomplete."
	log::error "Please fix the unresolved tags mentioned above and run the script again."
	exit 1
fi

source "mode.sh" "$@"

printf "\n\e[32mInstall complete!\e[0m Run \e[36m'exec zsh'\e[0m or restart your terminal to apply.\n"
