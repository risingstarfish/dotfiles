#!/usr/bin/env bash
# install.sh

set -euo pipefail

if [[ -n "${__INSTALL_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __INSTALL_SH_INCLUDED__=1
#######
IS_ELEVATED=false
SRC_PATH=""

readonly REPO_URL="https://github.com/risingstarfish/dotfiles.git"
REF=""
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

TARGET_OS="${OS_UNKNOWN}"
TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
# argparse
NO_RESTART=0
DRY_RUN=0
FORCE=0
UPDATE=0
INTERACTIVE=0
NO_BACKUP=0
NO_DEPS=0
NO_HOOKS=0
NO_LOG=0
VERBOSE=0
QUIET=0
MODE=""
LOG_LEVEL="info"
INSTALL_MODULES=()
EXCLUDE_MODULES=()
# windows TODO: possible add any1 with pwsh
PWSH_CMD=""

#######
dotfiles::println() {
	if [[ $# -gt 1 ]]; then
		# format
		command printf "$1\n" "${@:2}"
	else
		# single string
		command printf '%s\n' "${1:-}"
	fi
}
###################
# NOTE: required commands:
# all: git
# mac: bash

# TODO: maybe install package mac
dotfiles::bash_version_check() {
	if [ -z "${BASH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
		dotfiles::println 'Error: the install instructions explicitly say to use the install script with bash; please follow them.' >&2
		exit 1
	fi
	# script requires bash >=4.0
	if ((BASH_VERSINFO[0] < 4)); then
		local msg="Error: This script requires bash v4.0 or newer. You are running ${BASH_VERSION}."

		if [[ "$(uname -s)" == "Darwin" ]]; then
			msg+=$'\n
  On macOS, the default bash is severely outdated (v3.2).
  Please install modern bash via Homebrew:
    brew install bash
  or via MacPorts:
    sudo port install bash

  Then restart your terminal and run this script again using the new bash.'
		fi

		dotfiles::println "${msg}" >&2
		exit 1
	fi
}

# Detect if script was run as sudo or root.
# Usage: set_admin
dotfiles::set_admin() {
	if [[ "$EUID" -eq 0 || -n "${SUDO_USER:-}" ]]; then
		readonly IS_ELEVATED=true
	elif [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]] && net session >/dev/null 2>&1; then
		# net session fails with exit code 5 if not admin
		readonly IS_ELEVATED=true
	else
		readonly IS_ELEVATED=false
	fi
}

# Detects and sets TARGET_OS and TARGET_RUNTIME. Validates by comparing
# against OS_UNKNOWN and RUNTIME_UNKNOWN
# Usage: set_env
#
# Returns:
#   0 if TARGET_OS and TARGET_RUNTIME are set
#   1 if TARGET_OS and TARGET_RUNTIME remain 'unknown'
dotfiles::set_env() {
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
			readonly TARGET_OS
			readonly TARGET_RUNTIME

			return 1
		fi
		;;
	esac

	return 0
}

###################
# util
{
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

		printf "\n=> Do you want to continue anyway? [y/N]: " >&2

		local choice
		while true; do
			if ! read -r choice; then
				dotfiles::println "Error: No input available for prompt." >&2
				return 1
			fi

			case "$choice" in
			[yY])
				return 0
				;;
			[nN])
				dotfiles::println "Aborting installation!" >&2
				exit 1
				;;
			*)
				dotfiles::println "Error: Invalid input. Please enter y or n." >&2
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
  -c, --clean               Remove orphaned symlinks, then install/relink
      --reset               Remove all symlinks managed by this tool
  -i, --install <module>    Run only for the specified modules, semicolon-separated
  -x, --exclude <module>    Run for all modules EXCEPT those specified, semicolon-separated
  -l, --list                List all available modules
  -d, --diff                Show diff between current files and incoming dotfiles

SAFETY
  -n, --dry-run             Print planned actions without modifying the disk
  -I, --interactive         Prompt for confirmation before every overwrite
  -f, --force               Overwrite existing files/links without prompting
      --no-backup           Delete existing conflicting files instead of backing up

LOGGING
  -v, --verbose             Print detailed step-by-step instructions
  -q, --quiet               Suppress all standard output except errors
      --log-level <level>   Set log verbosity | debug, info, warn, or error (default: info)
      --no-log              Disable writing to the log file (env: DOTFILES_DISABLE_LOG)

PACKAGES
      --no-deps         Skip dotfiles dependency installation
      --no-hooks            Skip pre/post installation scripts

GENERAL
  -s, --status              Show current installation status of modules
      --version             Show the version and git information of this program
  -h, --help                Show this help message

Environment Variables:
  DOTFILES_LOG_DIR          Path to store log files (default: ~/.config/dotfiles/logs)
  DOTFILES_CACHE_DIR        Path to store temporary cache (default: ~/.cache/dotfiles)

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
		dotfiles::println "TODO: implement"
	}

	# pictures
	{
		dotfiles::print_banner() {
			cat <<'EOF'

  ____        _    __ _ _           
 |  _ \  ___ | |_ / _(_) | ___  ___ 
 | | | |/ _ \| __| |_| | |/ _ \/ __|
 | |_| | (_) | |_|  _| | |  __/\__ \\
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
			if [[ -z "${NO_RESTART:-}" ]]; then
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
		if [[ -n "${INSTALL_DIR:-}" ]]; then
			printf "%s" "${INSTALL_DIR}"
		else
			dotfiles::default_install_dir
		fi
	}

	dotfiles::install_from_git() {
		local -r install_dir="$(dotfiles::install_dir)"
		local -r ref="${DOTFILES_REF:-main}"

		# path is not directory
		if [[ -e "${install_dir}" && ! -d "${install_dir}" ]]; then
			dotfiles::println 'Error: path "%s" is not a directory.' "${install_dir}" >&2
			exit 1
		fi
		# already cloned
		if [[ -d "${install_dir}/.git" ]]; then
			if [[ -f "${install_dir}/install.sh" ]]; then
				dotfiles::println '=> Existing clone at %s.' "${install_dir}"
				exec bash "${install_dir}/install.sh" "$@"
			else # random repo
				dotfiles::println 'Error: %s/.git exists but %s does not.' \
					"${install_dir}" "install.sh" >&2
				dotfiles::println '  This does not appear to be a dotfiles clone.' >&2
				dotfiles::println '  Remove it or set INSTALL_DIR to a different path.' >&2
				exit 1
			fi
		fi
		# non-empty dir and NOT git clone
		if [[ -d "${install_dir}" && -n "$(ls -A "${install_dir}" 2>/dev/null)" ]]; then
			dotfiles::println 'Error: %s is not empty and is not a git clone.' "${install_dir}" >&2
			dotfiles::println '  Move it aside or set INSTALL_DIR to a different path.' >&2
			exit 1
		fi
		# install_dir does not exist
		mkdir -p "${install_dir}" || {
			dotfiles::println 'Error: cannot create %s' "${install_dir}" >&2
			exit 1
		}

		dotfiles::println '=> Cloning %s (ref: %s) to %s' "${REPO_URL}" "${ref}" "${install_dir}"
		command git clone --depth=1 -b "$ref" "$REPO_URL" "${install_dir}" || {
			dotfiles::println 'Error: Clone failed for %s (ref: %s)' "${REPO_URL}" "${ref}" >&2
			exit 1
		}

		command git -C "${install_dir}" reflog expire --expire=now --all 2>/dev/null || true
		command git -C "${install_dir}" gc --auto --prune=now 2>/dev/null || true

		# restart script with local copy
		dotfiles::println "=> Restarting script with local copy." # TODO: read -p
		exec bash "${install_dir}/install.sh" "$@"
	}

	############
	# set the absolute directory path of this script
	# Source - https://stackoverflow.com/a/246128
	dotfiles::src_path() {
		local source_path="${BASH_SOURCE[0]}"
		# piped to bash
		if [[ -z "${source_path}" ]]; then
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

		printf '%s\n' "$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
	}

	dotfiles::update() {
		if [[ ! -d "${SRC_PATH}/.git" ]]; then
			dotfiles::println 'Error: %s is not a git clone. Run install first.' "${SRC_PATH}" >&2
			exit 1
		fi

		local has_local_mods=0
		if ! command git -C "${SRC_PATH}" diff --quiet HEAD 2>/dev/null; then
			has_local_mods=1
		fi

		# ── Normal user: block hard ──────────────────────────────────
		if ((has_local_mods)) && [[ -z "${DOTFILES_ALLOW_LOCAL_MODS:-}" ]]; then
			cat <<EOF >&2

Error: You have uncommitted changes in ${SRC_PATH}:
$(command git -C "${SRC_PATH}" diff --stat HEAD 2>/dev/null)

  This repo is publicly maintained. Do not edit tracked files directly.
  Use .local override files for personal customisation:
    e.g.  tmux.conf  →  tmux.conf.local

  Revert your changes or move them to a .local file, then re-run:
    bash $(basename "$0") --update

  (dev: set DOTFILES_ALLOW_LOCAL_MODS=1 to bypass this check)

EOF
			exit 1
		fi

		# ── Dev override: rebase instead of force-checkout ──────────
		if ((has_local_mods)) && [[ -n "${DOTFILES_ALLOW_LOCAL_MODS:-}" ]]; then
			dotfiles::println '=> Local modifications detected. Rebasing instead of force-checkout.'
			dotfiles::println '  Your changes will be preserved on top of the latest %s.' "$REF"

			if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "$REF" 2>/dev/null; then
				dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "$REF" >&2
				exit 1
			fi
			if ! command git -C "${SRC_PATH}" rebase FETCH_HEAD 2>/dev/null; then
				dotfiles::println 'Error: Rebase failed. Resolve conflicts, then:' >&2
				dotfiles::println '    git -C "%s" rebase --continue' "${SRC_PATH}" >&2
				dotfiles::println '  Or abort with:' >&2
				dotfiles::println '    git -C "%s" rebase --abort' "${SRC_PATH}" >&2
				exit 1
			fi
			return 0
		fi

		dotfiles::println '=> Updating dotfiles in %s' "${SRC_PATH}"

		local fetch_ok=1
		if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "$REF" 2>/dev/null; then
			fetch_ok=0
			dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "$REF" >&2
			dotfiles::prompt_continue "Your files may be overwritten\n" || exit 1
			dotfiles::println '  Continuing with current local state.'
		fi
		if ((fetch_ok)); then
			if ! command git -C "${SRC_PATH}" checkout -f FETCH_HEAD 2>/dev/null; then
				dotfiles::println 'Error: Checkout of %s failed in %s' "$REF" "${SRC_PATH}" >&2
				exit 1
			fi
		fi

	}
}

# Determine which PowerShell binary to use and set PWSH_CMD to it
dotfiles::set_pwsh_cmd() {
	if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
		if PWSH_CMD=$(command -v pwsh.exe 2>/dev/null); then
			readonly PWSH_CMD
		elif PWSH_CMD=$(command -v powershell.exe 2>/dev/null); then
			readonly PWSH_CMD
		else
			readonly PWSH_CMD
		fi
	else # linux
		if PWSH_CMD=$(command -v pwsh 2>/dev/null); then
			readonly PWSH_CMD
		else
			readonly PWSH_CMD
		fi
	fi
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
		local msg="Missing ${#missing_paths[@]} path(s):"
		for missing in "${missing_paths[@]}"; do
			# '[ DEV_ERROR ]  ' 15 chars
			#       vvv indent 2 		 15 chars vvv
			printf -v msg "%s\n✗ %s" "${msg}" "${missing}"
		done

		#log::dev_fatal "%s" "${msg}"
		exit 1
	fi

	return 0
}

#######################################

# $1 = flag name for the error message
# $2 = value to assign to MODE
dotfiles::set_mode() {
	if [[ -n "$MODE" ]]; then
		dotfiles::println "Error: Cannot specify multiple actions. %s conflicts with '%s'" "$1" "$MODE" >&2
		exit 1
	fi
	MODE="$2"
}

# $1 = raw semicolon-separated string
# $2 = name of the target array (nameref, bash ≥ 4.3)
dotfiles::parse_module_list() {
	local -n arr="$2"
	local m
	local top
	local sub
	local valid
	local -a mods

	IFS=';' read -ra mods <<<"$1"
	for m in "${mods[@]}"; do
		[[ -z "$m" ]] && continue
		valid=0

		if [[ "$m" == *:* ]]; then
			top="${m%%:*}"
			sub="${m#*:}"
			case "$top" in
			apps)
				case "$sub" in
				curl | fastfetch | git | iterm2 | oh-my-posh | shellcheck | ssh | tmux | wget) valid=1 ;;
				esac
				;;
			os)
				case "$sub" in
				archlinux | debian | mac | windows) valid=1 ;;
				esac
				;;
			runtime)
				case "$sub" in
				gitbash | msys | native | wsl) valid=1 ;;
				esac
				;;
			shells)
				case "$sub" in
				bash | pwsh | zsh) valid=1 ;;
				esac
				;;
			esac
		else
			case "$m" in
			apps | configs | docs | lib | llama-launcher | os | runtime | setup | shells) valid=1 ;;
			esac
		fi

		if [[ $valid -eq 0 ]]; then
			dotfiles::println "Error: Unknown module '%s'" "$m" >&2
			exit 1
		fi
		arr+=("$m")
	done
}

