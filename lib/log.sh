#!/usr/bin/env bash

if [[ -n "${__LOG_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __LOG_SH_INCLUDED__=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

# source_deps """ || exit 1

{
	#FIXME: also defined in install
	# Ansi-256 Colours
	readonly COLOUR_RESET="\e[0m"
	readonly COLOUR_GREY="\e[38;5;8m"
	readonly COLOUR_RED="\e[38;5;9m"
	readonly COLOUR_GREEN="\e[38;5;10m"
	readonly COLOUR_YELLOW="\e[38;5;11m"
	readonly COLOUR_BLUE="\e[38;5;12m"
	readonly COLOUR_MAGENTA="\e[38;5;13m"
	readonly COLOUR_CYAN="\e[38;5;14m"
	readonly COLOUR_WHITE="\e[38;5;15m"
	readonly COLOUR_BLACK="\e[38;5;0m"
}

{
	# Output error message in red
	# Usage: log::error [-l stack_level] <message_or_format> [args...]
	#
	# Options:
	#   -l <level> : (Optional) The call stack depth to extract the source location from. Defaults to 1.
	#
	# Arguments:
	#   $1 (format) : The error message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	log::error() {
		local -i level=1

		if [[ "$1" == "-l" ]]; then
			level="$2"
			shift 2
		fi

		local -i line_level=$((level - 1))
		local -r caller_file="${BASH_SOURCE[$level]:-Unknown}"
		local -r caller_line="${BASH_LINENO[$line_level]:-Unknown}"
		local -r src_loc="[${caller_file}:${caller_line}]"

		local message
		if [[ $# -gt 1 ]]; then
			# shellcheck disable=SC2059
			printf -v message "$@"
		else
			message="$1"
		fi

		printf "%b\n" "${COLOUR_RED}[ERROR]${COLOUR_RESET}: ${src_loc} ${message}" >&2
	}

	# Output warning message in yellow
	# Usage: log::warning [-l stack_level] <message_or_format> [args...]
	#
	# Options:
	#   -l <level> : (Optional) The call stack depth to extract the source location from. Defaults to 1.
	#
	# Arguments:
	#   $1 (format) : The warning message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	log::warning() {
		local -i level=1

		if [[ "$1" == "-l" ]]; then
			level="$2"
			shift 2
		fi

		local -i line_level=$((level - 1))
		local -r caller_file="${BASH_SOURCE[$level]:-Unknown}"
		local -r caller_line="${BASH_LINENO[$line_level]:-Unknown}"
		local -r src_loc="[${caller_file}:${caller_line}] "

		local message
		if [[ $# -gt 1 ]]; then
			printf -v message "$@"
		else
			message="$1"
		fi

		printf "%b\n" "${COLOUR_YELLOW}[WARNING]${COLOUR_RESET}: ${src_loc}${message}" >&2
	}

	# Output informational message in cyan
	# Usage: log::info <message_or_format> [args...]
	#
	# Arguments:
	#   $1 (format) : The info message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	log::info() {
		local message

		if [[ $# -gt 1 ]]; then
			printf -v message "$@"
		else
			message="$1"
		fi

		printf "%b\n" "${COLOUR_CYAN}[INFO]${COLOUR_RESET}: ${message}"
	}

	# Output success message in green
	# Usage: log::success <message_or_format> [args...]
	#
	# Arguments:
	#   $1 (format) : The success message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	log::success() {
		local message

		if [[ $# -gt 1 ]]; then
			printf -v message "$@"
		else
			message="$1"
		fi

		printf "%b\n" "${COLOUR_GREEN}[SUCCESS]${COLOUR_RESET}: ${message}"
	}

	# Prints a major phase header
	# Usage: log::step <message_or_format> [args...]
	#
	# Arguments:
	#   $1 (format) : The step message, or a printf-style format string.
	#   $@ (args)   : (Optional) Arguments to populate the format string.
	log::step() {
		local message

		if [[ $# -gt 1 ]]; then
			printf -v message "$@"
		else
			message="$1"
		fi

		printf '\n\e[1;35m==>\e[0m \e[1;37m%s\e[0m\n' "${message}"
	}
}
