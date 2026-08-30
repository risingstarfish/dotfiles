#!/usr/bin/env bash
# install.sh

set -euo pipefail
####################
if [[ -n "${__INSTALL_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __INSTALL_SH_INCLUDED__=1
####################
# constants
{
	if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
		printf 'Error: unable to resolve $HOME'
		exit 1
	fi
	#  user global env
	readonly DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-${HOME}/.config/dotfiles/logs}" # post
	readonly DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-${HOME}/.cache/dotfiles}"   # post
	# readonly DOTFILES_LOG="${DOTFILES_LOG:-1}" # cli modified --no-log
	# pre script env. do not get modified by cli
	readonly DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-${HOME}/dotfiles}" # setup
	readonly DOTFILES_INSTALL_REF="${DOTFILES_INSTALL_REF:-main}"             # setup
	readonly DOTFILES_LOCAL_MODS="${DOTFILES_LOCAL_MODS:-0}"                  # post

	readonly REPO_URL="https://github.com/risingstarfish/dotfiles.git"
	# env
	readonly OS_ARCHLINUX="archlinux"
	readonly OS_DEBIAN="debian"
	readonly OS_MAC="mac"
	readonly OS_WINDOWS="windows"
	readonly OS_UNKNOWN="unknown"

	readonly RUNTIME_NATIVE="native"
	readonly RUNTIME_WSL="wsl"
	readonly RUNTIME_MSYS="msys"
	readonly RUNTIME_GITBASH="gitbash"
	readonly RUNTIME_UNKNOWN="unknown"

	readonly WINDOWS_SUDO_REG_LOC="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo"
}
####################
# util
{
	dotfiles::println() {
		if [[ $# -gt 1 ]]; then
			# format
			command printf "$1\n" "${@:2}"
		else
			# single string
			command printf '%s\n' "${1:-}"
		fi
	}

	dotfiles::is_true() {
		case "${1,,}" in
		1 | true) return 0 ;;
		*) return 1 ;;
		esac
	}
}
####################
# functions to set global vars
{
	# set the absolute directory path of this script
	# Source - https://stackoverflow.com/a/246128
	dotfiles::set_src_path() {
		[[ -n "${SRC_PATH:-}" ]] && return 0

		local source_path="${BASH_SOURCE[0]}"
		# piped to bash
		if [[ -z "${source_path}" ]]; then
			readonly SRC_PATH
			return
		fi

		local symlink_dir
		while [[ -L "$source_path" ]]; do
			symlink_dir="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
			source_path="$(readlink "$source_path")"

			if [[ $source_path != /* ]]; then
				source_path=$symlink_dir/$source_path
			fi
		done

		SRC_PATH="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
		readonly SRC_PATH
	}

	dotfiles::set_ref() {
		[[ -n "${GITHUB_REF:-}" ]] && return 0

		GITHUB_REF="$(command git -C "${SRC_PATH}" config --local dotfiles.ref 2>/dev/null)"
		readonly GITHUB_REF="${GITHUB_REF:-main}"
	}

	# Detects and sets TARGET_OS and TARGET_RUNTIME. Validates by comparing
	# against OS_UNKNOWN and RUNTIME_UNKNOWN
	# Usage: set_env
	#
	# Returns:
	#   0 if TARGET_OS and TARGET_RUNTIME are set
	#   1 if TARGET_OS and TARGET_RUNTIME remain 'unknown'
	dotfiles::set_env() {
		[[ -n "${TARGET_OS:-}" || -n "${TARGET_RUNTIME:-}" ]] && return 0

		local kernel_name
		kernel_name="$(uname -s 2>/dev/null || echo "unknown")"

		case "${kernel_name}" in
		Linux*)
			# wsl vs native
			if uname -r | grep -qi "microsoft"; then
				readonly TARGET_RUNTIME="${RUNTIME_WSL}"
			else
				readonly TARGET_RUNTIME="${RUNTIME_NATIVE}"
			fi

			# distro
			if [[ -f "/etc/os-release" ]]; then
				if grep -qiE '^ID=.*cachyos' /etc/os-release; then
					readonly TARGET_OS="${OS_CACHYOS:-cachyos}"
				elif grep -qiE '^ID(_LIKE)?=.*arch' /etc/os-release || [[ -f "/etc/arch-release" ]]; then
					readonly TARGET_OS="${OS_ARCHLINUX}"
				elif grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release || [[ -f "/etc/debian_version" ]]; then
					readonly TARGET_OS="${OS_DEBIAN}"
				else
					readonly TARGET_OS="${OS_UNKNOWN}"
				fi
			else
				readonly TARGET_OS="${OS_UNKNOWN}"
			fi
			;;

		Darwin*)
			readonly TARGET_OS="${OS_MAC}"
			readonly TARGET_RUNTIME="${RUNTIME_NATIVE}"
			;;

		CYGWIN* | MSYS*)
			readonly TARGET_OS="${OS_WINDOWS}"
			readonly TARGET_RUNTIME="${RUNTIME_MSYS}"
			;;

		MINGW*)
			readonly TARGET_OS="${OS_WINDOWS}"
			# Git Bash and standard MSYS2 MinGW output "MINGW*"
			# Git Bash explicitly places git-bash.exe at the root and sets $EXEPATH
			if [[ -f "/git-bash.exe" || -n "${EXEPATH:-}" ]]; then
				readonly TARGET_RUNTIME="${RUNTIME_GITBASH}"
			else
				readonly TARGET_RUNTIME="${RUNTIME_MSYS}"
			fi
			;;

		*)
			# Unknown
			if [[ "${OS:-}" == "Windows_NT" ]]; then
				readonly TARGET_OS="${OS_WINDOWS}"
				readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}" # redundant
			else
				readonly TARGET_OS="${OS_UNKNOWN}"
				readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}"

				return 1
			fi
			;;
		esac

		return 0
	}

	# Detect if script was run as sudo or root.
	# Usage: set_admin
	dotfiles::set_admin() {
		[[ -n "${IS_ADMIN:-}" ]] && return 0

		if [[ "$EUID" -eq 0 || -n "${SUDO_USER:-}" ]]; then
			readonly IS_ADMIN=0
		elif [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]] && net session >/dev/null 2>&1; then
			# net session fails with exit code 5 if not admin
			readonly IS_ADMIN=0
		else
			readonly IS_ADMIN=1
		fi
	}

	dotfiles::set_available_modules() {
		[[ -n "${ALL_MODULES:-}" ]] && return 0
		# order matters for help message
		ALL_MODULES=(
			# shells
			"shells/zsh"
			"shells/bash"
			# apps
			"apps/git"
			"apps/ssh"
			"apps/curl"
			#"apps/oh-my-posh"
			"apps/shellcheck"
			#apps/fastfetch
			#"apps/tmux"
			"apps/wget"
		)

		if [[ "$TARGET_OS" == "${OS_MAC}" ]]; then
			ALL_MODULES+=("apps/iterm2")
		fi

		readonly ALL_MODULES
	}
}
####################
dotfiles::bash_version_check() {
	if [ -z "${BASH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
		dotfiles::println 'Error: the install instructions explicitly say to use the install script with bash; please follow them.' >&2
		return 1
	fi
	# script requires bash >=4.0
	if ((BASH_VERSINFO[0] < 4)); then
		dotfiles::println 'Error: This script requires bash v4.0 or newer. You are running %s.' "${BASH_VERSION}"

		if [[ "$(uname -s)" == "Darwin" ]]; then
			dotfiles::println '  On macOS, the default bash is severely outdated (v3.2).' >&2
			dotfiles::println '  Please install modern bash via Homebrew:' >&2
			dotfiles::println '    brew install bash' >&2
			dotfiles::println '  or via MacPorts:' >&2
			dotfiles::println '    sudo port install bash' >&2
			echo >&2
			dotfiles::println '  Then restart your terminal and run this script again using the new bash.' >&2
		fi

		return 1
	fi
}

####################
# util
{
	# Safely sources a file, validating existence and permissions first.
	# Usage: source_file <file_path>
	#
	# Arguments:
	#   $1 (file_path) : The absolute or relative path to the file to source.
	#
	# Returns:
	#   0 on success
	#   1 if function is called without an argument, file does not exist or is directory,
	#	  read permission denied, or read went wrong
	dotfiles::source_file() {
		local target_file="$1"

		if [[ -z "${target_file}" ]]; then
			dotfiles::println 'Error: source_file called without a file path argument.' >&2
			return 1
		fi

		if [[ ! -f "${target_file}" ]]; then
			dotfiles::println 'Error: Cannot source '%s': File does not exist or is a directory.' "${target_file}" >&2
			return 1
		fi

		if [[ ! -r "${target_file}" ]]; then
			dotfiles::println 'Error: Cannot source '%s': Read permission denied.' "${target_file}" >&2
			return 1
		fi

		source "${target_file}" || {
			local err_code=$?
			dotfiles::println 'Error: File '%s' was read, but execution failed with exit code %d.' "${target_file}" "${err_code}" >&2
			return 1
		}

		return 0
	}

	# Prompts the user to continue.
	# Exits the script if the user chooses No (n/N).
	# Usage: prompt_continue
	#
	# Arguments:
	#   $1 (format) : (Optional) The warning message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	dotfiles::prompt_continue() {
		local msg
		if [[ $# -gt 1 ]]; then
			# shellcheck disable=SC2059
			printf -v msg "$@"
		else
			msg="${1:-}"
		fi

		if [[ -n "$msg" ]]; then
			printf "%s\n" "$msg" >&2
		fi

		local choice
		while true; do
			if ! read -r -p '\nDo you want to continue anyway? [y/N]: ' choice; then
				dotfiles::println 'Error: No input available for prompt.' >&2
				return 1
			fi

			case "$choice" in
			[yY])
				return 0
				;;
			[nN])
				dotfiles::println 'Aborting installation!' >&2
				exit 130
				;;
			*)
				dotfiles::println 'Error: Invalid input. Please enter y or n.' >&2
				;;
			esac
		done
	}
}

# print
{
	dotfiles::print_help() {
		cat <<EOF
OVERVIEW: Installs and synchronizes dotfiles, shell configuration, TODO: and optional packages.

USAGE: bash $(basename "$0") [options]

ACTIONS
  -u, --update              Update from git before performing any operations
      --update-only         Update from git then exit
  -c, --clean               Remove orphaned symlinks, then install/relink
      --reset               Remove all symlinks managed by this tool

MODULES
  -i, --install <module>    Install ONLY the specified modules, semicolon-separated
  -x, --exclude <module>    Install all modules EXCEPT those specified, semicolon-separated
  -l, --list                Display all available modules, status, and information

SAFETY
  -n, --dry-run             Print planned actions without modifying the disk
  -I, --interactive         Prompt for confirmation before every action/modification
      --noconfirm           Do not prompt for any confirmation
  -f, --force               Overwrite existing files/links
      --no-backup           Delete existing conflicting files instead of backing up	

LOGGING
  -v, --verbose             Print detailed step-by-step instructions
  -q, --quiet               Suppress all standard output except errors
      --log-level <level>   Set log verbosity | debug, info, warn, or error (default: info)
      --no-log              Disable writing to the log file

PACKAGES & HOOKS
      --no-deps             Skip dotfiles dependency installation
      --no-hooks            Skip pre/post installation scripts

INFORMATION
  -d, --diff                Show diff between current files and incoming dotfiles
  -s, --status              Show current installation status of modules
      --version             Show the version and git information of this program
  -h, --help                Show this help message

ENVIRONMENT VARIABLES
  Global (Always Active):
    DOTFILES_LOG_DIR        Path to store log files (default: ~/.config/dotfiles/logs)
    DOTFILES_CACHE_DIR      Path to store temporary cache (default: ~/.cache/dotfiles)
    DOTFILES_LOG            Set to 0 or false to disable log file writing (default: 1)
    DOTFILES_LOCAL_MODS     Set to 1 or true to stash uncommitted local changes (default: 0)

  Setup Only:
    DOTFILES_INSTALL_DIR    Target directory for installation (default: ~/dotfiles)
    DOTFILES_INSTALL_REF    Specific git branch, tag, or commit to install (default: main)

EOF
	}

	# https://github.com/HyDE-Project/HyDE/blob/master/Scripts/version.sh
	dotfiles::print_version() {
		local -r dotfiles_clone_branch=$(command git -C "${SRC_PATH}" rev-parse --show-toplevel) || dotfiles_clone_branch="<unknown>"
		local -r dotfiles_branch=$(command git -C "${SRC_PATH}" rev-parse --abbrev-ref HEAD) || dotfiles_branch="<unknown>"
		local -r dotfiles_remote=$(command git -C "${SRC_PATH}" config --get remote.origin.url) || dotfiles_remote="<unknown>"
		local -r dotfiles_version=$(command git -C "${SRC_PATH}" describe --tags --always) || dotfiles_version="<unknown>"
		local -r dotfiles_commit_hash=$(command git -C "${SRC_PATH}" rev-parse HEAD) || dotfiles_commit_hash="<unknown>"
		local -r dotfiles_version_commit_msg=$(command git -C "${SRC_PATH}" log -1 --pretty=%B) || dotfiles_version_commit_msg="<unknown>"
		local -r dotfiles_version_last_checked=$(date +%Y-%m-%d\ %H:%M:%S\ %Z) || dotfiles_version_last_checked="<unknown>"

		cat <<EOF
dotfiles ${dotfiles_version} built from branch ${dotfiles_branch} at commit ${dotfiles_commit_hash:0:12} ($dotfiles_version_commit_msg)
Date: ${dotfiles_version_last_checked}
Repository: ${dotfiles_clone_branch}
Remote: ${dotfiles_remote}

EOF
	}

	dotfiles::print_status() {
		dotfiles::println 'TODO: implement.'
	}

	dotfiles::print_modules() {
		dotfiles::set_available_modules

		dotfiles::println
		dotfiles::println 'AVAILABLE MODULES'
		dotfiles::println

		all_symlinks=$(find "$HOME" -maxdepth 3 -type l -exec ls -ld {} + 2>/dev/null || true)
		local all_symlinks
		local current_category=""

		for item in "${ALL_MODULES[@]}"; do
			local category="${item%%/*}" # everything before the first '/'
			local module="${item##*/}"   # everything after the last '/'

			# header if it changed
			if [[ "$category" != "$current_category" ]]; then
				[[ -n "$current_category" ]] && dotfiles::println
				dotfiles::println "$category"
				current_category="$category"
			fi

			local desc=""
			case "$module" in
			zsh) desc="Z shell configuration and plugins" ;;
			bash) desc="Bare bash profile" ;;
			git) desc="Global gitconfig and commit templates" ;;
			ssh) desc="SSH key generation and config setup" ;;
			curl) desc="Command line tool for transferring data" ;;
			shellcheck) desc="Shell script analysis tool" ;;
			wget) desc="Network utility to retrieve files" ;;
			iterm2) desc="macOS terminal emulator configuration" ;;
			*) desc="Configuration for $module" ;;
			esac

			local status='?'
			if [[ -n "$all_symlinks" ]]; then
				local mod_dir="${SRC_PATH}/${item}"

				if [[ -d "$mod_dir" ]]; then
					local total_files=0
					local linked_files=0

					while IFS= read -r src_file; do
						[[ -z "$src_file" ]] && continue
						((total_files++))

						if echo "$all_symlinks" | grep -F -q "$src_file"; then
							((linked_files++))
						fi
					done < <(find "$mod_dir" -maxdepth 1 -type f 2>/dev/null || true)

					if [[ $total_files -gt 0 ]]; then
						if [[ $linked_files -eq $total_files ]]; then
							status="✓" # all files symlinked
						elif [[ $linked_files -gt 0 ]]; then
							status="~" # some files symlinked, some missing
						fi
					else
						# fallback for modules with no files
						if echo "$all_symlinks" | grep -F -q "${item}/"; then
							status="✓"
						fi
					fi
				fi
			fi

			printf "  (%s) %-15s %s\n" "$status" "$module" "$desc"
		done
		dotfiles::println
	}

	# pictures
	{
		dotfiles::print_banner() {
			cat <<'EOF'

  ____        _    __ _ _           
 |  _ \  ___ | |_ / _(_) | ___  ___ 
 | | | |/ _ \| __| |_| | |/ _ \/ __|
 | |_| | (_) | |_|  _| | |  __/\__ \
 |____/ \___/ \__|_| |_|_|\___||___/
 -----------------------------------
     Automated Environment Setup      
 -----------------------------------

EOF
		}

		dotfiles::print_start() {
			cat <<'EOF'

╭───────────────────────────────────────────╮
│                                           │
│           STARTING INSTALLATION           │
│                                           │
╰───────────────────────────────────────────╯

EOF
		}
		dotfiles::print_end() {
			if [[ -z "${NO_RESTART}" ]]; then
				cat <<'EOF'

╭───────────────────────────────────────────╮
│                                           │
│          INSTALLATION COMPLETE!           │
│                                           │
│  Restarting shell…                        │
╰───────────────────────────────────────────╯

EOF
			else
				cat <<'EOF'

╭───────────────────────────────────────────╮
│                                           │
│          INSTALLATION COMPLETE!           │
│                                           │
│  Run exec zsh to apply your changes.      │
╰───────────────────────────────────────────╯

EOF
			fi
		}
	}
}

