#!/usr/bin/env bash
# package.sh

####################
if [[ -n "${__DEPS_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __DEPS_SH_INCLUDED__=1
####################
# constants
{
	declare -r MANAGER_CACHYOS_DEFAULT="sudo pacman -S --needed" #--noconfirm --force based on cli flags
	declare -r MANAGER_CACHYOS_YAY="yay -S --needed"
	declare -r MANAGER_MAC_DEFAULT="brew install"
	declare -r MANAGER_MAC_CASK="brew install --cask"
	declare -r MANAGER_WIN_SCOOP="scoop install"
	declare -r MANAGER_WIN_WINGET="winget install --exact --accept-source-agreements --id"
}

dotfiles::install_packages() {
	dotfiles::println '=== Starting package installation ==='
	local os_name=""

	case "${TARGET_OS:-}" in
	# information
	cachyos)
		os_name='CachyOS'
		;;
	archlinux)
		os_name='Arch Linux'
		;;
	windows)
		os_name='Windows'
		;;
	mac)
		os_name='macOS'
		;;
	*)
		dotfiles::println "Unknown target OS, skipping package installation."
		return 0
		;;
	esac

	dotfiles::println '=> Installing %s %s package(s' "TODO: print number" "${os_name}"

	dotfiles::println '=== Install complete ==='
}