dotfiles::argparse() {
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
		-c | --clean)
			dotfiles::set_mode "--clean" "clean"
			shift
			;;
		--reset)
			dotfiles::set_mode "--reset" "reset"
			shift
			;;
		-l | --list)
			dotfiles::set_mode "--list" "list"
			shift
			;;
		-d | --diff)
			dotfiles::set_mode "--diff" "diff"
			shift
			;;
		-i | --install)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println "Error: Missing argument for %s" "$1" >&2
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
				dotfiles::println "Error: Missing argument for %s" "$1" >&2
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
			if [[ "${FORCE}" == 1 ]]; then
				dotfiles::println "Error: --interactive conflicts with --force" >&2
				exit 1
			fi
			INTERACTIVE=1
			shift
			;;
		-f | --force)
			if [[ "${INTERACTIVE}" == 1 ]]; then
				dotfiles::println "Error: --force conflicts with --interactive" >&2
				exit 1
			fi
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
					dotfiles::println "Error: Invalid log level '%s'. Use: debug, info, warn, error" "$2" >&2
					exit 1
					;;
				esac
			else
				dotfiles::println "Error: Missing argument for %s" "$1" >&2
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
				dotfiles::println "Error: Invalid log level '%s'. Use: debug, info, warn, error" "${1#*=}" >&2
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
			dotfiles::println "Error: Invalid parameter %s" "$1"
			dotfiles::println "Run bash %s --help for valid options." "$(basename "$0")" >&2
			exit 1
			;;
		esac
	done

	if [[ -z "$MODE" ]]; then
		MODE="install"
	fi

	if [[ "$MODE" != "install" && ${#INSTALL_MODULES[@]} -gt 0 ]]; then
		dotfiles::println "Error: --install is not valid with --%s" "$MODE" >&2
		exit 1
	fi
	if [[ "$MODE" != "install" && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
		dotfiles::println "Error: --exclude is not valid with --%s" "$MODE" >&2
		exit 1
	fi
	if [[ ${#INSTALL_MODULES[@]} -gt 0 && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
		dotfiles::println "Error: --install and --exclude are mutually exclusive" >&2
		exit 1
	fi
	# TODO: process args
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
	list)
		# TODO: list all available modules
		# TODO: also list available upstream
		;;
	diff)
		# TODO: show diff between current files and incoming dotfiles
		;;
	status)
		dotfiles::print_status
		;;
	*)
		dotfiles::println "Error: Unknown mode '%s'" "$MODE" >&2
		exit 1
		;;
	esac
}

main() {
	dotfiles::bash_version_check
	dotfiles::set_admin

	SRC_PATH="$(dotfiles::src_path)"
	readonly SRC_PATH
	# piped to bash
	if [[ -z "$SRC_PATH" ]]; then
		dotfiles::install_from_git "$@" # noreturn
	fi

	REF="$(command git -C "${SRC_PATH}" config --local dotfiles.ref 2>/dev/null)"
	readonly REF="${REF:-main}"

	# TODO: bootstrap # move deps to bootstrap # check_exists
	# lib_files=
	# check_exists
	dotfiles::argparse "$@"

	dotfiles::print_banner

	dotfiles::set_env || {
		dotfiles::println "Warning: unable to determine \$TARGET_OS or \$TARGET_RUNTIME"
		dotfiles::prompt_continue "Some modules may be skipped"
	}

	dotfiles::set_pwsh_cmd
	# logging
	# check_exists base bootstrap files

	if [[ "${UPDATE}" -eq 1 ]]; then
		dotfiles::update
	fi
	# windows prompt powershell handoff
	# check_exists
	dotfiles::print_start
	# TODO: symlink etc
	dotfiles::do_mode

	dotfiles::print_end
	if [[ -z "${NO_RESTART:-}" ]]; then
		exec zsh
	fi

	exit 0
}
####################
main "$@" || exit 1

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

# utils
{
	# Safely sources a file, validating existence and permissions first.
	# Usage: source_file <file_path>
	#
	# Arguments:
	#   $1 (file_path) : The absolute or relative path to the file to source.
	#
	# Returns:
	#   0 on success, or triggers log::dev_fatal on failure.
	source_file() {
		local target_file="$1"

		if [[ -z "${target_file}" ]]; then
			log::dev_fatal "source_file called without a file path argument."
		fi

		if [[ ! -f "${target_file}" ]]; then
			log::dev_fatal "Cannot source '%s': File does not exist or is a directory." "${target_file}"
		fi

		if [[ ! -r "${target_file}" ]]; then
			log::dev_fatal "Cannot source '%s': Read permission denied." "${target_file}"
		fi

		source "${target_file}" || {
			local err_code=$?
			log::dev_fatal "File '%s' was read, but execution failed with exit code %d." "${target_file}" "${err_code}"
		}

		return 0
	}

}

# windows
{
	# Executes PowerShell handoff and exits the bash script.
	# Never returns to the caller if successful (exits with PowerShell's exit code).
	windows_handoff() {
		local ps_script="$SRC_DIR/install.ps1"
		if [[ ! -f "${ps_script}" ]]; then
			log::dev_fatal "Unable to find install.ps1."
		fi

		# convert unix paths to windows
		if [[ "${TARGET_RUNTIME}" == "${RUNTIME_WSL}" ]]; then
			ps_script=$(wslpath -w "$ps_script")
		fi

		local -a ps_args=("-NoProfile" "-ExecutionPolicy" "Bypass" "-File" "$ps_script")

		if [[ $IS_ELEVATED -eq 1 ]]; then
			ps_args+=("-IsElevated")
		fi

		printf "\n%b==>%b Handing off execution to %b%s%b...\n" \
			"${COLOUR["BOLD_BLUE"]}" "${COLOUR["RESET"]}" "${COLOUR["BOLD_GREEN"]}" "${PWSH_CMD}" "${COLOUR["RESET"]}"

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
	prompt_windows_handoff() {
		if [[ "${TARGET_RUNTIME}" == "${RUNTIME_GITBASH}" ]]; then
			printf "\n%b==>%b %bWindows Git Bash runtime detected.%b\n" \
				"${COLOUR["BOLD_BLUE"]}" "${COLOUR["RESET"]}" "${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2

			printf "%b==>%b %b(Note: If you are not actually running Git Bash, something went wrong)%b\n" \
				"${COLOUR["BOLD_YELLOW"]}" "${COLOUR["RESET"]}" "${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2
		else # unknown
			printf "\n%b==>%b %bUnknown Windows Bash runtime detected.%b\n" \
				"${COLOUR["BOLD_YELLOW"]}" "${COLOUR["RESET"]}" "${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2

			printf "    %bBash scripts may fail to configure native Windows settings properly.%b\n" \
				"${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2
		fi

		printf "    %bCertain functionality such as symlinking will ask for permissions if this script was not run with sudo.%b\n" \
			"${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2

		local choice
		while true; do
			printf "%b==>%b %bSwitch to the native PowerShell installer (install.ps1)? [Y/n]: %b" \
				"${COLOUR["BOLD_YELLOW"]}" "${COLOUR["RESET"]}" "${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2

			read -r choice

			case "$choice" in
			[yY])
				# verify powershell available
				if [[ -z "${PWSH_CMD}" ]]; then
					log::error "Cannot locate %bpwsh.exe%b or %bpowershell.exe%b" \
						"${COLOUR["YELLOW"]}" "${COLOUR["RESET"]}" "${COLOUR["YELLOW"]}" "${COLOUR["RESET"]}"
					exit 1
				fi
				return 0
				;;
			[nN])
				printf "\n%b==>%b Continuing with Bash installer on Windows...\n" \
					"${COLOUR["BOLD_BLUE"]}" "${COLOUR["RESET"]}"
				return 1
				;;
			*)
				printf "\n%bInvalid input. Please enter y or n.%b\n" "${COLOUR["RED"]}" "${COLOUR["RESET"]}" >&2
				;;
			esac
		done
	}

	if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
		case "${TARGET_RUNTIME}" in
		"${RUNTIME_GITBASH}" | "${RUNTIME_UNKNOWN}")
			if prompt_windows_handoff; then
				windows_handoff
			fi
			;;
		*) ;;

		esac
	fi
	unset -f prompt_windows_handoff windows_handoff
}

