#!/usr/bin/env bash
# install.sh

set -euo pipefail

if [[ -n "${__INSTALL_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __INSTALL_SH_INCLUDED__=1
###################
# script requires bash >=4.0
if ((BASH_VERSINFO[0] < 4)); then
	printf "\e[31m[ ERROR ]\e[0m This script requires Bash 4.0 or newer. You are running \e[33m%s\e[0m\n" "${BASH_VERSION}" >&2

	if [[ "$(uname -s)" == "Darwin" ]]; then
		printf "\nOn macOS, the default Bash is severely outdated (v3.2).\n" >&2
		printf "Please install modern Bash via Homebrew by running:\n" >&2
		printf "  \e[1;32mbrew install bash\e[0m\n\n" >&2
		printf "Then, restart your terminal and run this script again using the new Bash.\n" >&2
	fi
	exit 1
fi

###################
# colour constants
{
	COLOUR_DEPTH="16"
	declare -A COLOUR

	# Detects the maximum supported colour depth of the terminal.
	# Usage: detect_colour_support
	# Returns string via stdout: "none", "16", "256", or "truecolor"
	detect_colour_support() {
		if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
			printf "none"
			return 0
		fi

		if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]; then
			printf "truecolor"
			return 0
		fi

		# query terminal database
		if command -v tput &>/dev/null; then
			local tput_colors
			# suppress errors in case tput fails (e.g., missing terminfo)
			tput_colors=$(tput colors 2>/dev/null || echo 0)

			if ((tput_colors >= 256)); then
				printf "256"
				return 0
			elif ((tput_colors >= 8)); then
				printf "16"
				return 0
			fi
		fi

		if [[ "${TERM:-}" == *"-256color"* || "${TERM:-}" == *"xterm-256"* ]]; then
			printf "256"
			return 0
		fi
		# fallback
		printf "16"
	}
	COLOUR_DEPTH="$(detect_colour_support)"
	unset -f detect_colour_support
	readonly COLOUR_DEPTH

	case "${COLOUR_DEPTH}" in
	"none")
		COLOUR["RESET"]=""
		COLOUR["BLACK"]=""
		COLOUR["GREY"]=""
		COLOUR["RED"]=""
		COLOUR["GREEN"]=""
		COLOUR["YELLOW"]=""
		COLOUR["BLUE"]=""
		COLOUR["MAGENTA"]=""
		COLOUR["CYAN"]=""
		COLOUR["WHITE"]=""

		COLOUR["BOLD_BLACK"]=""
		COLOUR["BOLD_GREY"]=""
		COLOUR["BOLD_RED"]=""
		COLOUR["BOLD_GREEN"]=""
		COLOUR["BOLD_YELLOW"]=""
		COLOUR["BOLD_BLUE"]=""
		COLOUR["BOLD_MAGENTA"]=""
		COLOUR["BOLD_CYAN"]=""
		COLOUR["BOLD_WHITE"]=""
		;;
	"16")
		COLOUR["RESET"]="\e[0m"
		COLOUR["BLACK"]="\e[30m"
		COLOUR["GREY"]="\e[90m"
		COLOUR["RED"]="\e[91m"
		COLOUR["GREEN"]="\e[92m"
		COLOUR["YELLOW"]="\e[93m"
		COLOUR["BLUE"]="\e[94m"
		COLOUR["MAGENTA"]="\e[95m"
		COLOUR["CYAN"]="\e[96m"
		COLOUR["WHITE"]="\e[97m"

		COLOUR["BOLD_BLACK"]="\e[1;30m"
		COLOUR["BOLD_GREY"]="\e[1;90m"
		COLOUR["BOLD_RED"]="\e[1;91m"
		COLOUR["BOLD_GREEN"]="\e[1;92m"
		COLOUR["BOLD_YELLOW"]="\e[1;93m"
		COLOUR["BOLD_BLUE"]="\e[1;94m"
		COLOUR["BOLD_MAGENTA"]="\e[1;95m"
		COLOUR["BOLD_CYAN"]="\e[1;96m"
		COLOUR["BOLD_WHITE"]="\e[1;97m"
		;;
	"256")
		COLOUR["RESET"]="\e[0m"
		COLOUR["BLACK"]="\e[38;5;0m"
		COLOUR["GREY"]="\e[38;5;8m"
		COLOUR["RED"]="\e[38;5;9m"
		COLOUR["GREEN"]="\e[38;5;10m"
		COLOUR["YELLOW"]="\e[38;5;11m"
		COLOUR["BLUE"]="\e[38;5;12m"
		COLOUR["MAGENTA"]="\e[38;5;13m"
		COLOUR["CYAN"]="\e[38;5;14m"
		COLOUR["WHITE"]="\e[38;5;15m"

		COLOUR["BOLD_BLACK"]="\e[1;38;5;0m"
		COLOUR["BOLD_GREY"]="\e[1;38;5;8m"
		COLOUR["BOLD_RED"]="\e[1;38;5;9m"
		COLOUR["BOLD_GREEN"]="\e[1;38;5;10m"
		COLOUR["BOLD_YELLOW"]="\e[1;38;5;11m"
		COLOUR["BOLD_BLUE"]="\e[1;38;5;12m"
		COLOUR["BOLD_MAGENTA"]="\e[1;38;5;13m"
		COLOUR["BOLD_CYAN"]="\e[1;38;5;14m"
		COLOUR["BOLD_WHITE"]="\e[1;38;5;15wm"
		;;
	"truecolor")
		COLOUR["RESET"]="\e[0m"
		COLOUR["BLACK"]="\e[38;2;0;0;0m"
		COLOUR["GREY"]="\e[38;2;128;128;128m"
		COLOUR["RED"]="\e[38;2;255;0;0m"
		COLOUR["GREEN"]="\e[38;2;0;255;0m"
		COLOUR["YELLOW"]="\e[38;2;255;255;0m"
		COLOUR["BLUE"]="\e[38;2;0;0;255m"
		COLOUR["MAGENTA"]="\e[38;2;255;0;255m"
		COLOUR["CYAN"]="\e[38;2;0;255;255m"
		COLOUR["WHITE"]="\e[38;2;255;255;255m"

		COLOUR["BOLD_BLACK"]="\e[1;38;2;0;0;0m"
		COLOUR["BOLD_GREY"]="\e[1;38;2;128;128;128m"
		COLOUR["BOLD_RED"]="\e[1;38;2;255;0;0m"
		COLOUR["BOLD_GREEN"]="\e[1;38;2;0;255;0m"
		COLOUR["BOLD_YELLOW"]="\e[1;38;2;255;255;0m"
		COLOUR["BOLD_BLUE"]="\e[1;38;2;0;0;255m"
		COLOUR["BOLD_MAGENTA"]="\e[1;38;2;255;0;255m"
		COLOUR["BOLD_CYAN"]="\e[1;38;2;0;255;255m"
		COLOUR["BOLD_WHITE"]="\e[1;38;2;255;255;255m"
		;;
	esac

	readonly -A COLOUR
}

