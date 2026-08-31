#!/usr/bin/env bash
# windows.sh

###################
if [[ -n "${__WINDOWS_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __WINDOWS_SH_INCLUDED__=1
####################
{
	# detect if windows user has sudo enabled
	dotfiles::set_windows_sudo() {
		[[ -n "${WINDOWS_SUDO:-}" ]] && return 0

		command -v sudo >/dev/null 2>&1 || return 1
		command -v reg.exe >/dev/null 2>&1 || return 1 # NOTE: redundant?

		local sudo_reg
		sudo_reg=$(MSYS_NO_PATHCONV=1 reg.exe query "${WINDOWS_SUDO_REG_LOC}" /v Enabled 2>/dev/null)
		# output of 0x1, 0x2, or 0x3 means enabled
		if [[ "${sudo_reg}" =~ 0x[1-3] ]]; then
			readonly WINDOWS_SUDO=0
		else
			readonly WINDOWS_SUDO=1
		fi
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

		#if [[ ${IS_ELEVATED} -eq 1 ]]; then
		#	ps_args+=("-IsElevated")
		#fi

		local pwsh_name="${PWSH_CMD##*/}"
		pwsh_name="${pwsh_name%.exe}"

		echo
		dotfiles::println '=> Handing off execution to %s...' "${pwsh_name}"
		echo

		# adding exec makes it auto close
		"${PWSH_CMD}" "${ps_args[@]}"

		echo
		read -n 1 -s -r -p "Press any key to exit..."
		exit 0
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

		dotfiles::println 'Certain functionality may be missing or altered (e.g. instead of symlinking, files get copied).' >&2
		if dotfiles::is_true "${WINDOWS_SUDO}"; then
			dotfiles::println '   Tip: Re-run this script using `sudo` to enable native symlinks.' >&2
		else
			dotfiles::println '   Tip: Enable Windows Developer Mode or Windows Sudo to allow native symlinks.' >&2
		fi

		echo
		local choice
		while true; do
			if ! read -r -p $'Switch to the native PowerShell installer (install.ps1)? [Y/n/(q)]: ' choice; then
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
