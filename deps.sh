#!/usr/bin/env bash
# deps.sh

####################
if [[ -n "${__DEPS_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __DEPS_SH_INCLUDED__=1
####################
# constants
{
	declare -r MANAGER_PACMAN=(sudo pacman -S --needed)
	declare -r MANAGER_YAY=(yay -S --needed)

	declare -r MANAGER_BREW=(brew install)
	declare -r MANAGER_BREW_CASK=(brew install --cask)
	declare -r MANAGER_MACPORT=(sudo port install)

	declare -r MANAGER_SCOOP=(scoop install)
	declare -r MANAGER_WINGET=(winget install --exact --accept-source-agreements --id)
	# first success wins
	declare -r MANAGERS_ARCH=(pacman yay)
	declare -r MANAGERS_MAC=(brew port)
	declare -r MANAGERS_WINDOWS=(scoop winget yay)

	SCOOP_DIR="${SCOOP:-${HOME}/opt/scoop}"
}
DEPS_ACTIVE_MANAGERS=()

ACTIVE_PACKAGES=(
	"eza"
	# arch openssh  systemctl --user enable --now ssh-agent.service
)
CASK_PACKAGES=()

# current command sets used by dotfiles::install_package()
DEPS_DEFAULT_CMD=()
DEPS_FALLBACK_CMD=()

# util
{
	dotfiles::require_host_functions() {
		local -a required=(
			"dotfiles::println"
			"dotfiles::prompt_continue"
			"dotfiles::is_true"
		)
		local fn

		for fn in "${required[@]}"; do
			if ! command -v "${fn}" >/dev/null 2>&1; then
				printf 'Error: %s is not defined. deps.sh must be sourced by install.sh.\n' "${fn}" >&2
				return 1
			fi
		done

		return 0
	}

	dotfiles::has_command() {
		[[ $# -gt 0 ]] || return 1
		command -v "$1" >/dev/null 2>&1
	}
}

# Returns the command array for a given manager name.
# Sets DEPS_RESOLVED_CMD (local to caller) and returns 0/1.
dotfiles::resolve_manager_cmd() {
	local -r name="${1:-}"

	case "${name}" in
	pacman) DEPS_RESOLVED_CMD=("${MANAGER_PACMAN[@]}") ;;
	yay) DEPS_RESOLVED_CMD=("${MANAGER_YAY[@]}") ;;
	brew) DEPS_RESOLVED_CMD=("${MANAGER_BREW[@]}") ;;
	port) DEPS_RESOLVED_CMD=("${MANAGER_PORT[@]}") ;;
	scoop) DEPS_RESOLVED_CMD=("${MANAGER_SCOOP[@]}") ;;
	winget) DEPS_RESOLVED_CMD=("${MANAGER_WINGET[@]}") ;;
	*) return 1 ;;
	esac
	return 0
}

dotfiles::set_pkg_managers() {
	case "${TARGET_OS:-}" in
	"${OS_CACHYOS}" | "${OS_ARCHLINUX}") DEPS_ACTIVE_MANAGERS=("${MANAGERS_ARCH[@]}") ;;
	"${OS_MAC}") DEPS_ACTIVE_MANAGERS=("${MANAGERS_MAC[@]}") ;;
	"${OS_WINDOWS}") DEPS_ACTIVE_MANAGERS=("${MANAGERS_WINDOWS[@]}") ;;
	*) return 1 ;;
	esac
	return 0
}
# internal helpers
{
	dotfiles::detail::display_name() {
		local -r cmd="${1:-}"
		case "${cmd}" in
		brew) printf 'Homebrew' ;;
		yay) printf 'yay' ;;
		scoop) printf 'Scoop' ;;
		winget) printf 'winget' ;;
		port) printf 'MacPorts' ;;
		pacman) printf 'pacman' ;;
		*) printf '%s' "${cmd}" ;; # identity fallback
		esac
	}

	# Handles the common "is it there? / dry-run / prerequisites" gate.
	#
	# Usage: dotfiles::detail::bootstrap_gate <cmd> [prereq_cmd ...]
	#
	# Returns:
	#   0  – tool already present (nothing to do)
	#   0  – dry-run (would install, but we're done)
	#   1  – prerequisites missing (caller should abort)
	#   2  – tool missing, caller should proceed with install
	dotfiles::detail::bootstrap_gate() {
		local -r cmd="${1:-}"
		shift || true

		local display
		display="$(dotfiles::detail::display_name "${cmd}")"

		# already installed
		if dotfiles::has_command "${cmd}"; then
			return 0
		fi

		dotfiles::println '  [bootstrap] %s not found.' "${display}"

		if ((DRY_RUN)); then
			dotfiles::println '  [bootstrap] [dry-run] Would install %s.' "${display}"
			return 0
		fi

		# check prerequisites
		local prereq
		for prereq in "$@"; do
			if ! dotfiles::has_command "${prereq}"; then
				dotfiles::println 'Error: %s is required to install %s.' "${prereq}" "${display}" >&2
				return 1
			fi
		done

		dotfiles::println '  [bootstrap] Installing %s.' "${display}"
		return 2
	}
}