# install and update
{
	dotfiles::default_install_dir() {
		printf "%s" "${HOME}/dotfiles"
	}

	dotfiles::install_dir() {
		if [[ -n "${DOTFILES_INSTALL_DIR:-}" ]]; then
			printf "%s" "${DOTFILES_INSTALL_DIR}"
		else
			dotfiles::default_install_dir
		fi
	}

	dotfiles::install_from_git() {
		local -r install_dir="$(dotfiles::install_dir)"
		local -r ref="${DOTFILES_INSTALL_REF:-main}"

		# path is not directory
		if [[ -e "${install_dir}" && ! -d "${install_dir}" ]]; then
			dotfiles::println 'Error: path "%s" is not a directory.' "${install_dir}" >&2
			return 1
		fi
		# already cloned
		if [[ -d "${install_dir}/.git" ]]; then
			if [[ -f "${install_dir}/install.sh" ]]; then
				dotfiles::println '=> Existing clone at %s.' "${install_dir}"
				exec bash "${install_dir}/install.sh" "$@"
			else # random repo
				dotfiles::println 'Error: %s/.git exists but %s does not.' "${install_dir}" "install.sh" >&2
				dotfiles::println '  This does not appear to be a dotfiles clone.' >&2
				dotfiles::println '  Remove it or set DOTFILES_INSTALL_DIR to a different path.' >&2
				return 1
			fi
		fi
		# non-empty dir and NOT git clone
		if [[ -d "${install_dir}" && -n "$(ls -A "${install_dir}" 2>/dev/null)" ]]; then
			dotfiles::println 'Error: %s is not empty and is not a git clone.' "${install_dir}" >&2
			dotfiles::println '  Move it aside or set DOTFILES_INSTALL_DIR to a different path.' >&2
			return 1
		fi
		# install_dir does not exist
		mkdir -p "${install_dir}" || {
			dotfiles::println 'Error: cannot create %s' "${install_dir}" >&2
			return 1
		}

		dotfiles::println '=> Cloning %s (ref: %s) to %s' "${REPO_URL}" "${ref}" "${install_dir}"
		command git clone --depth=1 -b "$ref" "$REPO_URL" "${install_dir}" || {
			dotfiles::println 'Error: Clone failed for %s (ref: %s)' "${REPO_URL}" "${ref}" >&2
			return 1
		}

		command git -C "${install_dir}" reflog expire --expire=now --all 2>/dev/null || true
		command git -C "${install_dir}" gc --auto --prune=now 2>/dev/null || true

		# restart script with local copy
		dotfiles::println '=> Restarting script with local copy.' # TODO: read -p
		exec bash "${install_dir}/install.sh" "$@"
	}

	############

	dotfiles::update() {
		if [[ ! -d "${SRC_PATH}/.git" ]]; then
			dotfiles::println 'Error: %s is not a git clone. Run install first.' "${SRC_PATH}" >&2
			return 1
		fi

		local has_local_mods=0
		if ! command git -C "${SRC_PATH}" diff --quiet HEAD 2>/dev/null; then
			has_local_mods=1
		fi

		# ── Normal user: block hard ──────────────────────────────────
		if ((has_local_mods)) && ! dotfiles::is_true "${DOTFILES_LOCAL_MODS}"; then
			cat <<EOF >&2

Error: You have uncommitted changes in ${SRC_PATH}:
$(command git -C "${SRC_PATH}" diff --stat HEAD 2>/dev/null)

  This repo is publicly maintained. Do not edit tracked files directly.
  Use .local override files for personal customisation:
    e.g.  tmux.conf  →  tmux.conf.local

  Revert your changes or move them to a .local file, then re-run:
    bash $(basename "$0") --update

  (dev: set DOTFILES_LOCAL_MODS=1 to bypass this check)

EOF
			return 1
		fi

		# ── Dev override: rebase instead of force-checkout ──────────
		if ((has_local_mods)) && dotfiles::is_true "${DOTFILES_LOCAL_MODS}"; then
			dotfiles::println '=> Local modifications detected. Rebasing instead of force-checkout.'
			dotfiles::println '  Your changes will be preserved on top of the latest %s.' "$GITHUB_REF"

			if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "$GITHUB_REF" 2>/dev/null; then
				dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "$GITHUB_REF" >&2
				return 1
			fi
			if ! command git -C "${SRC_PATH}" rebase FETCH_HEAD 2>/dev/null; then
				dotfiles::println 'Error: Rebase failed. Resolve conflicts, then:' >&2
				dotfiles::println '    git -C "%s" rebase --continue' "${SRC_PATH}" >&2
				dotfiles::println '  Or abort with:' >&2
				dotfiles::println '    git -C "%s" rebase --abort' "${SRC_PATH}" >&2
				return 1
			fi
			return 0
		fi

		dotfiles::println '=> Updating dotfiles in %s' "${SRC_PATH}"

		local fetch_ok=1
		if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "$GITHUB_REF" 2>/dev/null; then
			fetch_ok=0
			dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "$GITHUB_REF" >&2
			dotfiles::prompt_continue "Your files may be overwritten\n" || exit 1
			dotfiles::println '  Continuing with current local state.'
		fi
		if ((fetch_ok)); then
			if ! command git -C "${SRC_PATH}" checkout "$GITHUB_REF" 2>/dev/null; then
				dotfiles::println 'Error: Checkout of %s failed in %s' "$GITHUB_REF" "${SRC_PATH}" >&2
				return 1
			fi
			if ! command git -C "${SRC_PATH}" reset --hard FETCH_HEAD 2>/dev/null; then
				dotfiles::println 'Error: Reset to %s failed in %s' "$GITHUB_REF" "${SRC_PATH}" >&2
				return 1
			fi
		fi
	}
}

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
dotfiles::check_exists() {
	local -r -a paths=("$@")
	local -a missing_paths=()
	local -r prefix="${SRC_PATH}/"

	for path in "${paths[@]}"; do
		if [[ ! -e "$path" ]]; then
			missing_paths+=("${path#"$prefix"}")
		fi
	done

	if [[ ${#missing_paths[@]} -gt 0 ]]; then
		printf "Missing %d path(s):\n" "${#missing_paths[@]}" >&2

		for missing in "${missing_paths[@]}"; do
			printf "✗ %s\n" "${missing}" >&2
		done

		return 1
	fi

	return 0
}

#######################################
# windows
{
	# detect if windows user has sudo enabled
	dotfiles::detect_windows_sudo() {
		command -v sudo >/dev/null 2>&1 || return 1
		command -v reg.exe >/dev/null 2>&1 || return 1 # NOTE: redundant?

		local sudo_reg
		sudo_reg=$(reg.exe query "${WINDOWS_SUDO_REG_LOC}" /v Enabled 2>/dev/null)
		# output of 0x1, 0x2, or 0x3 means enabled
		if [[ "${sudo_reg}" =~ 0x[1-3] ]]; then
			return 0
		fi

		return 1
	}

	# Determine which PowerShell binary to use and set PWSH_CMD to it
	dotfiles::set_pwsh_cmd() {
		[[ -n "${PWSH_CMD:-}" ]] && return 0

		if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
			if PWSH_CMD=$(command -v pwsh.exe 2>/dev/null); then
				:
			elif PWSH_CMD=$(command -v powershell.exe 2>/dev/null); then
				:
			fi
		else # linux
			if PWSH_CMD=$(command -v pwsh 2>/dev/null); then
				:
			fi
		fi

		readonly PWSH_CMD
	}

	# Executes PowerShell handoff and exits the bash script.
	# Never returns to the caller if successful (exits with PowerShell's exit code).
	dotfiles::windows_handoff() {
		local ps_script="${SRC_PATH}/install.ps1"
		if [[ ! -f "${ps_script}" ]]; then
			dotfiles::println 'Error: unable to find "install.ps1".' >&2
			exit 1
		fi

		# convert unix paths to windows
		if [[ "${TARGET_RUNTIME}" == "${RUNTIME_WSL}" ]]; then
			ps_script=$(wslpath -w "$ps_script")
		fi

		local -a ps_args=("-NoProfile" "-ExecutionPolicy" "Bypass" "-File" "$ps_script")

		#if [[ ${IS_ADMIN} -eq 1 ]]; then
		#	ps_args+=("-IsElevated")
		#fi

		echo
		dotfiles::println '=> Handing off execution to "%s"...' "${PWSH_CMD}"
		exec "${PWSH_CMD}" "${ps_args[@]}"
	}

	# Checks if running on Windows (Git Bash or Unknown) and prompts user to switch to PowerShell.
	# Usage: prompt_windows_handoff
	#
	# Precondition:
	#    TARGET_OS == OS_WINDOWS
	#	 TARGET_RUNTIME == RUNTIME_GITBASH || RUNTIME_UNKNOWN
	#
	# Returns:
	#    0 if user wants to switch to powershell (yY)
	#    1 if user continues with script (nN)
	dotfiles::prompt_windows_handoff() {
		echo >&2

		if [[ "${TARGET_RUNTIME}" == "${RUNTIME_GITBASH}" ]]; then
			dotfiles::println '=> Windows Git Bash runtime detected' >&2
			dotfiles::println 'If you are not actually running Git Bash, something went wrong.' >&2
		else # unknown
			dotfiles::println '=> Unknown Windows Bash runtime detected.' >&2
			dotfiles::println 'Bash scripts may fail to configure native Windows settings properly.' >&2
		fi

		dotfiles::println 'Certain functionality may be missing or altered (e.g. instead of symlinking, it copies).' >&2
		if dotfiles::detect_windows_sudo; then
			dotfiles::println '   Tip: Re-run this script using `sudo` to enable native symlinks.' >&2
		else
			dotfiles::println '   Tip: Enable Windows Developer Mode or Windows Sudo to allow native symlinks.' >&2
		fi

		local choice
		while true; do
			if ! read -r -p $'\nSwitch to the native PowerShell installer (install.ps1)? [Y/n/(q)uit]: ' choice; then
				dotfiles::println 'Error: No input available for prompt.' >&2
				exit 1
			fi

			case "$choice" in
			[yY])
				# verify powershell available
				dotfiles::set_pwsh_cmd
				if [[ -z "${PWSH_CMD}" ]]; then
					dotfiles::println 'Error: Cannot locate pwsh.exe or powershell.exe.' >&2
					exit 1
				fi
				return 0
				;;
			[nN])
				dotfiles::println '=> Continuing with Bash installer on Windows...'
				return 1
				;;
			[qQ])
				dotfiles::println 'Aborting installation!' >&2
				exit 130
				;;
			*)
				dotfiles::println 'Error: Invalid input. Please enter y, n, or q.' >&2
				;;
			esac
		done
	}
}
####################
# $1 = flag name for the error message
# $2 = value to assign to MODE
dotfiles::set_mode() {
	if [[ -n "$MODE" ]]; then
		dotfiles::println 'Error: Cannot specify multiple actions. "%s" conflicts with "%s".' "$1" "$MODE" >&2
		exit 1
	fi
	MODE="$2"
}

