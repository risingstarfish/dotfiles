#!/usr/bin/env bash

if [[ -n "${__INSTALL_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __INSTALL_SH_INCLUDED__=1
###################
# get the absolute directory path of this script
# Source - https://stackoverflow.com/a/246128
# Posted by dogbane, modified by community. See post 'Timeline' for change history
# Retrieved 2026-08-20, License - CC BY-SA 4.0
get_script_dir() {
	local SOURCE_PATH="${BASH_SOURCE[0]}"
	local SYMLINK_DIR
	local SCRIPT_DIR
	# Resolve symlinks recursively
	while [ -L "$SOURCE_PATH" ]; do
		# Get symlink directory
		SYMLINK_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
		# Resolve symlink target (relative or absolute)
		SOURCE_PATH="$(readlink "$SOURCE_PATH")"
		# Check if candidate path is relative or absolute
		if [[ $SOURCE_PATH != /* ]]; then
			# Candidate path is relative, resolve to full path
			SOURCE_PATH=$SYMLINK_DIR/$SOURCE_PATH
		fi
	done
	# Get final script directory path from fully resolved source path
	SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
	# Return failure if the directory couldn't be resolved
	[[ -z "$SCRIPT_DIR" ]] && return 1
	printf "%s\n" "$SCRIPT_DIR"
}

ROOT_DIR="$(get_script_dir)" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to resolve script directory. Exiting...\n" >&2
	exit 1
}
readonly ROOT_DIR

unset -f get_script_dir

cd "$ROOT_DIR" || {
	printf "\e[31m[ERROR]\e[0m Failed to enter root directory: %s\n" "$ROOT_DIR" >&2
	exit 1
}
###################
# print banner
if [[ -f "$ROOT_DIR/lib/banner.sh" ]]; then
	source "$ROOT_DIR/lib/banner.sh"
fi

source "$ROOT_DIR/lib/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "common.sh" "log.sh" "filesystem.sh" "git.sh" "template.sh" || exit 1
###################
# initial checks
# FIXME: move required checks here

# validate input and check for help flag
source "$ROOT_DIR/usage.sh" "$(basename "$0")" "$@" || exit 1

###################
# Main script
printf '\n%b\n%b\n%b\n%b\n%b\n\n' \
	'\e[36m╭───────────────────────────────────────────╮\e[0m' \
	'\e[36m│                                           │\e[0m' \
	'\e[36m│\e[0m           \e[1;36mSTARTING INSTALLATION\e[0m           \e[36m│\e[0m' \
	'\e[36m│                                           │\e[0m' \
	'\e[36m╰───────────────────────────────────────────╯\e[0m'

log::step "Pulling latest changes from git..."
if ! git_output=$(git pull origin main 2>&1); then
	log::warning "Git pull failed, continuing with local files."
	log::warning "Reason: $git_output"
	common::prompt_continue
fi
# tell bash to include hidden files
shopt -s dotglob

declare -r GIT_DIR="git"
declare -r ZSH_DIR="zsh"
declare -r TEMPLATE_DIR="template"
# NOTE: keep .exports first
declare -a BARE_FILES=(".exports" ".paths" ".curlrc" ".wgetrc")

declare -i missing_deps=0 # tracker

echo ""
log::step "Validating required files and directories"

filesystem::require_directory "$GIT_DIR" "Git directory" || missing_deps=1
filesystem::require_directory "$ZSH_DIR" "Zsh directory" || missing_deps=1
filesystem::require_directory "$TEMPLATE_DIR" "Template directory" || missing_deps=1

for file in "${BARE_FILES[@]}"; do
	filesystem::require_file "$file" "Bare file" || missing_deps=1
done

if ((missing_deps > 0)); then
	echo "" >&2
	log::error "One or more required files or directories are missing."
	log::error "Installation cannot proceed. Exiting..."
	exit 1
fi

log::success "All required files and directories are present."

log::step "Symlinking config files"
filesystem::install_symlink "$HOME" "${BARE_FILES[@]}" "$GIT_DIR"/* "$ZSH_DIR"/*

log::step "Setting up local configuration templates"

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
	printf "\n" >&2
	log::error "One or more local configuration files are incomplete."
	log::error "Please fix the unresolved tags mentioned above and run the script again."
	exit 1
fi

source "mode.sh" "$@"

printf '\n%b\n%b\n%b\n%b\n%b\n%b\n\n' \
	'\e[32m╭───────────────────────────────────────────╮\e[0m' \
	'\e[32m│                                           │\e[0m' \
	'\e[32m│\e[0m          \e[1;32mINSTALLATION COMPLETE!\e[0m           \e[32m│\e[0m' \
	'\e[32m│                                           │\e[0m' \
	'\e[32m│\e[0m  Run \e[1;36mexec zsh\e[0m to apply your changes.      \e[32m│\e[0m' \
	'\e[32m╰───────────────────────────────────────────╯\e[0m'