dotfiles::bootstrap_yay() {
	:
}
dotfiles::bootstrap_brew() {
	:
}
dotfiles::bootstrap_pwsh() {
	:
}
dotfiles::bootstrap_scoop() {
	local display
	display="$(dotfiles::detail::display_name scoop)"

	if dotfiles::has_command scoop; then
		return 0
	fi

	dotfiles::println '  [bootstrap] %s not found.' "${display}"

	if ((DRY_RUN)); then
		dotfiles::println '  [bootstrap] [dry-run] Would install %s to %s' "${display}" "${SCOOP_DIR}"
		return 0
	fi

	dotfiles::set_pwsh_cmd
	if [[ -z "${PWSH_CMD:-}" ]]; then
		dotfiles::println 'Error: Cannot locate pwsh.exe.' >&2
		return 1
	fi

	dotfiles::println '  [bootstrap] Installing %s to %s' "${display}" "${SCOOP_DIR}"

	# Convert $HOME (unix-style /c/Users/foo) to a Windows path (C:\Users\foo)
	# so PowerShell gets a valid absolute path.
	local win_scoop_dir
	if command -v cygpath >/dev/null 2>&1; then
		win_scoop_dir="$(cygpath -w "${SCOOP_DIR}")"
	elif command -v wslpath >/dev/null 2>&1; then
		win_scoop_dir="$(wslpath -w "${SCOOP_DIR}")"
	else
		# MSYS2/Git Bash: $HOME is already like /c/Users/foo
		# PowerShell understands /c/Users/foo in most contexts,
		# but let's be safe and convert.
		win_scoop_dir="${SCOOP_DIR}"
	fi

	local tmp_ps
	tmp_ps="$(mktemp "${TMPDIR:-/tmp}/scoop_install.XXXXXX.ps1")"
	trap 'rm -f "${tmp_ps}" 2>/dev/null' RETURN

	# Convert temp file path to Windows form for the PS side
	local tmp_ps_win
	if command -v cygpath >/dev/null 2>&1; then
		tmp_ps_win="$(cygpath -w "${tmp_ps}")"
	elif command -v wslpath >/dev/null 2>&1; then
		tmp_ps_win="$(wslpath -w "${tmp_ps}")"
	else
		tmp_ps_win="${tmp_ps}"
	fi

	# Step 1: download the installer to a known location
	if ! "${PWSH_CMD}" -NoProfile -ExecutionPolicy Bypass -Command \
		"irm https://get.scoop.sh -outfile '${tmp_ps_win}'"; then
		dotfiles::println 'Error: Failed to download Scoop installer.' >&2
		return 1
	fi

	# Step 2: run it with explicit parameters
	if ! "${PWSH_CMD}" -NoProfile -ExecutionPolicy Bypass -Command \
		"Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; & '${tmp_ps_win}' -ScoopDir '${win_scoop_dir}'"; then
		dotfiles::println 'Error: Scoop installation failed.' >&2
		return 1
	fi

	rm -f "${tmp_ps}" 2>/dev/null || true

	# Post-install: add shims to current bash PATH
	local shims_dir="${SCOOP_DIR}/shims"
	if [[ -d "${shims_dir}" ]] && [[ ":${PATH}:" != *":${shims_dir}:"* ]]; then
		export PATH="${shims_dir}:${PATH}"
	fi

	return 0
}

