#!/usr/bin/env bash
# package.sh

set -euo pipefail
####################
if [[ -n "${__PACKAGE_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __PACKAGE_SH_INCLUDED__=1
####################
# constants
{
	readonly MANAGER_ARCHLINUX_DEFAULT="sudo pacman -S --needed" #--noconfirm based on cli flags
	readonly MANAGER_ARCHLINUX_YAY="yay -S --needed"             #--noconfirm based on cli flags
	readonly MANAGER_MAC_DEFAULT="brew install"
	readonly MANAGER_MAC_CASK="brew install --cask"
	readonly MANAGER_WIN_WINGET="winget install --exact --accept-source-agreements --id"
	readonly MANAGER_WIN_SCOOP="scoop install"
}

dotfiles::bootstrap_managers() {
	local noconfirm_flag=""
	if [[ "${NO_CONFIRM:-0}" -eq 1 ]]; then
		if [[ "${TARGET_OS}" == "${OS_MAC}" ]]; then
			noconfirm_flag="NONINTERACTIVE=1"
		elif [[ "${TARGET_OS}" == "${OS_ARCHLINUX}" ]]; then
			noconfirm_flag="--noconfirm"
		fi
	fi

	if [[ "${TARGET_OS}" == "${OS_MAC}" ]]; then
		if ! command -v brew >/dev/null 2>&1; then
			dotfiles::println "=> Installing Homebrew"
			"${noconfirm_flag}" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
			# load into current session
			[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
			[[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
		fi

	elif [[ "${TARGET_OS}" == "${OS_ARCHLINUX}" ]]; then
		if ! command -v yay >/dev/null 2>&1; then
			dotfiles::println "=> Installing yay"
			sudo pacman -S --needed "${noconfirm_flag}" git base-devel
			git clone https://aur.archlinux.org/yay.git /tmp/yay
			(cd /tmp/yay && makepkg -si "${noconfirm_flag}")
			rm -rf /tmp/yay
		fi
	fi
}



dotfiles::install_packages() {

	if [[ "${TARGET_OS}" == "${OS_ARCHLINUX}" ]]; then

		dotfiles::println "=> Installing %s Arch Linux package(s)..." "TODO: print number"

	elif [[ "${TARGET_OS}" == "${OS_MAC}" ]]; then

		dotfiles::println "=> Installing %s macOS package(s)..." "TODO: print number"

	elif [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then

		dotfiles::println "=> Installing %s Windows package(s)..." "TODO: print number"

	else
		dotfiles::println "Unknown target OS, skipping package installation."
		return 0
	fi
}
