#!/usr/bin/env bash

if [[ -n "${__INSTALL_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __INSTALL_SH_INCLUDED__=1
###################
# functions

# Prompts the user to continue.
# Exits the script if the user chooses No (n/N).
# Usage: prompt_continue
prompt_continue() {

	local choice
	while true; do
		# Print a styled prompt (Yellow arrow, bold white text)
		printf '\n\e[1;33m==>\e[0m \e[1;37mDo you want to continue anyway? [y/N]: \e[0m'
		read -r choice

		case "$choice" in
		[yY])
			return 0 # continue script
			;;
		[nN]) #| "") # 'Enter' key is no
			printf '\n\e[1;31mAborting installation!\e[0m\n' >&2
			exit 1
			;;
		*)
			printf '\e[31mInvalid input. Please enter y or n.\e[0m\n'
			;;
		esac
	done
}

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
# determine specific OS to source correct source file, output, etc.
get_os_suffix() {
	if [[ -n "${FORCE_OS_SUFFIX:-}" ]]; then
		echo "${FORCE_OS_SUFFIX}"
		return 0
	fi

	if [[ "$OS" == "Windows_NT" ]]; then
		echo "windows"
		return 0
	fi
	case "$(uname -s)" in
	Darwin*) echo "mac" ;;
	Linux*)
		if uname -r | grep -qi "microsoft"; then
			echo "wsl"
		else
			echo "linux"
		fi
		;;
	CYGWIN* | MINGW* | MSYS*) echo "windows" ;;
	*)
		echo "unknown"
		return 1
		;;
	esac
	return 0
}

OS_SUFFIX="$(get_os_suffix)" || {
	log::warning "To force install, run: \e[36m'bash %s --os <mac|linux|win|wsl>'\e[0m" "$0"
	log::warning "Unknown OS. Cannot determine which configuration files to install."
	prompt_continue
}
readonly OS_SUFFIX
unset -f get_os_suffix

###################
# Main script
printf '\n%b\n%b\n%b\n%b\n%b\n\n' \
	'\e[36m╭───────────────────────────────────────────╮\e[0m' \
	'\e[36m│                                           │\e[0m' \
	'\e[36m│\e[0m           \e[1;36mSTARTING INSTALLATION\e[0m           \e[36m│\e[0m' \
	'\e[36m│                                           │\e[0m' \
	'\e[36m╰───────────────────────────────────────────╯\e[0m'

log::step "Pulling latest changes from git"
git::pull || {
	prompt_continue
}

# tell bash to include hidden files
shopt -s dotglob

# FIXME: move to top
declare -r GIT_DIR="git"
declare -r ZSH_DIR="zsh"
declare -r TEMPLATE_DIR="template"
# NOTE: keep .exports first
declare -a BARE_FILES=(".exports" ".paths" ".curlrc" ".wgetrc" ".bashrc")

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

# FIXME: platform specific
declare -r LOCAL_ZSH="$HOME/.zshrc.local"
declare -r ZSH_TEMPLATE="$TEMPLATE_DIR/.zshrc.template"

declare -r LOCAL_GITCONFIG="$HOME/.gitconfig.local"

template::install "$LOCAL_ZSH" "$ZSH_TEMPLATE" || missing_deps=1
template::validate "$LOCAL_ZSH" "${INVALID_TOKEN}" || missing_deps=1

if [[ "$os_suffix" != "unknown" ]]; then
	gitconfig_src="$TEMPLATE_DIR/.gitconfig.${OS_SUFFIX}"

	filesystem::install_local "$gitconfig_src" "$LOCAL_GITCONFIG" || missing_deps=1
	#TODO: zsh
fi

# FIXME: move to top
if ((missing_deps > 0)); then
	echo "" >&2
	log::warning "One or more local configuration files are incomplete."
	log::warning "Continue or fix the unresolved tags mentioned above and run the script again."
	prompt_continue
fi

source "mode.sh" "$@"

printf '\n%b\n%b\n%b\n%b\n%b\n%b\n\n' \
	'\e[32m╭───────────────────────────────────────────╮\e[0m' \
	'\e[32m│                                           │\e[0m' \
	'\e[32m│\e[0m          \e[1;32mINSTALLATION COMPLETE!\e[0m           \e[32m│\e[0m' \
	'\e[32m│                                           │\e[0m' \
	'\e[32m│\e[0m  Run \e[1;36mexec zsh\e[0m to apply your changes.      \e[32m│\e[0m' \
	'\e[32m╰───────────────────────────────────────────╯\e[0m'