# detect script directory
{
	SCRIPT_DIR=""  # source directory of script
	SCRIPT_FILE="" # current file

	# set the absolute directory path of this script
	# Source - https://stackoverflow.com/a/246128
	set_script() {
		local source_path="${BASH_SOURCE[0]}"
		local symlink_dir
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
		SCRIPT_DIR="$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)"
		readonly SCRIPT_DIR

		SCRIPT_FILE="${SCRIPT_DIR}/$(basename "$source_path")"
		readonly SCRIPT_FILE

		if [[ -z "$SCRIPT_DIR" || -z "$SCRIPT_FILE" ]]; then
			printf "%b[ FATAL ]%b Failed to resolve script paths.\n" "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" >&2
			exit 1
		fi
	}
	set_script
	unset -f set_script

	cd "$SCRIPT_DIR" || {
		printf "%b[ FATAL ]%b Failed to enter root directory: %s." "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" "$SCRIPT_DIR" >&2
		exit 1
	}
}

# OS and Runtime
{
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
	IS_ELEVATED=0
	PWSH_CMD="" # only used if TARGET_OS == OS_WINDOWS

	# Detects and sets TARGET_OS and TARGET_RUNTIME. Validates by comparing
	# against OS_UNKNOWN and RUNTIME_UNKNOWN
	# Usage: set_env
	#
	# Returns:
	#   0 if TARGET_OS and TARGET_RUNTIME are set
	#   1 if TARGET_OS and TARGET_RUNTIME remain 'unknown'
	set_env() {
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

			# archlinux vs debian
			if [[ -f "/etc/arch-release" ]]; then
				readonly TARGET_OS="${OS_ARCHLINUX}"
			elif [[ -f "/etc/debian_version" ]]; then
				readonly TARGET_OS="${OS_DEBIAN}"
			elif [[ -f "/etc/os-release" ]]; then
				if grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release; then
					readonly TARGET_OS="${OS_DEBIAN}"
				elif grep -qiE '^ID(_LIKE)?=.*arch' /etc/os-release; then
					readonly TARGET_OS="${OS_ARCHLINUX}"
				fi
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
			if [[ "$OS" == "Windows_NT" ]]; then
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
	set_env || {
		printf "%b[ FATAL ]%b Unable to detect TARGET_OS and TARGET_RUNTIME." "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" >&2
	}
	unset -f set_env

	# Detect if script was run as sudo or root.
	# Usage: check_admin
	check_admin() {
		if [[ "$EUID" -eq 0 || -n "${SUDO_USER:-}" ]]; then
			readonly IS_ELEVATED=1
		elif [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]] && net session >/dev/null 2>&1; then
			# net session fails with exit code 5 (Access Denied) if not admin
			readonly IS_ELEVATED=1
		else
			readonly IS_ELEVATED
		fi
	}
	check_admin
	unset -f check_admin

	# Determine which PowerShell binary to use and set PWSH_CMD to it
	set_pwsh_cmd() {
		if [[ "${TARGET_OS}" == "OS_WINDOWS" ]]; then
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
	set_pwsh_cmd
	unset -f set_pwsh_cmd
}

# usage, banners, large text
{
	print_banner() {
		echo ""
		printf '\n%b%s%b\n' \
			"${COLOUR["BOLD_CYAN"]}" '  ____        _    __ _ _           ' "${COLOUR["RESET"]}" \
			"${COLOUR["BOLD_CYAN"]}" ' |  _ \  ___ | |_ / _(_) | ___  ___ ' "${COLOUR["RESET"]}" \
			"${COLOUR["BOLD_CYAN"]}" ' | | | |/ _ \| __| |_| | |/ _ \/ __|' "${COLOUR["RESET"]}" \
			"${COLOUR["BOLD_CYAN"]}" ' | |_| | (_) | |_|  _| | |  __/\__ \' "${COLOUR["RESET"]}" \
			"${COLOUR["BOLD_CYAN"]}" ' |____/ \___/ \__|_| |_|_|\___||___/' "${COLOUR["RESET"]}" \
			"${COLOUR["GREY"]}" ' -----------------------------------' "${COLOUR["RESET"]}" \
			"" '   Automated Environment Setup' "" \
			"${COLOUR["GREY"]}" ' -----------------------------------' "${COLOUR["RESET"]}"

		printf '\n'
		printf '\e[90m  Target : \e[0m%s\n\e[90m  System : \e[0m%s\n\n' "$HOME" "$(uname -sm)"
	}

	print_usage() {
		print_banner

		printf "Usage: %b'bash %s [options]'%b\n\n" "${COLOUR["CYAN"]}" "$(basename "$0")" "${COLOUR["RESET"]}"
		printf "Options:\n"
		printf "  -f, --force              Overwrite existing dotfiles without prompting\n"
		printf "  -n, --dry-run            Simulate installation without making actual changes\n"
		printf "  -l, --log-level <level>  Set verbosity ('info', 'success', 'warning', 'error', 'quiet')\n"
		printf "						   (default: 'info')\n"
		printf "						   (env: DOTFILES_LOG_LEVEL)\n"
		printf "  -q, --quiet              Suppress all output except errors (same as --log-level=error)\n"
		printf "  -o, --log-file <path>    Specify a custom path for the log file\n"
		printf "						   (default: %s/tmp/install.log)\n" "${SCRIPT_DIR}"
		printf "                           (env: DOTFILES_LOG_FILE)\n"
		printf "      --no-log             Disable writing to a log file\n"
		printf "  -h, --help               Print this help message\n"
	}
}

# logging
{
	readonly LOG_LEVEL_DEBUG=0
	readonly LOG_LEVEL_INFO=1
	readonly LOG_LEVEL_SUCCESS=2
	readonly LOG_LEVEL_WARNING=3
	readonly LOG_LEVEL_ERROR=4
	readonly LOG_LEVEL_FATAL=5

	log::detail::format() {
		local -n args="$1"
		shift
		if [[ $# -gt 1 ]]; then
			local format="$1"
			shift
			# shellcheck disable=SC2059
			printf -v args "$format" "$@"
		else
			args="${1:-}"
		fi
	}

	# handles colors for terminal, plain text for file.
	log::detail::emit() {
		local level_name="$1"
		local color_code="$2"
		local stream="$3"
		local msg="$4"

		# terminal
		if [[ "$stream" -eq 2 ]]; then
			printf "%b[ %s ]%b %s\n" "$color_code" "$level_name" "${COLOUR["RESET"]}" "$msg" >&2
		else
			printf "%b[ %s ]%b %s\n" "$color_code" "$level_name" "${COLOUR["RESET"]}" "$msg"
		fi

		# file
		if [[ -n "${INSTALL_LOG_FILE:-}" ]]; then
			local ts
			ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
			printf "[%s] [ %s ] %s\n" "$ts" "$level_name" "$msg" >>"$INSTALL_LOG_FILE"
		fi
	}

	log::debug() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_DEBUG)) && return 0
		local msg
		log::detail::format msg "$@"
		log::detail::emit "DEBUG" "${COLOUR["BOLD_GREY"]}" 1 "$msg"
	}

	log::info() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_INFO)) && return 0
		local msg
		log::detail::format msg "$@"
		log::detail::emit "INFO" "${COLOUR["BOLD_BLUE"]}" 1 "$msg"
	}

	log::success() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_SUCCESS)) && return 0
		local msg
		log::detail::format msg "$@"
		log::detail::emit "SUCCESS" "${COLOUR["BOLD_GREEN"]}" 1 "$msg"
	}

	log::warning() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_WARNING)) && return 0
		local msg
		log::detail::format msg "$@"
		log::detail::emit "WARNING" "${COLOUR["BOLD_YELLOW"]}" 2 "$msg"
	}

	log::error() {
		((ACTIVE_LOG_LEVEL > LOG_LEVEL_ERROR)) && return 0
		local msg
		log::detail::format msg "$@"
		log::detail::emit "ERROR" "${COLOUR["BOLD_RED"]}" 2 "$msg"
	}

	log::fatal() {
		local msg
		log::detail::format msg "$@"
		log::detail::emit "FATAL" "${COLOUR["BOLD_RED"]}" 2 "$msg"
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
		log::detail::format msg "$@"
		msg="${msg:-Uh oh! An unspecified developer error occurred.}"

		local -r trace_msg="file: ${base_file}(${caller_line}) \`${caller_func}()\`: ${msg}"
		log::detail::emit "DEVELOPER" "${COLOUR["BOLD_RED"]}" 2 "$trace_msg"

		exit 1
	}
}