# required paths for installation
{
	# base directory constants
	readonly LIB_DIR="${SRC_DIR}/lib"
	readonly OS_DIR="${SRC_DIR}/os"
	readonly RUNTIME_DIR="${SRC_DIR}/runtime"
	readonly SHELL_DIR="${SRC_DIR}/shells"
	readonly APP_DIR="${SRC_DIR}/apps"

	# paths
	{
		# dev
		declare -r -a dev_files=(
			"${SRC_DIR}/mode.sh"
			"${SRC_DIR}/usage.sh"
		)
		# lib
		declare -r -a lib_files=(
			"${LIB_DIR}/bootstrap.sh"
			"${LIB_DIR}/common.sh"
			"${LIB_DIR}/filesystem.sh"
			"${LIB_DIR}/git.sh"
			"${LIB_DIR}/template.sh"
		)

		# OS
		declare -r -a os_mac_files=(
			"${OS_DIR}/mac/TODO"
		)
		declare -r -a os_archlinux_files=(
			"${OS_DIR}/archlinux/TODO"
		)
		declare -r -a os_debian_files=(
			"${OS_DIR}/debian/TODO"
		)
		declare -r -a os_windows_files=(
			"${OS_DIR}/windows/TODO"
		)

		# runtime
		declare -r -a runtime_native_files=(
			"${RUNTIME_DIR}/native/TODO"
		)
		declare -r -a runtime_wsl_files=(
			"${RUNTIME_DIR}/wsl/TODO"
		)
		declare -r -a runtime_msys_files=(
			"${RUNTIME_DIR}/msys/TODO"
		)
		declare -r -a runtime_gitbash_files=(
			"${RUNTIME_DIR}/gitbash/TODO"
		)

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
		# declare -a shell_pwsh_files=()

		# app
		declare -r -a app_ssh_files=(
			"${APP_DIR}/ssh/config" # TODO: remember chmod 600 when symlink
			"${APP_DIR}/ssh/allowed_signers"
		)
		declare -r -a app_curl_files=("${APP_DIR}/curl/.curlrc")
		declare -r -a app_wget_files=("${APP_DIR}/wget/.wgetrc")
		declare -a app_git_files=(
			"${APP_DIR}/git/.gitignore"
			"${APP_DIR}/git/.gitattributes"
			#"${APP_DIR}/git/.gitconfig.global"
		)
		declare -a app_fastfetch_files=(
			"${APP_DIR}/fastfetch/default.config.jsonc" # fallback
		)

		# os specific
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

		# runtime specific
		if [[ "${TARGET_RUNTIME}" == "${RUNTIME_WSL}" ]]; then
			app_git_files+=("${APP_DIR}/git/.gitconfig.wsl")
		fi

		declare -r app_git_files
		declare -r app_fastfetch_files

		# base files required across all machines
		declare -a files_to_check=(
			"${dev_files[@]}"
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

		case "${TARGET_RUNTIME}" in
		"${RUNTIME_GITBASH}")
			files_to_check+=("${runtime_gitbash_files[@]}" "${shell_bash_files[@]}")
			;;
		"${RUNTIME_WSL}")
			files_to_check+=("${runtime_wsl_files[@]}")
			;;
		"${RUNTIME_MSYS}")
			files_to_check+=("${runtime_msys_files[@]}")
			;;
		"${RUNTIME_NATIVE}")
			files_to_check+=("${runtime_native_files[@]}")
			;;
		esac

		declare -r files_to_check
	}

	check_exists "${files_to_check[@]}"
	unset -f check_exists
}

