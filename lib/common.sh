#!/usr/bin/env bash

if [[ -n "${__COMMON_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __COMMON_SH_INCLUDED__=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "log.sh" || exit 1

# constants
{
	readonly INVALID_TOKEN="fiseb39293t23g"
} # constants

# common
{
	# Enforces argument count constraints for functions.
	# Usage: assert_args <func_name> <count> <min> [max]
	#
	# Arguments:
	#   $1 (func_name) : The name of the function being checked.
	#   $2 (count)     : The actual number of arguments passed to that function (usually $#).
	#   $3 (min)       : The minimum number of arguments required.
	#   $4 (max)       : (Optional) The maximum number of arguments allowed. Defaults to $3 (min).
	#
	# Returns:
	#   0 on success (argument count is within valid bounds).
	#   2 on failure (argument count mismatch or invalid configuration).
	common::assert_args() {
		local -r func_name="$1"
		local -r count="$2"
		local -r min="$3"
		local -r max="${4:-$3}"

		local err_msg="${COLOUR_CYAN}${func_name}()${COLOUR_RESET} "

		# check min and max non-negative integers
		if [[ ! "$min" =~ ^[0-9]+$ ]] || [[ ! "$max" =~ ^[0-9]+$ ]]; then
			err_msg+="configuration error! Min and max bounds must be non-negative integers (got min: '${min}', max: '${max}')."
		elif ((min > max)); then
			# developer error
			err_msg+="configuration error! Min arguments (${COLOUR_YELLOW}${min}${COLOUR_RESET}) cannot be greater than max arguments (${COLOUR_YELLOW}${max}${COLOUR_RESET})."
		elif ((count < min || count > max)); then
			# argument mismatch
			err_msg+="requires "
			if ((min == max)); then
				err_msg+="exactly ${COLOUR_YELLOW}${min}${COLOUR_RESET} argument(s)"
			else
				err_msg+="between ${COLOUR_YELLOW}${min}${COLOUR_RESET} and ${COLOUR_YELLOW}${max}${COLOUR_RESET} argument(s)"
			fi

			err_msg+=", but received ${COLOUR_YELLOW}${count}${COLOUR_RESET}."
		else
			# valid
			return 0
		fi

		log::error "$err_msg" 2
		return 2
	}

	# Prompts the user to continue.
	# Exits the script if the user chooses No (n/N).
	# Usage: common::prompt_continue
	common::prompt_continue() {
		common::assert_args "common::find_program" $# 0 || return $?

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
} # common