# arg parsing
{
	declare -i ACTIVE_LOG_LEVEL
	DISABLE_LOG_FILE=0
	FORCE_INSTALL=0
	DRY_RUN=0
	INSTALL_LOG_FILE="${DOTFILES_LOG_FILE:-${SCRIPT_DIR}/tmp/install.log}"
	user_log_level="${DOTFILES_LOG_LEVEL:-info}"

	# parse args
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			print_usage
			exit 0
			;;
		-f | --force)
			FORCE_INSTALL=1
			shift
			;;
		-n | --dry-run)
			DRY_RUN=1
			shift
			;;
		-q | --quiet)
			user_log_level="error"
			shift
			;;
		--no-log)
			DISABLE_LOG_FILE=1
			shift
			;;
		-o | --log-file)
			if [[ -n "${2:-}" && "$2" != -* ]]; then
				INSTALL_LOG_FILE="$2"
				shift 2
			else
				printf "%b[ ERROR ]%b Missing argument for %s\n" "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" "$1" >&2
				exit 1
			fi
			;;
		--log-file=*)
			INSTALL_LOG_FILE="${1#*=}"
			shift
			;;
		-l | --log-level)
			# --log-level warning
			if [[ -n "${2:-}" && "$2" != -* ]]; then
				user_log_level="$2"
				shift 2
			else
				printf "%b[ ERROR ]%b Missing argument for %s\n" "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" "$1" >&2
				exit 1
			fi
			;;
		--log-level=*)
			# --log-level=warning
			user_log_level="${1#*=}"
			shift
			;;
		*)
			printf "%b[ ERROR ]%b Invalid parameter: %s\n" "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" "$1"
			printf "Run %b'bash %s --help'%b for valid options.\n" "${COLOUR["CYAN"]}" "$(basename "$0")" "${COLOUR["RESET"]}" >&2 >&2
			exit 1
			;;
		esac
	done

	readonly FORCE_INSTALL
	readonly DRY_RUN

	case "${user_log_level,,}" in
	debug | 0) ACTIVE_LOG_LEVEL=${LOG_LEVEL_DEBUG} ;;
	info | 1) ACTIVE_LOG_LEVEL=${LOG_LEVEL_INFO} ;;
	success | 2) ACTIVE_LOG_LEVEL=${LOG_LEVEL_SUCCESS} ;;
	warn | warning | 3) ACTIVE_LOG_LEVEL=${LOG_LEVEL_WARNING} ;;
	err | error | 4) ACTIVE_LOG_LEVEL=${LOG_LEVEL_ERROR} ;;
	fatal | quiet | silent | 5) ACTIVE_LOG_LEVEL=${LOG_LEVEL_FATAL} ;;
	*)
		printf "Invalid log level '%s'. Defaulting to INFO.\n" "${user_log_level}" >&2
		ACTIVE_LOG_LEVEL=${LOG_LEVEL_INFO}
		;;
	esac
	unset -v user_log_level
	readonly ACTIVE_LOG_LEVEL

	if [[ -n "${INSTALL_LOG_FILE:-}" ]]; then
		mkdir -p "$(dirname "$INSTALL_LOG_FILE")"
		: >"$INSTALL_LOG_FILE"
		readonly INSTALL_LOG_FILE

		log::debug "Log file initialized at: %s" "$INSTALL_LOG_FILE"
	else
		readonly INSTALL_LOG_FILE
		log::debug "File logging disabled via parameter."
	fi
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
	# Prompts the user to continue.
	# Exits the script if the user chooses No (n/N).
	# Usage: prompt_continue
	#
	# Arguments:
	#   $1 (format) : (Optional) The warning message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	prompt_continue() {
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
				"${COLOUR["BOLD_YELLOW"]}" "${COLOUR["RESET"]}" \
				"${COLOUR["BOLD_WHITE"]}" "${COLOUR["RESET"]}" >&2

			read -r choice

			case "$choice" in
			[yY])
				return 0
				;;
			[nN])
				log::dev_fatal "Aborting installation!"
				;;
			*)
				printf "%bInvalid input. Please enter y or n.%b\n" "${COLOUR["RED"]}" "${COLOUR["RESET"]}" >&2
				;;
			esac
		done
	}
}