###################
# print banner
print_banner
source_file "${LIB_DIR}/bootstrap.sh"

{
	{
		{
			log::dev_fatal "End of script"
		}
	}
}

source_deps "common.sh" "log.sh" "filesystem.sh" "git.sh" "template.sh" || exit 1
###################
# initial checks
# FIXME: move required checks here

# validate input and check for help flag
source "$SRC_DIR/usage.sh" "$(basename "$0")" "$@" || exit 1
# determine specific OS to source correct source file, output, etc.
get_os_suffix() {
	if [[ -n "${FORCE_RUNTIME_SUFFIX:-}" ]]; then
		echo "${FORCE_RUNTIME_SUFFIX}"
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

RUNTIME_SUFFIX="$(get_os_suffix)" || {
	log::warning "To force install, run: \e[36m'bash %s --os <mac|linux|win|wsl>'\e[0m" "$0"
	log::warning "Unknown OS. Cannot determine which configuration files to install."
	prompt_continue
}
readonly RUNTIME_SUFFIX
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
	log::error "Installation cannot proceed."
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
	gitconfig_src="$TEMPLATE_DIR/.gitconfig.${RUNTIME_SUFFIX}"

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

# NOTE: not used
# Restart script with admin rights
elevate() {
	if [[ "${IS_ELEVATED}" -eq 1 ]]; then
		return 0
	fi

	printf "\n%b==>%b %bElevated privileges are required. Requesting access...%b\n" \
		"${COLOUR["BOLD_BLUE"]}" "${COLOUR["RESET"]}" "${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2

	if [[ "${TARGET_OS}" == "OS_WINDOWS" ]]; then
		if command -v sudo >/dev/null 2>&1; then
			exec sudo bash "$0" "$@" || {
				log::error "Failed to gain admin rights with Windows sudo."
				exit 1
			}
		fi

		# no sudo so verify powershell available
		if [[ -z "${PWSH_CMD}" ]]; then
			log::error "Cannot locate %bpwsh.exe%b or %bpowershell.exe%b" \
				"${COLOUR["YELLOW"]}" "${COLOUR["RESET"]}" "${COLOUR["YELLOW"]}" "${COLOUR["RESET"]}"
			exit 1
		fi

		# fallback to UAC elevation
		local script_path="${SCRIPT_FILE}"

		# convert to Windows path
		if command -v cygpath >/dev/null 2>&1; then
			script_path="$(cygpath -w "${script_path}")"
		elif command -v wslpath >/dev/null 2>&1; then
			script_path="$(wslpath -w "${script_path}")"
		fi

		local escaped_args
		printf -v escaped_args '%q ' "$@"

		# pause script at end so user can read output
		local bash_cmd="\"${script_path}\" ${escaped_args}; echo ''; read -r -p 'Press Enter to exit...'"
		local -a ps_args=(
			"-NoProfile"
			"-Command" "Start-Process"
			"-FilePath" "'bash'"
			"-ArgumentList" "'-c', \"${bash_cmd}\""
			"-Verb" "RunAs"
		)

		exec "${PWSH_CMD}" "${ps_args[@]}" || {
			log::error "Failed to gain admin rights via UAC."
			exit 1
		}
	else
		exec sudo bash "${SCRIPT_FILE}" "$@" || {
			log::error "Failed to gain admin rights with sudo."
			exit 1
		}
	fi
}