dotfiles::bootstrap_managers() {
	local -a noconfirm_arg=()
	local -a noconfirm_env=()

	if [[ "${NO_CONFIRM:-0}" -eq 1 ]]; then
		case "${TARGET_OS}" in
		"${OS_CACHYOS}" | "${OS_ARCHLINUX}")
			noconfirm_arg=(--noconfirm)
			;;
		"${OS_MAC}")
			noconfirm_env=(NONINTERACTIVE=1)
			;;
		*)
			return 0
			;;
		esac
	fi

	if [[ "${TARGET_OS}" == "${OS_MAC}" ]]; then
		if ! dotfiles::has_command brew; then
			dotfiles::println '  [bootstrap] Homebrew not found.'

			if ((DRY_RUN)); then
				dotfiles::println '  [bootstrap] [dry-run] Would install Homebrew.'
				return 0
			fi

			if ! dotfiles::has_command curl; then
				dotfiles::println 'Error: curl is required to install Homebrew.' >&2
				return 1
			fi

			dotfiles::println '  [bootstrap] Installing Homebrew.'

			if ! homebrew_script="$(command curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh 2>/dev/null)"; then
				dotfiles::println 'Error: Failed to download Homebrew installer.' >&2
				return 1
			fi

			if [[ -z "${homebrew_script}" ]]; then
				dotfiles::println 'Error: Downloaded Homebrew installer is empty.' >&2
				return 1
			fi

			if [[ ${#noconfirm_env[@]} -gt 0 ]]; then
				if ! command env "${noconfirm_env[@]}" /bin/bash -c "${homebrew_script}"; then
					dotfiles::println 'Error: Homebrew installation failed.' >&2
					return 1
				fi
			else
				if ! /bin/bash -c "${homebrew_script}"; then
					dotfiles::println 'Error: Homebrew installation failed.' >&2
					return 1
				fi
			fi

			if [[ -x /opt/homebrew/bin/brew ]]; then
				if shellenv="$(command /opt/homebrew/bin/brew shellenv 2>/dev/null)"; then
					if [[ -n "${shellenv}" ]]; then
						eval "${shellenv}"
					fi
				else
					dotfiles::println 'Warning: Unable to load Homebrew shell environment.' >&2
				fi
			elif [[ -x /usr/local/bin/brew ]]; then
				if shellenv="$(command /usr/local/bin/brew shellenv 2>/dev/null)"; then
					if [[ -n "${shellenv}" ]]; then
						eval "${shellenv}"
					fi
				else
					dotfiles::println 'Warning: Unable to load Homebrew shell environment.' >&2
				fi
			else
				dotfiles::println 'Warning: Homebrew installation finished, but brew was not found in standard locations.' >&2
			fi
		fi
	elif [[ "${TARGET_OS}" == "${OS_CACHYOS}" || "${TARGET_OS}" == "${OS_ARCHLINUX}" ]]; then
		if ! dotfiles::has_command yay; then
			dotfiles::println '  [bootstrap] yay not found.'

			if ((DRY_RUN)); then
				dotfiles::println '  [bootstrap] [dry-run] Would install yay.'
				return 0
			fi

			if ! dotfiles::has_command sudo || ! dotfiles::has_command git; then
				dotfiles::println 'Error: sudo and git are required to bootstrap yay.' >&2
				return 1
			fi

			dotfiles::println '  [bootstrap] Installing yay.'

			pacman_cmd=(sudo pacman -S --needed)
			if [[ ${#noconfirm_args[@]} -gt 0 ]]; then
				pacman_cmd+=("${noconfirm_args[@]}")
			fi

			if ! command "${pacman_cmd[@]}" git base-devel; then
				dotfiles::println 'Error: Failed to install base packages required for yay.' >&2
				return 1
			fi

			if ! dotfiles::has_command makepkg; then
				dotfiles::println 'Error: makepkg is required to build yay.' >&2
				return 1
			fi

			if ! yay_dir="$(mktemp -d)"; then
				dotfiles::println 'Error: Unable to create temporary directory for yay.' >&2
				return 1
			fi

			if ! command git clone --depth=1 https://aur.archlinux.org/yay.git "${yay_dir}"; then
				dotfiles::println 'Error: Failed to clone yay.' >&2
				rm -rf "${yay_dir}" 2>/dev/null || true
				return 1
			fi

			makepkg_cmd=(makepkg -si)
			if [[ ${#noconfirm_args[@]} -gt 0 ]]; then
				makepkg_cmd+=("${noconfirm_args[@]}")
			fi

			if ! (cd "${yay_dir}" && command "${makepkg_cmd[@]}"); then
				dotfiles::println 'Error: Failed to build and install yay.' >&2
				rm -rf "${yay_dir}" 2>/dev/null || true
				return 1
			fi

			rm -rf "${yay_dir}" 2>/dev/null || true
		fi
	elif [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
		if ! dotfiles::has_command scoop && ! dotfiles::has_command winget; then
			dotfiles::println '  [bootstrap] Neither scoop nor winget found.'

			if ((DRY_RUN)); then
				dotfiles::println '  [bootstrap] [dry-run] Would require scoop or winget.'
				return 0
			fi

			dotfiles::println 'Error: Install scoop or enable winget before installing packages.' >&2
			return 1
		fi
	fi

	return 0
}

# Runs a package install command.
#
# Returns:
#   0 on success
#   1 if no command was supplied
#   2 if the command binary is missing
#   3 if the command ran but failed
dotfiles::run_package_command() {
	local -r pkg="${1:-}"

	if [[ -z "${pkg}" ]]; then
		dotfiles::println 'Error: run_package_command called without a package name.' >&2
		return 1
	fi

	shift

	if [[ $# -eq 0 ]]; then
		dotfiles::println 'Error: No package command supplied for %s.' "${pkg}" >&2
		return 1
	fi

	local -a cmd=("$@")

	if ! dotfiles::has_command "${cmd[0]}"; then
		if ((DRY_RUN)); then
			dotfiles::println '      [dry-run] Would attempt: %s (command not found: %s)' "${cmd[*]} ${pkg}" "${cmd[0]}"
			return 0
		fi
		return 2
	fi

	dotfiles::println '      $ %s' "${cmd[*]} ${pkg}"

	if ((DRY_RUN)); then
		return 0
	fi

	if command "${cmd[@]}" "${pkg}"; then
		return 0
	fi

	return 3
}

dotfiles::install_package() {
	local -r pkg="${1:-}"
	local manager
	local rc=255

	if [[ -z "${pkg}" ]]; then
		dotfiles::println 'Error: install_package called without a package name.' >&2
		return 1
	fi

	if [[ ${#DEPS_ACTIVE_MANAGERS[@]} -eq 0 ]]; then
		dotfiles::println 'Warning: No package managers configured. Skipping %s.' "${pkg}" >&2
		return 0
	fi

	for manager in "${DEPS_ACTIVE_MANAGERS[@]}"; do
		if ! dotfiles::resolve_manager_cmd "${manager}"; then
			continue
		fi

		rc=255
		dotfiles::run_package_command "${pkg}" "${DEPS_RESOLVED_CMD[@]}" || rc=$?

		case "${rc}" in
		0)
			dotfiles::println '      [ok] %s (%s)' "${pkg}" "${manager}"
			return 0
			;;
		2)
			# binary not found → try next manager
			dotfiles::println '      [skip] %s: %s not installed, trying next.' "${pkg}" "${manager}"
			;;
		3)
			# ran but failed → try next manager (package may be in a different source)
			dotfiles::println '      [skip] %s: %s failed, trying next.' "${pkg}" "${manager}"
			;;
		esac
	done

	dotfiles::println 'Error: No manager could install %s.' "${pkg}" >&2
	return 1
}

dotfiles::install_packages() {
	if ! dotfiles::deps::require_host_functions; then
		return 1
	fi

	dotfiles::set_pkg_install_cmds || {
		dotfiles::println "Unknown target OS, skipping package installation."
		return 0
	}

	if ((NO_DEPS)); then
		dotfiles::println '=> Skipping package installation (--no-deps).'
		return 0
	fi

	dotfiles::println '=== Starting package installation ==='

	if ! dotfiles::bootstrap_managers; then
		if ((NOCONFIRM)); then
			dotfiles::println 'Error: Package manager bootstrap failed.' >&2
			return 1
		fi

		dotfiles::prompt_continue 'Package manager bootstrap failed!'
		return 1
	fi

	local total=0
	local pkg
	local rc=0

	total=$((total + ${#ACTIVE_PACKAGES[@]} + ${#FALLBACK_PACKAGES[@]}))

	if [[ "${TARGET_OS}" == "${OS_MAC}" ]]; then
		total=$((total + ${#CASK_PACKAGES[@]}))
	fi

	if [[ ${total} -eq 0 ]]; then
		dotfiles::println '  [packages] No packages configured. Nothing to do.'
		return 0
	fi

	dotfiles::println '=> Installing %d package(s)' "${total}"

	if [[ ${#ACTIVE_PACKAGES[@]} -gt 0 ]]; then
		for pkg in "${ACTIVE_PACKAGES[@]}"; do
			dotfiles::println '  [packages] %s' "${pkg}"
			dotfiles::install_package "${pkg}" || rc=1
		done
	fi

	if [[ ${#FALLBACK_PACKAGES[@]} -gt 0 ]]; then
		for pkg in "${FALLBACK_PACKAGES[@]}"; do
			dotfiles::println '  [packages] %s' "${pkg}"
			dotfiles::install_package "${pkg}" || rc=1
		done
	fi

	if [[ "${TARGET_OS}" == "${OS_MAC}" ]] && [[ ${#CASK_PACKAGES[@]} -gt 0 ]]; then
		DEPS_DEFAULT_CMD=("${MANAGER_BREW_CASK[@]}")
		DEPS_FALLBACK_CMD=()

		for pkg in "${CASK_PACKAGES[@]}"; do
			dotfiles::println '  [cask] %s' "${pkg}"
			dotfiles::install_package "${pkg}" || rc=1
		done

		DEPS_DEFAULT_CMD=("${MANAGER_BREW[@]}")
		DEPS_FALLBACK_CMD=("${MANAGER_MACPORT[@]}")
	fi

	if [[ ${rc} -ne 0 ]]; then
		dotfiles::println '=> Package installation finished with errors!' >&2
		return 1
	fi

	dotfiles::println '=== Package installation complete ==='
	return 0
}
