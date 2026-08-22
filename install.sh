#!/usr/bin/env bash

if [[ -n "${__INSTALL_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __INSTALL_SH_INCLUDED__=1
###################
# utility
{
	# Output detailed error message in red
	# Usage: dev_error <message_or_format> [args...]
	#
	# Arguments:
	#   $1 (format) : The error message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	#
	# Returns:
	#   Outputs the formatted error string to stderr. Returns 0.
	#
	# Examples:
	#   [ DEV_ERROR ] file: main.sh(25) `main`: Hello world!
	#   [ DEV_ERROR ] file: install.sh(147) `main`: test error linux
	dev_error() {
		# set stack level (immediate caller)
		local -i level=1
		local -i line_level=$((level - 1))

		local -r caller_file="${BASH_SOURCE[$level]:-Unknown}"
		local -r caller_line="${BASH_LINENO[$line_level]:-Unknown}"
		local -r caller_func="${FUNCNAME[$level]:-main}"

		local -r base_file="${caller_file##*/}"

		local -r bold_red='\e[1;31m'
		local -r reset='\e[0m'

		local message
		if [[ $# -gt 1 ]]; then
			local format="$1"
			shift
			# shellcheck disable=SC2059
			printf -v message "$format" "$@"
		else
			message="$1"
		fi

		printf "%b[ DEV_ERROR ]%b file: %s(%s) \`%s()\`: %b\n" \
			"${bold_red}" "${reset}" \
			"${base_file}" "${caller_line}" "${caller_func}" \
			"${message}" >&2
	}

	# Prompts the user to continue.
	# Exits the script if the user chooses No (n/N).
	# Usage: prompt_continue
	#
	# Arguments:
	#   $1 (format) : (Optional) The warning message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	prompt_continue() {
		local -r bold_yellow='\e[1;33m'
		local -r bold_white='\e[1;37m'
		local -r bold_red='\e[1;31m'
		local -r red='\e[31m'
		local -r reset='\e[0m'

		local message
		if [[ $# -gt 1 ]]; then
			# shellcheck disable=SC2059
			printf -v message "$@"
		else
			message="$1"
		fi

		if [[ -n "$message" ]]; then
			printf "%b\n" "$message" >&2
		fi

		local choice
		while true; do
			printf "\n%b==>%b %bDo you want to continue anyway? [y/N]: %b" \
				"${bold_yellow}" "${reset}" \
				"${bold_white}" "${reset}" >&2

			read -r choice

			case "$choice" in
			[yY])
				return 0
				;;
			[nN] | "") # 'Enter' key defaults to no
				printf "\n%bAborting installation!%b\n" "${bold_red}" "${reset}" >&2
				exit 1
				;;
			*)
				printf "%bInvalid input. Please enter y or n.%b\n" "${red}" "${reset}" >&2
				;;
			esac
		done
	}
}

# detect and set script directory
{
	declare SCRIPT_DIR # source directory of script

	# get the absolute directory path of this script
	# Source - https://stackoverflow.com/a/246128
	# Posted by dogbane, modified by community. See post 'Timeline' for change history
	# Retrieved 2026-08-20, License - CC BY-SA 4.0
	get_script_dir() {
		local source_path="${BASH_SOURCE[0]}"
		local symlink_dir
		local script_dir
		# Resolve symlinks recursively
		while [ -L "$source_path" ]; do
			# Get symlink directory
			symlink_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
			# Resolve symlink target (relative or absolute)
			source_path="$(readlink "$source_path")"
			# Check if candidate path is relative or absolute
			if [[ $source_path != /* ]]; then
				# Candidate path is relative, resolve to full path
				source_path=$symlink_dir/$source_path
			fi
		done
		# Get final script directory path from fully resolved source path
		script_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
		# Return failure if the directory couldn't be resolved
		[[ -z "$script_dir" ]] && return 1
		printf "%s\n" "$script_dir"
	}

	SCRIPT_DIR="$(get_script_dir)" || {
		printf "\n\e[1;31m[ERROR]\e[0m Failed to resolve script directory. Exiting...\n" >&2
		exit 1
	}
	readonly SCRIPT_DIR
	unset -f get_script_dir
	cd "$SCRIPT_DIR" || {
		printf "\e[1;31m[ERROR]\e[0m Failed to enter root directory: %s\n" "$SCRIPT_DIR" >&2
		exit 1
	}
}

# OS and environment
{
	declare TARGET_OS
	declare TARGET_ENV

	readonly OS_ARCHLINUX="archlinux"
	readonly OS_DEBIAN="debian"
	readonly OS_MAC="mac"
	readonly OS_WINDOWS="windows"
	readonly OS_UNKNOWN="unknown"

	readonly ENV_NATIVE="native"
	readonly ENV_WSL="wsl"
	readonly ENV_MSYS="msys"
	readonly ENV_GITBASH="gitbash"
	readonly ENV_UNKNOWN="unknown"

	# Detects and sets TARGET_OS and TARGET_ENV. Validates by comparing
	# against OS_UNKNOWN and ENV_UNKNOWN
	# Usage: detect_environment
	#
	# Returns:
	#   0 on success
	#   1 if the OS is completely unrecognizable.
	detect_environment() {
		# Set safe defaults
		TARGET_OS="${OS_UNKNOWN}"
		TARGET_ENV="${ENV_UNKNOWN}"

		local kernel_name
		kernel_name="$(uname -s 2>/dev/null || echo "unknown")"

		case "${kernel_name}" in
		Linux*)
			# wsl vs native
			if uname -r | grep -qi "microsoft"; then
				TARGET_ENV="${ENV_WSL}"
			else
				TARGET_ENV="${ENV_NATIVE}"
			fi

			# archlinux vs debian
			if [[ -f "/etc/arch-release" ]]; then
				TARGET_OS="${OS_ARCHLINUX}"
			elif [[ -f "/etc/debian_version" ]]; then
				TARGET_OS="${OS_DEBIAN}"
			elif [[ -f "/etc/os-release" ]]; then
				if grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release; then
					TARGET_OS="${OS_DEBIAN}"
				elif grep -qiE '^ID(_LIKE)?=.*arch' /etc/os-release; then
					TARGET_OS="${OS_ARCHLINUX}"
				fi
			fi
			;;

		Darwin*)
			TARGET_OS="${OS_MAC}"
			TARGET_ENV="${ENV_NATIVE}"
			;;

		CYGWIN* | MSYS*)
			TARGET_OS="${OS_WINDOWS}"
			TARGET_ENV="${ENV_MSYS}"
			;;

		MINGW*)
			TARGET_OS="${OS_WINDOWS}"
			# Git Bash and standard MSYS2 MinGW output "MINGW*"
			# Git Bash explicitly places git-bash.exe at the root and sets $EXEPATH
			if [[ -f "/git-bash.exe" || -n "${EXEPATH:-}" ]]; then
				TARGET_ENV="${ENV_GITBASH}"
			else
				TARGET_ENV="${ENV_MSYS}"
			fi
			;;

		*)
			# Unknown
			if [[ "$OS" == "Windows_NT" ]]; then
				TARGET_OS="${OS_WINDOWS}"
				TARGET_ENV="${ENV_NATIVE}"
			else
				return 1
			fi
			;;
		esac

		return 0
	}

	detect_environment || {
		dev_error "Unable to detect TARGET_OS or TARGET_ENV."
		prompt_continue "Installation may not proceed as expected"
	}

	readonly TARGET_OS
	readonly TARGET_ENV
	unset -f detect_environment

	# Executes the PowerShell handoff and exits the bash script.
	# Never returns to the caller if successful (exits with PowerShell's exit code).
	exec_powershell_handoff() {
		local -r bold_blue='\e[1;34m'
		local -r bold_green='\e[1;32m'
		local -r reset='\e[0m'

		local ps_script="$SCRIPT_DIR/install.ps1"

		if [[ ! -f "${ps_script}" ]]; then
			dev_error "Something went wrong! Unable to find install.ps1."
			exit 1
		fi

		# Determine which PowerShell binary to use
		local ps_exe
		if command -v pwsh.exe >/dev/null 2>&1; then
			ps_exe="pwsh.exe"
		else
			ps_exe="powershell.exe"
		fi

		printf "\n%b==>%b Handing off execution to %b%s%b...\n" \
			"${bold_blue}" "${reset}" "${bold_green}" "${ps_exe}" "${reset}"

		"$ps_exe" -NoProfile -ExecutionPolicy Bypass -File "$ps_script"
		exit $?
	}

	# Checks if running on Windows (Git Bash or Unknown) and prompts user to switch to PowerShell.
	prompt_windows_handoff() {
		# If not on Windows at all, return immediately
		if [[ "${TARGET_OS}" != "${OS_WINDOWS}" ]]; then
			return 0
		fi

		local -r bold_yellow='\e[1;33m'
		local -r bold_white='\e[1;37m'
		local -r bold_blue='\e[1;34m'
		local -r red='\e[31m'
		local -r reset='\e[0m'

		if [[ "${TARGET_ENV}" == "${ENV_GIT_BASH}" ]]; then
			printf "\n%b==>%b %bWindows Git Bash environment detected.%b\n" \
				"${bold_blue}" "${reset}" "${bold_white}" "${reset}" >&2

			printf "%b==>%b %b(Note: If you are not actually running Git Bash, this could be an error)%b\n\n" \
				"${bold_yellow}" "${reset}" "${bold_white}" "${reset}" >&2

		elif [[ "${TARGET_ENV}" == "${ENV_NATIVE}" ]]; then
			printf "\n%b==>%b %bUnknown Windows Bash environment detected.%b\n" \
				"${bold_yellow}" "${reset}" "${bold_white}" "${reset}" >&2

			printf "    %bBash scripts may fail to configure native Windows settings properly.%b\n\n" \
				"${bold_white}" "${reset}" >&2
		else
			return 0
		fi

		local choice
		while true; do
			printf "%b==>%b %bSwitch to the native PowerShell installer (install.ps1)? [Y/n]: %b" \
				"${bold_yellow}" "${reset}" "${bold_white}" "${reset}" >&2

			read -r choice

			case "$choice" in
			[yY])
				execute_powershell_handoff
				;;
			[nN])
				printf "\n%b==>%b Continuing with Bash installer on Windows...\n" \
					"${bold_blue}" "${reset}"
				return 0
				;;
			*)
				printf "\n%bInvalid input. Please enter y or n.%b\n" "${red}" "${reset}" >&2
				;;
			esac
		done
	}

	prompt_windows_handoff
	unset -f prompt_windows_handoff execute_powershell_handoff
}

# required paths for installation
{
	# Check if provided paths exist.
	# If any paths are missing, outputs a summary at the end.
	# Usage: check_exists <path> [path...]
	#
	# Arguments:
	#   $@ (args) : Paths to verify.
	#
	# Returns:
	#   0 if all paths exist
	#   1 if any paths do not exist
	check_exists() {
		local -r -a paths=("$@")
		local -a missing_paths=()

		local -r bold_red='\e[1;31m'
		local -r reset='\e[0m'

		local prefix=""
		if [[ -n "${SCRIPT_DIR:-}" ]]; then
			prefix="${SCRIPT_DIR}/"
		fi

		for path in "${paths[@]}"; do
			if [[ ! -e "$path" ]]; then
				missing_paths+=("${path#"$prefix"}")
			fi
		done

		if [[ ${#missing_paths[@]} -gt 0 ]]; then
			echo "" >&2
			dev_error "Missing %d path(s):" "${#missing_paths[@]}"
			for missing in "${missing_paths[@]}"; do
				# '[ DEV_ERROR ] ' 14 chars
				#       vvv 16 chars vvv
				printf "  %b✗%b %s\n" "${bold_red}" "${reset}" "${missing}" >&2
			done

			echo "" >&2
			exit 1
		fi

		return 0
	}

	# base directory constants
	readonly LIB_DIR="${SCRIPT_DIR}/lib"
	readonly OS_DIR="${SCRIPT_DIR}/os"
	readonly ENV_DIR="${SCRIPT_DIR}/env"
	readonly SHELL_DIR="${SCRIPT_DIR}/shells"
	readonly APP_DIR="${SCRIPT_DIR}/apps"

	# lib
	declare -a lib_files=(
		"${LIB_DIR}/banner.sh"
		"${LIB_DIR}/bootstrap.sh"
		"${LIB_DIR}/common.sh"
		"${LIB_DIR}/log.sh"
		"${LIB_DIR}/filesystem.sh"
		"${LIB_DIR}/git.sh"
		"${LIB_DIR}/template.sh"
	)

	# OS
	declare -a os_mac_files=(
		"${OS_DIR}/mac/TODO"
	)
	declare -a os_archlinux_files=(
		"${OS_DIR}/archlinux/TODO"
	)
	declare -a os_debian_files=(
		"${OS_DIR}/debian/TODO"
	)
	declare -a os_windows_files=(
		"${OS_DIR}/windows/TODO"
	)

	# env
	declare -a env_native_files=(
		"${ENV_DIR}/native/TODO"
	)
	declare -a env_wsl_files=(
		"${ENV_DIR}/wsl/TODO"
	)
	declare -a env_msys_files=(
		"${ENV_DIR}/msys/TODO"
	)
	declare -a env_gitbash_files=(
		"${ENV_DIR}/gitbash/TODO"
	)

	# shell
	declare -a shell_zsh_files=(
		"${SHELL_DIR}/zsh/.aliases"
		"${SHELL_DIR}/zsh/.exports"
		"${SHELL_DIR}/zsh/.functions"
		"${SHELL_DIR}/zsh/.p10k.zsh"
		"${SHELL_DIR}/zsh/.zimrc"
		"${SHELL_DIR}/zsh/.zsh_options"
		"${SHELL_DIR}/zsh/.zshrc"
		"${SHELL_DIR}/zsh/.zshrc.toggles"
		"${SHELL_DIR}/zsh/.zstyles"
		"${SHELL_DIR}/zsh/.paths"
	)
	declare -a shell_bash_files=(
		"${SHELL_DIR}/bash/.bashrc"
		"${SHELL_DIR}/bash/.bash_profile"
	)
	# declare -a shell_pwsh_files=()

	# app
	declare -a app_ssh_files=(
		"${APP_DIR}/ssh/config" # FIXME: remember chmod 600
		"${APP_DIR}/ssh/allowed_signers"
	)
	declare -a app_curl_files=("${APP_DIR}/curl/.curlrc")
	declare -a app_wget_files=("${APP_DIR}/wget/.wgetrc")
	declare -a app_git_files=(
		"${APP_DIR}/git/.gitignore"
		"${APP_DIR}/git/.gitattributes"
		#"${APP_DIR}/git/.gitconfig.global"
	)
	declare -a app_fastfetch_files=(
		"${APP_DIR}/fastfetch/default.config.jsonc" # fallback
	)

	# os/env specific
	case "${TARGET_OS}" in
	"${OS_MAC}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.mac")
		app_fastfetch_files+=("${APP_DIR}/fastfetch/mac.config.jsonc")
		;;
	"${OS_ARCHLINUX}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.archlinux")
		# app_fastfetch_files+=( "${APP_DIR}/fastfetch/archlinux.config.jsonc" )
		;;
	"${OS_WINDOWS}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.windows")
		# app_fastfetch_files+=( "${APP_DIR}/fastfetch/windows.config.jsonc" )
		;;
	esac

	if [[ "${TARGET_ENV}" == "${ENV_WSL}" ]]; then
		app_git_files+=("${APP_DIR}/git/.gitconfig.wsl")
	fi

	# base files required across all machines
	declare -a files_to_check=(
		"${lib_files[@]}"
		"${shell_zsh_files[@]}"
		"${app_ssh_files[@]}"
		"${app_curl_files[@]}"
		"${app_wget_files[@]}"
		"${app_git_files[@]}"
		"${app_fastfetch_files[@]}"
	)

	case "${TARGET_OS}" in
	"${OS_MAC}") files_to_check+=("${os_mac_files[@]}") ;;
	"${OS_ARCHLINUX}") files_to_check+=("${os_archlinux_files[@]}") ;;
	"${OS_DEBIAN}") files_to_check+=("${os_debian_files[@]}") ;;
	"${OS_WINDOWS}") files_to_check+=("${os_windows_files[@]}") ;;
	esac

	case "${TARGET_ENV}" in
	"${ENV_GITBASH}")
		files_to_check+=("${env_gitbash_files[@]}" "${shell_bash_files[@]}")
		;;
	"${ENV_WSL}")
		files_to_check+=("${env_wsl_files[@]}")
		;;
	"${ENV_MSYS}")
		files_to_check+=("${env_msys_files[@]}")
		;;
	"${ENV_NATIVE}")
		files_to_check+=("${env_native_files[@]}")
		;;
	esac

	check_exists "${files_to_check[@]}"
	unset -f check_exists
}
###################
# print banner
if [[ -f "$SCRIPT_DIR/lib/banner.sh" ]]; then
	source "$SCRIPT_DIR/lib/banner.sh"
fi

# FIXME:
prompt_continue "Script not finished"
exit 1

source "$SCRIPT_DIR/lib/bootstrap.sh" || {
	printf "\n\e[1;31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "common.sh" "log.sh" "filesystem.sh" "git.sh" "template.sh" || exit 1
###################
# initial checks
# FIXME: move required checks here

# validate input and check for help flag
source "$SCRIPT_DIR/usage.sh" "$(basename "$0")" "$@" || exit 1
# determine specific OS to source correct source file, output, etc.
get_os_suffix() {
	if [[ -n "${FORCE_ENV_SUFFIX:-}" ]]; then
		echo "${FORCE_ENV_SUFFIX}"
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

ENV_SUFFIX="$(get_os_suffix)" || {
	log::warning "To force install, run: \e[36m'bash %s --os <mac|linux|win|wsl>'\e[0m" "$0"
	log::warning "Unknown OS. Cannot determine which configuration files to install."
	prompt_continue
}
readonly ENV_SUFFIX
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
	gitconfig_src="$TEMPLATE_DIR/.gitconfig.${ENV_SUFFIX}"

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