# windows
{
	# Executes PowerShell handoff and exits the bash script.
	# Never returns to the caller if successful (exits with PowerShell's exit code).
	windows_handoff() {
		local ps_script="$SCRIPT_DIR/install.ps1"
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
		*)
			;;
		esac
	fi
	unset -f prompt_windows_handoff windows_handoff
}

# required paths for installation
{
	# base directory constants
	readonly LIB_DIR="${SCRIPT_DIR}/lib"
	readonly OS_DIR="${SCRIPT_DIR}/os"
	readonly RUNTIME_DIR="${SCRIPT_DIR}/runtime"
	readonly SHELL_DIR="${SCRIPT_DIR}/shells"
	readonly APP_DIR="${SCRIPT_DIR}/apps"

	# paths
	{
		# dev
		declare -r -a dev_files=(
			"${SCRIPT_DIR}/mode.sh"
			"${SCRIPT_DIR}/usage.sh"
		)
		# lib
		declare -r -a lib_files=(
			"${LIB_DIR}/banner.sh"
			"${LIB_DIR}/bootstrap.sh"
			"${LIB_DIR}/common.sh"
			"${LIB_DIR}/log.sh"
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
			local log::error

			printf -v log::error "Missing %d path(s):" "${#missing_paths[@]}"
			for missing in "${missing_paths[@]}"; do
				printf -v log::error "%s\n  %b✗%b %s" "$log::error" "${COLOUR["BOLD_RED"]}" "${COLOUR["RESET"]}" "${missing}"
			done

			log::dev_fatal "%s" "$log::error"
		fi

		return 0
	}
	check_exists "${files_to_check[@]}"
	unset -f check_exists
}

###################
# print banner
source_file "${LIB_DIR}/banner.sh"
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
source "$SCRIPT_DIR/usage.sh" "$(basename "$0")" "$@" || exit 1
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
