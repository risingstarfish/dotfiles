#!/usr/bin/env bash
# user_env.sh

####################
if [[ -n "${__USER_ENV_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __USER_ENV_SH_INCLUDED__=1
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

	dotfiles::set_shell_dir() {
		[[ -n "${SHELL_DIR:-}" ]] && return 0
		readonly SHELL_DIR="${SRC_PATH}/shells"
	}

	dotfiles::set_app_dir() {
		[[ -n "${APP_DIR:-}" ]] && return 0
		readonly APP_DIR="${SRC_PATH}/apps"
	}

	dotfiles::set_github_ref() {
		[[ -n "${DOTFILES_INSTALL_REF:-}" ]] && return 0

		DOTFILES_INSTALL_REF="$(command git -C "${SRC_PATH}" config --local dotfiles.ref 2>/dev/null)"
		readonly DOTFILES_INSTALL_REF="${DOTFILES_INSTALL_REF:-main}"
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
				readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
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
	# Usage: set_elevated
	dotfiles::set_elevated() {
		[[ -n "${IS_ELEVATED:-}" ]] && return 0

		if [[ "${EUID}" -eq 0 || -n "${SUDO_USER:-}" ]]; then
			readonly IS_ELEVATED=1
		elif [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]] && net session >/dev/null 2>&1; then
			# net session fails with exit code 5 if not admin
			readonly IS_ELEVATED=1
		else
			readonly IS_ELEVATED=0
		fi
	}

	dotfiles::set_available_modules() {
		[[ -n "${AVAILABLE_MODULES:-}" ]] && return 0
		# order matters for help message
		AVAILABLE_MODULES=(
			# shells
			"shells/zsh"
			"shells/bash"
			# apps
			"apps/git"
			"apps/ssh"
			"apps/curl"
			"apps/wget"
			#"apps/oh-my-posh"
			"apps/shellcheck"
			#apps/fastfetch
			#"apps/tmux"
		)

		#if [[ "$TARGET_OS" == "${OS_MAC}" ]]; then
		#	AVAILABLE_MODULES+=("apps/iterm2")
		#fi

		readonly AVAILABLE_MODULES
	}
}