# $1 = raw semicolon-separated string
# $2 = name of the target array
dotfiles::parse_module_list() {
	local -n arr="$2"
	local m
	local mod
	local valid
	local -a mods

	IFS=';' read -ra mods <<<"$1"
	for m in "${mods[@]}"; do
		[[ -z "$m" ]] && continue
		valid=0

		if [[ "$m" == */* ]]; then
			# submodule match (e.g., "apps/git")
			for mod in "${ALL_MODULES[@]}"; do
				[[ "$mod" == "$m" ]] && valid=1 && break
			done
		else
			# top-level match (e.g., "apps")
			for mod in "${ALL_MODULES[@]}"; do
				[[ "${mod%%/*}" == "$m" ]] && valid=1 && break
			done
		fi

		if [[ $valid -eq 0 ]]; then
			dotfiles::println 'Error: Unknown module "%s".' "$m" >&2
			exit 1
		fi
		arr+=("$m")
	done
}

dotfiles::argparse() {
	NO_RESTART=0
	DRY_RUN=0
	FORCE=0
	UPDATE=0
	INTERACTIVE=0
	NO_BACKUP=0
	NO_DEPS=0
	NO_HOOKS=0
	NO_LOG=0
	NO_CONFIRM=0
	VERBOSE=0
	QUIET=0
	MODE=""
	LOG_LEVEL="info"
	INSTALL_MODULES=()
	EXCLUDE_MODULES=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			dotfiles::print_help
			exit 0
			;;
		--version)
			dotfiles::print_version
			exit 0
			;;
		-s | --status)
			dotfiles::print_status
			exit 0
			;;

		-u | --update)
			UPDATE=1
			shift
			;;
		--update-only)
			dotfiles::update || exit 1
			dotfiles::println '=> Successfully updated!'
			exit 0
			;;
		-c | --clean)
			dotfiles::set_mode "--clean" "clean"
			shift
			;;
		--reset)
			dotfiles::set_mode "--reset" "reset"
			shift
			;;
		-l | --list)
			dotfiles::print_modules
			exit 0
			;;
		-d | --diff)
			dotfiles::set_mode "--diff" "diff"
			shift
			;;
		-i | --install)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println 'Error: Missing argument for "%s".' "$1" >&2
				exit 1
			fi
			dotfiles::parse_module_list "$2" INSTALL_MODULES
			shift 2
			;;
		--install=*)
			dotfiles::parse_module_list "${1#*=}" INSTALL_MODULES
			shift
			;;
		-x | --exclude)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println 'Error: Missing argument for "%s".' "$1" >&2
				exit 1
			fi
			dotfiles::parse_module_list "$2" EXCLUDE_MODULES
			shift 2
			;;
		--exclude=*)
			dotfiles::parse_module_list "${1#*=}" EXCLUDE_MODULES
			shift
			;;

		-n | --dry-run)
			DRY_RUN=1
			shift
			;;
		-I | --interactive)
			if [[ "${NO_CONFIRM}" -eq 1 ]]; then
				dotfiles::println 'Error: --interactive conflicts with --noconfirm.' >&2
				exit 1
			fi
			INTERACTIVE=1
			shift
			;;
		--noconfirm)
			if [[ "${INTERACTIVE}" -eq 1 ]]; then
				dotfiles::println 'Error: --noconfirm conflicts with --interactive.' >&2
				exit 1
			fi
			NO_CONFIRM=1
			shift
			;;
		-f | --force)
			FORCE=1
			shift
			;;
		--no-backup)
			NO_BACKUP=1
			shift
			;;

		-v | --verbose)
			VERBOSE=1
			LOG_LEVEL="debug"
			shift
			;;
		-q | --quiet)
			QUIET=1
			LOG_LEVEL="error"
			shift
			;;
		--log-level)
			if [[ -n "${2:-}" && "$2" != -* ]]; then
				case "$2" in
				debug | info | warn | error)
					LOG_LEVEL="$2"
					shift 2
					;;
				*)
					dotfiles::println 'Error: Invalid log level "%s". Use: debug, info, warn, error.' "$2" >&2
					exit 1
					;;
				esac
			else
				dotfiles::println 'Error: Missing argument for "%s".' "$1" >&2
				exit 1
			fi
			;;
		--log-level=*)
			case "${1#*=}" in
			debug | info | warn | error)
				LOG_LEVEL="${1#*=}"
				shift
				;;
			*)
				dotfiles::println 'Error: Invalid log level "%s". Use: debug, info, warn, error.' "${1#*=}" >&2
				exit 1
				;;
			esac
			;;
		--no-log)
			NO_LOG=1
			shift
			;;

		--no-deps)
			NO_DEPS=1
			shift
			;;
		--no-hooks)
			NO_HOOKS=1
			shift
			;;

		--no-restart)
			NO_RESTART=1
			shift
			;;

		*)
			dotfiles::println 'Error: Invalid parameter "%s"' "$1"
			dotfiles::println 'Run "bash %s --help" for valid options.' "$(basename "$0")" >&2
			exit 1
			;;
		esac
	done

	if [[ -z "$MODE" ]]; then
		MODE="install"
	fi

	if [[ "$MODE" != "install" && ${#INSTALL_MODULES[@]} -gt 0 ]]; then
		dotfiles::println 'Error: --install is not valid with --%s.' "$MODE" >&2
		exit 1
	fi
	if [[ "$MODE" != "install" && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
		dotfiles::println 'Error: --exclude is not valid with --%s.' "$MODE" >&2
		exit 1
	fi
	if [[ ${#INSTALL_MODULES[@]} -gt 0 && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
		dotfiles::println 'Error: --install and --exclude are mutually exclusive.' >&2
		exit 1
	fi
}

# Checks if a module should be installed based on INSTALL_MODULES and EXCLUDE_MODULES.
# Returns 0 (success/true) if it should be installed, 1 (failure/false) if skipped.
dotfiles::is_module_enabled() {
	local target_module="$1"                # e.g., "apps/git"
	local top_module="${target_module%%/*}" # e.g., "apps"
	local item

	# exclusions
	if [[ ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
		for item in "${EXCLUDE_MODULES[@]}"; do
			if [[ "$item" == "$target_module" || "$item" == "$top_module" ]]; then
				return 1
			fi
		done
	fi

	# inclusions
	if [[ ${#INSTALL_MODULES[@]} -gt 0 ]]; then
		for item in "${INSTALL_MODULES[@]}"; do
			if [[ "$item" == "$target_module" || "$item" == "$top_module" ]]; then
				return 0
			fi
		done
		return 1
	fi

	return 0
}

dotfiles::set_files_to_check() {
	# base directory constants
	readonly SHELL_DIR="${SRC_PATH}/shells"
	readonly APP_DIR="${SRC_PATH}/apps"

	# shell
	declare -r -a shell_zsh_files=(
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
	declare -r -a shell_bash_files=(
		"${SHELL_DIR}/bash/.bashrc"
		"${SHELL_DIR}/bash/.bash_profile"
	)
	# app
	declare -r -a app_ssh_files=(
		"${APP_DIR}/ssh/config" # TODO: chmod 600 when symlink
		"${APP_DIR}/ssh/allowed_signers"
	)

	declare -r -a app_curl_files=("${APP_DIR}/curl/.curlrc")
	declare -r -a app_wget_files=("${APP_DIR}/wget/.wgetrc")
	declare -a app_git_files=(
		"${APP_DIR}/git/.gitignore"
		"${APP_DIR}/git/.gitattributes"
	)
	declare -r -a app_iterm2_files=(
		"${APP_DIR}/iterm2/Profiles.json"
		"${APP_DIR}/iterm2/schemas/0x96f.itermcolors"
		"${APP_DIR}/iterm2/schemas/Argonaut.itermcolors"
		"${APP_DIR}/iterm2/schemas/Aurora.itermcolors"
		"${APP_DIR}/iterm2/schemas/Floraverse.itermcolors"
	)
	declare -r -a app_shellcheck_files=("${APP_DIR}/shellcheck/.shellcheckrc")

	case "${TARGET_OS}" in
	"${OS_MAC}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.mac")
		;;
	"${OS_ARCHLINUX}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.archlinux")
		;;
	"${OS_WINDOWS}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.windows")
		;;
	esac

	dotfiles::is_module_enabled "shells/zsh" && FILES_TO_CHECK+=("${shell_zsh_files[@]}")
	dotfiles::is_module_enabled "shells/bash" && FILES_TO_CHECK+=("${shell_bash_files[@]}")
	dotfiles::is_module_enabled "apps/ssh" && FILES_TO_CHECK+=("${app_ssh_files[@]}")
	dotfiles::is_module_enabled "apps/curl" && FILES_TO_CHECK+=("${app_curl_files[@]}")
	dotfiles::is_module_enabled "apps/wget" && FILES_TO_CHECK+=("${app_wget_files[@]}")
	dotfiles::is_module_enabled "apps/git" && FILES_TO_CHECK+=("${app_git_files[@]}")
	dotfiles::is_module_enabled "apps/shellcheck" && FILES_TO_CHECK+=("${app_shellcheck_files[@]}")
	dotfiles::is_module_enabled "apps/iterm2" && FILES_TO_CHECK+=("${app_iterm2_files[@]}")
}

dotfiles::set_log() {
	if dotfiles::is_true "${NO_LOG}"; then
		readonly DOTFILES_LOG=0
	else
		readonly DOTFILES_LOG="${DOTFILES_LOG:-1}"
	fi
}

dotfiles::do_mode() {
	case "$MODE" in
	install)
		# TODO: implement
		# TODO: symlink, env, logging, check_exists, windows pwsh handoff
		;;
	clean)
		# TODO: remove orphaned symlinks, then install/relink
		;;
	reset)
		# TODO: remove all symlinks managed by this tool
		;;
	diff)
		# TODO: show diff between current files and incoming dotfiles
		;;
	status)
		dotfiles::print_status
		exit 0
		;;
	*)
		dotfiles::println 'Error: Unknown mode "%s"' "$MODE" >&2
		exit 1
		;;
	esac
}

################
main() {
	dotfiles::bash_version_check || exit 1

	dotfiles::set_src_path # SRC_PATH
	# piped to bash
	if [[ -z "$SRC_PATH" ]]; then
		# noreturn
		dotfiles::install_from_git "$@" || exit 1
	fi

	dotfiles::set_ref # GITHUB_REF

	dotfiles::set_env || { # TARGET_OS & TARGET_RUNTIME
		dotfiles::println 'Warning: unable to determine $TARGET_OS or $TARGET_RUNTIME.'
		dotfiles::prompt_continue "Some functionality may be limited."
	}
	dotfiles::set_admin             # IS_ADMIN
	dotfiles::set_available_modules # ALL_MODULES

	dotfiles::argparse "$@"
	dotfiles::set_log # DOTFILES_LOG

	lib_dir="${SRC_PATH}/lib"
	local -r -a lib_files=("${lib_dir}/filesystem.sh" "${lib_dir}/git.sh" "${lib_dir}/template.sh")
	dotfiles::check_exists "${lib_files[@]}" || exit 1

	dotfiles::source_file "${lib_dir}/filesystem.sh" || {
		exit 1
	}
	dotfiles::source_file "${lib_dir}/git.sh" || {
		exit 1
	}
	dotfiles::source_file "${lib_dir}/template.sh" || {
		exit 1
	}

	dotfiles::print_banner

	if [[ "${UPDATE}" -eq 1 ]]; then
		dotfiles::update || exit 1
	fi

	# switch to native powershell if non sudo windows bash
	if [[ "${IS_ADMIN}" -eq 1 && "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
		case "${TARGET_RUNTIME}" in
		"${RUNTIME_GITBASH}" | "${RUNTIME_UNKNOWN}")
			if dotfiles::prompt_windows_handoff; then
				dotfiles::windows_handoff # noreturn
			fi
			;;
		*) ;;
		esac
	fi

	# figure out what files are needed based on args
	dotfiles::set_files_to_check # FILES_TO_CHECK
	# println info verifying files
	dotfiles::check_exists "${FILES_TO_CHECK[@]}" || {
		exit 1
	}
	dotfiles::println 'File(s) queued for install: %d' "${#FILES_TO_CHECK[@]}"

	# logging

	# dotfiles::print_start
	# TODO: symlink etc
	dotfiles::do_mode

	dotfiles::print_end
	if [[ -z "${NO_RESTART:-}" ]]; then
		exec zsh
	fi

	exit 0
}
main "$@" || exit 1
####################

# logging
{
	readonly LOG_LEVEL_DEBUG=0
	readonly LOG_LEVEL_INFO=1
	readonly LOG_LEVEL_SUCCESS=2
	readonly LOG_LEVEL_WARNING=3
	readonly LOG_LEVEL_ERROR=4
	readonly LOG_LEVEL_FATAL=5

	log::detail::format() {
		if [[ $# -gt 1 ]]; then
			# shellcheck disable=SC2059
			printf "$1" "${@:2}"
		else
			printf '%s' "${1:-}"
		fi
	}

	# handles colors for terminal, plain text for file.
	log::detail::emit() {
		local level_name="$1"
		local stream="$2"
		local msg="$3"

		local color_code=""
		local reset_code=""
		if [[ "${COLOUR_DEPTH}" != "none" ]]; then
			# colour if the *actual* stream is a terminal
			if [[ "$stream" -eq 2 ]] && [[ -t 2 ]]; then
				: # stderr is a TTY
			elif [[ "$stream" -eq 1 ]] && [[ -t 1 ]]; then
				: # stdout is a TTY
			else
				return_after_file=1 # skip colour, still write to file
			fi
		fi

		if [[ -z "$return_after_file" ]]; then
			case "$level_name" in
			DEBUG) color_code="${COLOUR[BOLD_GREY]}" ;;
			INFO) color_code="${COLOUR[BOLD_BLUE]}" ;;
			SUCCESS) color_code="${COLOUR[BOLD_GREEN]}" ;;
			WARNING) color_code="${COLOUR[BOLD_YELLOW]}" ;;
			ERROR | FATAL | DEVELOPER) color_code="${COLOUR[BOLD_RED]}" ;;
			esac
			reset_code="${COLOUR[RESET]}"
		fi
		# terminal output
		if [[ "$stream" -eq 2 ]]; then
			printf "%s[ %s ]%b %s\n" "${color_code}" "${level_name}" "${reset_code}" "${msg}" >&2
		else
			printf "%s[ %s ]%b %s\n" "${color_code}" "${level_name}" "${reset_code}" "${msg}"
		fi

		# file
		if [[ -n "${INSTALL_LOG_FILE:-}" ]]; then
			local ts
			ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
			printf "[%s] [ %s ] %s\n" "$ts" "$level_name" "$msg" >>"$INSTALL_LOG_FILE"
		fi
	}

	log::info() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_INFO)) && return 0
		local msg
		msg="$(log::detail::format "$@")"
		log::detail::emit "INFO" 1 "$msg"
	}

	log::success() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_SUCCESS)) && return 0
		local msg
		msg="$(log::detail::format "$@")"
		log::detail::emit "SUCCESS" 1 "$msg"
	}

	log::warning() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_WARNING)) && return 0
		local msg
		msg="$(log::detail::format "$@")"
		log::detail::emit "WARNING" 2 "$msg"
	}

	log::error() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_ERROR)) && return 0
		local msg
		msg="$(log::detail::format "$@")"
		log::detail::emit "ERROR" 2 "$msg"
	}

	log::fatal() {
		local msg
		msg="$(log::detail::format "$@")"
		log::detail::emit "FATAL" 2 "$msg"
		exit 1
	}

	# Output detailed error message in COLOUR["BOLD_RED"]
	# Usage: log::dev_fatal <message_or_format> [args...]
	#
	# Arguments:
	#   $1 (format) : The error message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	#
	# Returns:
	#   Outputs the formatted error string to stderr and exists.
	#
	# Examples:
	#   [ DEV_ERROR ] file: main.sh(25) `main`: Uh oh! An unspecified developer error occurred.
	log::dev_fatal() {
		# set stack level (immediate caller)
		local -i level=1
		local -i line_level=$((level - 1))

		local -r caller_file="${BASH_SOURCE[$level]:-Unknown}"
		local -r caller_line="${BASH_LINENO[$line_level]:-Unknown}"
		local -r caller_func="${FUNCNAME[$level]:-main}"
		local -r base_file="${caller_file##*/}"

		local msg
		msg="$(log::detail::format "$@")"
		msg="${msg:-Uh oh! An unspecified developer error occurred.}"

		local -r trace_msg="file: ${base_file}(${caller_line}) \`${caller_func}()\`: ${msg}"
		log::detail::emit "DEVELOPER" 2 "$trace_msg"

		exit 1
	}
}

filesystem::install_symlink "$HOME" "${BARE_FILES[@]}" "$GIT_DIR"/* "$ZSH_DIR"/*

log::step "Setting up local configuration templates"

# FIXME: platform specific
declare -r LOCAL_ZSH="$HOME/.zshrc.local"
declare -r ZSH_TEMPLATE="$TEMPLATE_DIR/.zshrc.template"

declare -r LOCAL_GITCONFIG="$HOME/.gitconfig.local"

template::install "$LOCAL_ZSH" "$ZSH_TEMPLATE" || missing_deps=1
template::validate "$LOCAL_ZSH" "${INVALID_TOKEN}" || missing_deps=1

if [[ "$os_suffix" != "unknown" ]]; then
	gitconfig_src="$TEMPLATE_DIR/.gitconfig.${RUNTIME_SUFFIX}"

	filesystem::install_local "$gitconfig_src" "$LOCAL_GITCONFIG" || missing_deps=1
	#TODO: zsh
fi
