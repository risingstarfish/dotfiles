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

	readonly REPO_URL="https://github.com/risingstarfish/dotfiles.git"
	#  user defined  env
	readonly DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-${HOME}/.config/dotfiles/logs}"
	readonly DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-${HOME}/.cache/dotfiles}"
	readonly DOTFILES_LOCAL_MODS="${DOTFILES_LOCAL_MODS:-0}"
	# environment
	readonly OS_ARCHLINUX="archlinux"
	readonly OS_CACHYOS="cachyos"
	readonly OS_DEBIAN="debian"
	readonly OS_MAC="mac"
	readonly OS_WINDOWS="windows"
	readonly OS_UNKNOWN="unknown"

	readonly RUNTIME_NATIVE="native"
	readonly RUNTIME_WSL="wsl"
	readonly RUNTIME_MSYS="msys"
	readonly RUNTIME_GITBASH="gitbash"
	readonly RUNTIME_UNKNOWN="unknown"

	readonly WINDOWS_SUDO_REG_LOC='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'
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
####################
dotfiles::bash_version_check() {
	if [[ -z "${BASH_VERSION:-}" || -n "${ZSH_VERSION:-}" ]]; then
		dotfiles::println 'Error: the install instructions explicitly say to use the install script with bash; please follow them.' >&2
		return 1
	fi
	# script requires bash >=4.0
	if ((BASH_VERSINFO[0] < 4)); then
		dotfiles::println 'Error: This script requires bash v4.0 or newer. You are running %s.' "${BASH_VERSION}" >&2

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
			dotfiles::println 'Error: Cannot source "%s": File does not exist or is a directory.' "${target_file}" >&2
			return 1
		fi

		if [[ ! -r "${target_file}" ]]; then
			dotfiles::println 'Error: Cannot source "%s": Read permission denied.' "${target_file}" >&2
			return 1
		fi

		source "${target_file}" || {
			local err_code=$?
			dotfiles::println 'Error: File "%s" was read, but execution failed with exit code %d.' "${target_file}" "${err_code}" >&2
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
  -u, --update               Update from git before performing any operations
      --update-only          Update from git then exit
  -r, --repair               Remove orphaned symlinks, then install/relink
      --reset                Remove all symlinks managed by this tool
      --clean-backups [N]    Remove backups older than <N> days (default: 7, 0 = all)
      --clean-logs [N]       Remove logs older than <N> days (default: 7, 0 = all)
      --clean-all            Remove all backups and logs
	  --uninstall            Deletes symlinks, logs, and backups, then deletes install directory

MODULES
  -i, --install <module...>  Install ONLY the specified modules <module>, semicolon-separated
  -x, --exclude <module...>  Install all modules <module> EXCEPT those specified, semicolon-
                             separated
  -l, --list                 Display all available modules, status, and information

SETUP
	  --dir <path>           Install directory (default: ~/dotfiles)
      --ref <ref>            Git branch, tag, or commit to install (default: main)

RESTORE
      --restore [file...]    Restore file(s) from the most recent backup.
                             Without arguments, lists restorable files.
      --restore-all          Restore ALL files from the most recent backup run.
      --from <run>           Restore from a specific run (e.g. 2026-07-16/14-52-31)  
                             (default: most recent)
      --backup-list          Show all available backup runs and their files.

BEHAVIOUR
  -n, --dry-run              Print planned actions without modifying the disk
  -I, --interactive          Prompt for confirmation before every action/modification
      --noconfirm            Do not prompt for any confirmation
  -y, --yes                  Auto-accept yes to prompts. Alias to --noconfirm
  -f, --force                Overwrite existing files/links
  -K, --autorestart          Automatically restart shell at script end
      --no-backup            Delete existing conflicting files instead of backing up	

LOGGING
  -v, --verbose              Print detailed step-by-step instructions
  -q, --quiet                Suppress all standard output except errors
      --log-level <level>    Set log verbosity <level> | debug, info, warn, error (default: info)
      --no-log               Disable writing to the log file

///PACKAGES & HOOKS
      ///--no-deps              Skip dotfiles dependency installation
      ///--no-hooks             Skip pre/post installation scripts

INFORMATION
  -d, --diff                 Show diff between current files and incoming dotfiles
      --verify               Check all managed symlinks (exit 0 = healthy, 1 = broken)
  -e, --examples             Show some example commands
	  --version              Show the version and git information of this program
  -h, --help                 Show this help message

ENVIRONMENT VARIABLES
  Global (Always Active):
    DOTFILES_INSTALL_DIR     Target directory for installation (default: ~/dotfiles)
    DOTFILES_INSTALL_REF     Specific git branch, tag, or commit to install (default: main)
    DOTFILES_LOG_DIR         Path to store log files (default: ~/.config/dotfiles/logs)
    DOTFILES_CACHE_DIR       Path to store temporary cache (default: ~/.cache/dotfiles)
    DOTFILES_LOG             Set to 0 or false to disable log file writing (default: 1)
    DOTFILES_LOCAL_MODS      Set to 1 or true to stash uncommitted local changes (default: 0)
    DOTFILES_AUTORESTART     Set to 1 or true to restart shell at script finish (default: 0)

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

	dotfiles::print_modules() {
		dotfiles::set_available_modules

		# read manifest once into an indexed array of source paths
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"
		local -a manifest_sources=()
		if [[ -f "${manifest}" ]]; then
			while IFS=$'\t' read -r src dest; do
				[[ -n "${src}" ]] && manifest_sources+=("${src}")
			done <"${manifest}"
		fi

		# helper: is this source path in the manifest?
		# sets in_manifest to 0 or 1
		local in_manifest

		# helper: get the dest for a source (empty string if no mapping)
		local dest

		dotfiles::println
		dotfiles::println 'AVAILABLE MODULES'
		dotfiles::println

		local current_category=""

		for item in "${AVAILABLE_MODULES[@]}"; do
			local category="${item%%/*}"
			local module="${item##*/}"
			local mod_dir="${SRC_PATH}/${item}"

			# category header
			if [[ "$category" != "$current_category" ]]; then
				[[ -n "$current_category" ]] && dotfiles::println
				dotfiles::println "${category}"
				current_category="${category}"
			fi

			# module header
			if [[ ! -d "$mod_dir" ]]; then
				printf '  %s:\n    (-) directory not found\n' "$module"
				continue
			fi

			printf '  %s:\n' "$module"

			# collect files in this module dir
			local -a files=()
			while IFS= read -r f; do
				[[ -z "$f" ]] && continue
				files+=("$f")
			done < <(find "$mod_dir" -maxdepth 1 -type f 2>/dev/null | sort)

			if [[ ${#files[@]} -eq 0 ]]; then
				printf '    (–) no files\n'
				continue
			fi

			local module_ok=0
			local module_total=0

			for src_file in "${files[@]}"; do
				# only show files this tool manages (in manifest)
				in_manifest=0
				for ms in "${manifest_sources[@]}"; do
					if [[ "$ms" == "$src_file" ]]; then
						in_manifest=1
						break
					fi
				done

				if [[ ${in_manifest} -eq 0 ]]; then
					orphans+=("${link}")
				fi

				# resolve dest to check if symlink is alive
				dest="$(dotfiles::resolve_dest "$src_file")" || dest=""

				local status="✗"
				local fname="${src_file##*/}"

				if [[ -n "$dest" ]]; then
					if [[ -L "$dest" && -e "$dest" ]]; then
						status="✓"
					elif [[ -L "$dest" ]]; then
						status="!" # symlink exists but target is gone (broken)
					fi
				fi

				printf '    (%s) %s\n' "$status" "$fname"
				module_total=$((module_total + 1))
				[[ "$status" == "✓" ]] && module_ok=$((module_ok + 1))
			done

			# if no files in this module are managed, show a hint
			if [[ ${module_total} -eq 0 ]]; then
				printf '    (✗) not installed\n'
			fi
		done
		dotfiles::println
	}

	# Print all backup runs and their files, newest first.
	# Usage: print_backups
	# Returns: always 0
	dotfiles::print_backups() {
		local -r base="${DOTFILES_CACHE_DIR}/backups"

		if [[ ! -d "${base}" ]]; then
			dotfiles::println 'No backups found.'
			return 0
		fi

		local -a runs=()
		# collect YYYY-MM-DD/HH-MM-SS dirs, sorted newest first
		while IFS= read -r -d '' run; do
			runs+=("$(echo "${run}" | sed "s|^${base}/||")")
		done < <(find "${base}" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -rz | tac -z 2>/dev/null ||
			find "${base}" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -rz)

		if [[ ${#runs[@]} -eq 0 ]]; then
			dotfiles::println 'No backup runs found.'
			return 0
		fi

		dotfiles::println 'AVAILABLE BACKUPS %d run(s):' "${#runs[@]}"
		dotfiles::println

		local run
		for run in "${runs[@]}"; do
			printf '  %s/\n' "${run}"
			local -a files
			files=()
			while IFS= read -r -d '' f; do
				files+=("$(basename "$f")")
			done < <(find "${base}/${run}" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

			for f in "${files[@]}"; do
				printf '    %s\n' "$f"
			done
			printf '\n'
		done
	}

	# Returns 0 if all managed symlinks are valid, 1 otherwise.
	# Prints a one-line summary (for scripts) or a table (for humans).
	dotfiles::print_verification() {
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"

		if [[ ! -f "${manifest}" ]]; then
			dotfiles::println '  [verify] No manifest found. Nothing to verify.'
			return 0
		fi

		local broken=0
		local ok=0
		local src dest

		while IFS=$'\t' read -r src dest; do
			[[ -z "${dest}" ]] && continue
			if [[ -L "${dest}" && -e "${dest}" && "$(readlink "${dest}")" == "${src}" ]]; then
				ok=$((ok + 1))
			else
				broken=$((broken + 1))
				printf '  %s\n' "${dest}" >&2
			fi
		done <"${manifest}"

		if [[ ${broken} -eq 0 ]]; then
			dotfiles::println '  [verify] OK (%d links valid).' "${ok}" >&2
			return 0
		else
			dotfiles::println '  [verify] %d broken, %d ok.' "${broken}" "${ok}" >&2
			return 1
		fi
	}

	dotfiles::print_examples() {
		local -r program="$(basename "$0")"
		cat <<EOF

TODO: short description of example
TODO: command 

bash ${program}


EOF
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
			if dotfiles::is_true "${DOTFILES_AUTORESTART}"; then
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
			dotfiles::println '  Your changes will be preserved on top of the latest %s.' "$DOTFILES_INSTALL_REF"

			if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "$DOTFILES_INSTALL_REF" 2>/dev/null; then
				dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "$DOTFILES_INSTALL_REF" >&2
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
		if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "$DOTFILES_INSTALL_REF" 2>/dev/null; then
			fetch_ok=0
			dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "$DOTFILES_INSTALL_REF" >&2
			dotfiles::prompt_continue "Your files may be overwritten\n" || exit 1
			dotfiles::println '  Continuing with current local state.'
		fi
		if ((fetch_ok)); then
			if ! command git -C "${SRC_PATH}" checkout "$DOTFILES_INSTALL_REF" 2>/dev/null; then
				dotfiles::println 'Error: Checkout of %s failed in %s' "$DOTFILES_INSTALL_REF" "${SRC_PATH}" >&2
				return 1
			fi
			if ! command git -C "${SRC_PATH}" reset --hard FETCH_HEAD 2>/dev/null; then
				dotfiles::println 'Error: Reset to %s failed in %s' "$DOTFILES_INSTALL_REF" "${SRC_PATH}" >&2
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
# manifest
{
	# Append a source→dest pair to the manifest (deduplicated).
	# Called by symlink_file after a successful link creation or confirmation.
	# Usage: dotfiles::manifest_add <source> <dest>
	dotfiles::manifest_add() {
		local -r source="$1"
		local -r dest="$2"
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"

		# ensure parent dir exists
		mkdir -p "$(dirname "${manifest}")" 2>/dev/null || true

		# skip if already recorded
		if grep -qF -e "${dest}" "${manifest}" 2>/dev/null; then
			return 0
		fi

		printf '%s\t%s\n' "${source}" "${dest}" >>"${manifest}"
	}

	# Remove a dest entry from the manifest.
	# Usage: dotfiles::manifest_remove <dest>
	dotfiles::manifest_remove() {
		local -r dest="$1"
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"

		[[ -f "${manifest}" ]] || return 0
		grep -vF -e "${dest}" "${manifest}" >"${manifest}.tmp" 2>/dev/null &&
			mv "${manifest}.tmp" "${manifest}"
	}

	# Remove all manifest entries (called after a full clean).
	# Usage: dotfiles::clear
	dotfiles::manifest_clear() {
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"
		[[ -f "${manifest}" ]] || return 0
		: >"${manifest}"
	}
}

#############################
# windows
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
# clean/reset
{
	# Remove all symlinks recorded in the manifest, plus any orphaned
	# symlinks pointing into $SRC_PATH that are missing from the manifest.
	#
	# Usage: clean_symlinks
	#
	# Returns:
	#   0 on success
	#   1 if one or more removals failed
	dotfiles::clean_symlinks() {
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"
		local -a managed=()
		local -a orphans=()
		local src
		local dest

		# manifest entries
		if [[ -f "${manifest}" ]]; then
			while IFS=$'\t' read -r src dest; do
				[[ -z "${dest}" ]] && continue
				managed+=("${dest}")
			done <"${manifest}"
		fi

		# safety net
		local -a scan_dirs=("$HOME" "$HOME/.ssh")
		if [[ "${TARGET_OS:-}" == "${OS_MAC}" ]]; then
			scan_dirs+=("$HOME/Library/Application Support/iTerm2")
		fi

		local dir
		local link
		local target
		for dir in "${scan_dirs[@]}"; do
			[[ -d "$dir" ]] || continue
			while IFS= read -r -d '' link; do
				target="$(readlink "$link" 2>/dev/null)" || continue
				[[ "$target" == "${SRC_PATH}/"* ]] || continue
				# skip if already in managed list
				local in_manifest=0
				for d in "${managed[@]}"; do
					[[ "$d" == "$link" ]] && in_manifest=1 && break
				done
				((in_manifest)) || orphans+=("${link}")
			done < <(find "$dir" -maxdepth 2 -type l -print0 2>/dev/null)
		done

		local total=$((${#managed[@]} + ${#orphans[@]}))
		if [[ ${total} -eq 0 ]]; then
			dotfiles::println '  [clean-symlinks] No managed symlinks found.'
			return 0
		fi

		dotfiles::println '  [clean-symlinks] Found %d managed, %d orphaned symlink(s).' \
			"${#managed[@]}" "${#orphans[@]}"

		#remove
		local -a all_links=("${managed[@]}" "${orphans[@]}")
		local removed=0
		local failed=0

		for link in "${all_links[@]}"; do
			[[ -L "$link" ]] || continue # already gone
			target="$(readlink "$link" 2>/dev/null)"
			printf '    %s -> %s\n' "$link" "${target:-<gone>}"

			if ((DRY_RUN)); then
				dotfiles::println '    [dry-run] rm %s' "$link"
				removed=$((removed + 1))
				continue
			fi

			if ((INTERACTIVE)); then
				local choice
				if ! read -r -p '    Remove? [Y/n]: ' choice; then
					dotfiles::println '    [skip] no input available.'
					continue
				fi
				case "$choice" in
				[nN])
					dotfiles::println '    [skip] %s (user declined)' "$link"
					continue
					;;
				esac
			fi

			if rm "$link" 2>/dev/null; then
				dotfiles::manifest_remove "$link"
				removed=$((removed + 1))
			else
				dotfiles::println 'Error: cannot remove %s' "$link" >&2
				failed=$((failed + 1))
			fi
		done

		# if we removed everything, truncate the manifest
		if [[ ${#all_links[@]} -eq ${removed} ]]; then
			dotfiles::manifest_clear
		fi

		dotfiles::println '  [clean-symlinks] Removed %d, failed %d.' "$removed" "$failed"
		((failed > 0)) && return 1
		return 0
	}

	# Remove all dated backup directories under $DOTFILES_CACHE_DIR/backups/
	# Usage: clean_backups
	#
	# Returns:
	#   0 on success (including "nothing to clean")
	#   1 on error
	dotfiles::clean_backups() {
		local -r base="${DOTFILES_CACHE_DIR}/backups"
		local -r days="${CLEAN_BACKUPS_DAYS:-0}"

		if [[ ! -d "${base}" ]]; then
			dotfiles::println '  [clean-backups] No backup directory found. Nothing to do.'
			return 0
		fi

		if ((days == 0)); then
			# remove everything
			if ((DRY_RUN)); then
				dotfiles::println '  [dry-run] rm -rf %s' "${base}"
				return 0
			fi
			rm -rf "${base}" || {
				dotfiles::println 'Error: failed to remove %s' "${base}" >&2
				return 1
			}
			dotfiles::println '  [clean-backups] Removed all backups.'
			return 0
		fi

		# remove day-directories older than N days
		local removed=0
		while IFS= read -r -d '' dir; do
			removed=$((removed + 1))
			if ((DRY_RUN)); then
				dotfiles::println '  [dry-run] rm -rf %s' "$dir"
			else
				rm -rf "$dir"
			fi
		done < <(find "${base}" -mindepth 1 -maxdepth 1 -type d -mtime +"${days}" -print0 2>/dev/null)

		dotfiles::println '  [clean-backups] Removed %d day(s) older than %d.' "${removed}" "${days}"
		return 0
	}

	# Remove all log files under $DOTFILES_LOG_DIR/
	# Usage: clean_logs
	#
	# Returns:
	#   0 on success (including "nothing to clean")
	#   1 on error
	dotfiles::clean_logs() {
		local -r days="${CLEAN_LOGS_DAYS}"
		local -r base="${DOTFILES_LOG_DIR}"

		if [[ ! -d "${base}" ]]; then
			dotfiles::println '  [clean-logs] No log directory found. Nothing to do.'
			return 0
		fi

		local -a targets=()
		local removed=0

		if [[ "${days}" == "0" ]]; then
			# remove all log files
			while IFS= read -r -d '' f; do
				targets+=("$f")
			done < <(find "${base}" -maxdepth 1 -type f -print0 2>/dev/null)
		else
			# remove files older than N days
			while IFS= read -r -d '' f; do
				targets+=("$f")
			done < <(find "${base}" -maxdepth 1 -type f -mtime +"${days}" -print0 2>/dev/null)
		fi

		if [[ ${#targets[@]} -eq 0 ]]; then
			dotfiles::println '  [clean-logs] No log files to remove.'
			return 0
		fi

		for f in "${targets[@]}"; do
			if ((DRY_RUN)); then
				dotfiles::println '  [dry-run] rm %s' "$f"
			else
				rm -f "$f" || {
					dotfiles::println 'Error: cannot remove %s' "$f" >&2
					return 1
				}
			fi
			removed=$((removed + 1))
		done

		dotfiles::println '  [clean-logs] Removed %d log file(s)%s.' \
			"${removed}" "$([[ "${days}" != "0" ]] && printf ' older than %d day(s)' "${days}")"
		return 0
	}

	dotfiles::repair_symlink() {
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"
		local -a orphans=()
		local src dest

		# find orphaned managed symlinks
		if [[ -f "${manifest}" ]]; then
			while IFS=$'\t' read -r src dest; do
				[[ -z "${dest}" ]] && continue
				# orphan: link exists but target is gone, or link was removed by user
				if [[ -L "${dest}" && ! -e "${dest}" ]]; then
					orphans+=("${dest}")
				elif [[ ! -L "${dest}" && -e "${dest}" ]]; then
					# dest exists as a regular file (user replaced the link)
					# NOT orphaned — skip; user is deliberately overriding
					continue
				fi
			done <"${manifest}"
		fi

		# remove orphans
		if [[ ${#orphans[@]} -gt 0 ]]; then
			dotfiles::println '  [relink] Removing %d orphaned symlink(s):' "${#orphans[@]}"
			local removed=0
			for link in "${orphans[@]}"; do
				printf '    %s\n' "$link"
				if ((DRY_RUN)); then
					dotfiles::println '    [dry-run] rm %s' "$link"
				else
					rm -f "$link"
					dotfiles::manifest_remove "$link"
				fi
				removed=$((removed + 1))
			done
			dotfiles::println '  [relink] Removed %d orphan(s).' "$removed"
		fi

		dotfiles::symlink_all

		dotfiles::println '  [relink] Done.'
	}

}

# restoration
{
	# Restore a single file from a backup run.
	# Removes the symlink (if present), places the original file back,
	# and removes the manifest entry.
	#
	# Usage: restore_file <basename> <run_path>
	#
	# Arguments:
	#   $1 (basename) : e.g. ".zshrc" (matches *.bak in the run dir)
	#   $2 (run_path) : e.g. "2025-07-14/10-23-41"
	#
	# Returns:
	#   0 on success
	#   1 on error
	dotfiles::restore_file() {
		local -r name="$1"
		local -r run="$2"
		local -r base="${DOTFILES_CACHE_DIR}/backups"
		local -r src="${base}/${run}/${name}.bak"

		if [[ ! -f "${src}" ]]; then
			dotfiles::println 'Error: no backup of "%s" in run %s.' "${name}" "${run}" >&2
			return 1
		fi

		# determine destination: look up in manifest, fall back to $HOME
		local dest="${HOME}/${name}"
		local -r manifest="${DOTFILES_CACHE_DIR}/manifest.tsv"
		if [[ -f "${manifest}" ]]; then
			# actually look for the dest path that had this basename
			while IFS=$'\t' read -r _src dest; do
				if [[ "${dest##*/}" == "${name}" ]]; then
					dest="${dest}"
					break
				fi
			done <"${manifest}"
		fi

		dotfiles::println '  [restore] %s -> %s' "${src}" "${dest}"

		# if dest is currently a symlink to our repo, remove it
		if [[ -L "${dest}" ]]; then
			local link_target
			link_target="$(readlink "${dest}")"
			if [[ "${link_target}" == "${SRC_PATH}/"* ]]; then
				if ((DRY_RUN)); then
					dotfiles::println '    [dry-run] rm symlink %s' "${dest}"
				else
					rm -f "${dest}"
					dotfiles::manifest_remove "${dest}"
				fi
			fi
		fi

		# if dest exists as a regular file, back it up first (meta-backup)
		if [[ -e "${dest}" && ! -L "${dest}" ]]; then
			dotfiles::backup_file "${dest}" || return 1
		fi

		# copy backup back to dest
		if ((DRY_RUN)); then
			dotfiles::println '    [dry-run] cp %s %s' "${src}" "${dest}"
			return 0
		fi

		cp "${src}" "${dest}" || {
			dotfiles::println 'Error: cannot restore %s to %s.' "${src}" "${dest}" >&2
			return 1
		}

		dotfiles::println '    [restored] %s' "${dest}"
		return 0
	}

	# Find the most recent run that contains a given filename.
	# Prints the run path (e.g. "2025-07-14/10-23-41") to stdout.
	# Returns 1 if not found.
	dotfiles::restore::find_run() {
		local -r name="$1"
		local -r base="${DOTFILES_CACHE_DIR}/backups"

		[[ -d "${base}" ]] || return 1

		# newest first: sort by day desc, then time desc
		local run
		while IFS= read -r -d '' run; do
			if [[ -f "${run}/${name}.bak" ]]; then
				printf '%s' "$(echo "${run}" | sed "s|^${base}/||")"
				return 0
			fi
		done < <(find "${base}" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -rz | tac -z 2>/dev/null ||
			find "${base}" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -rz)

		return 1
	}

	# Orchestrates restore for one or more files.
	# Usage: restore
	#
	# Precondition:
	#   RESTORE_FILES, RESTORE_ALL, RESTORE_FROM are set by argparse.
	#
	# Returns:
	#   0 on success
	#   1 if one or more restorations failed
	dotfiles::restore() {
		local -a targets=()
		local -r base="${DOTFILES_CACHE_DIR}/backups"
		local run

		if [[ ! -d "${base}" ]]; then
			dotfiles::println 'Error: no backup directory found. Nothing to restore.' >&2
			return 1
		fi

		# determine targets
		if [[ ${RESTORE_ALL} -eq 1 ]]; then
			# all files from the specified (or latest) run
			if [[ -n "${RESTORE_FROM}" ]]; then
				run="${RESTORE_FROM}"
			else
				run="$(find "${base}" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | sort -z | tac -z 2>/dev/null | head -z -1 | tr -d '\0')"
				run="${run#"${base}"/}"
				[[ -z "${run}" ]] && {
					dotfiles::println 'Error: no backup runs found.' >&2
					return 1
				}
			fi
			# collect all files in that run
			local f
			while IFS= read -r -d '' f; do
				local name
				name="$(basename "$f")"
				name="${name%.bak}"
				targets+=("${name}")
			done < <(find "${base}/${run}" -maxdepth 1 -type f -print0 2>/dev/null)
			dotfiles::println '=> Restoring %d file(s) from run %s:' "${#targets[@]}" "${run}"
		else
			# specific file(s), each from its own most-recent run (or --from)
			for name in "${RESTORE_FILES[@]}"; do
				if [[ -n "${RESTORE_FROM}" ]]; then
					run="${RESTORE_FROM}"
				else
					if ! run="$(dotfiles::restore::find_run "${name}")"; then
						dotfiles::println 'Error: no backup of "%s" found in any run.' "${name}" >&2
						return 1
					fi
				fi
				targets+=("${name}")
				dotfiles::println '=> Restoring "%s" from run %s:' "${name}" "${run}"
			done
		fi

		# restore each
		local ok=0
		local failed=0

		for name in "${targets[@]}"; do
			local target_run
			if [[ ${RESTORE_ALL} -eq 1 ]]; then
				target_run="${run}"
			else
				if [[ -n "${RESTORE_FROM}" ]]; then
					target_run="${RESTORE_FROM}"
				else
					target_run="$(dotfiles::restore::find_run "${name}")"
				fi
			fi

			if dotfiles::restore_file "${name}" "${target_run}"; then
				ok=$((ok + 1))
			else
				failed=$((failed + 1))
			fi
		done

		dotfiles::println '  Restore done: %d/%d succeeded.' "${ok}" "$((ok + failed))"
		((failed > 0)) && return 1
		return 0
	}

}
####################
# $1 = flag name for the error message
# $2 = value to assign to MODE
dotfiles::assign_mode() {
	if [[ -n "$MODE" ]]; then
		dotfiles::println 'Error: Cannot specify multiple actions. "%s" conflicts with "%s".' "$1" "$MODE" >&2
		exit 2
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
			for mod in "${AVAILABLE_MODULES[@]}"; do
				[[ "$mod" == "$m" ]] && valid=1 && break
			done
		else
			# top-level match (e.g., "apps")
			for mod in "${AVAILABLE_MODULES[@]}"; do
				[[ "${mod%%/*}" == "$m" ]] && valid=1 && break
			done
		fi

		if [[ $valid -eq 0 ]]; then
			dotfiles::println 'Error: Unknown module "%s".' "$m" >&2
			exit 2
		fi
		arr+=("$m")
	done
}

dotfiles::argparse() {
	# setup
	DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-${HOME}/dotfiles}"
	DOTFILES_INSTALL_REF="${DOTFILES_INSTALL_REF:-main}"
	# behaviour
	DOTFILES_AUTORESTART="${DOTFILES_AUTORESTART:-0}"
	DOTFILES_LOG="${DOTFILES_LOG:-1}"

	DRY_RUN=0
	FORCE=0
	UPDATE=0
	INTERACTIVE=0
	NO_BACKUP=0
	NO_DEPS=0
	NO_HOOKS=0
	NO_CONFIRM=0
	VERBOSE=0
	QUIET=0
	MODE=""
	REPAIR_SYMLINKS=0
	CLEAN_BACKUPS_DAYS=""
	CLEAN_LOGS_DAYS=""
	LOG_LEVEL="info"
	INSTALL_MODULES=()
	EXCLUDE_MODULES=()
	# restore
	RESTORE_FILES=()
	RESTORE_ALL=0
	RESTORE_FROM=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		# information
		-h | --help)
			dotfiles::print_help
			exit 0
			;;
		--version)
			dotfiles::print_version
			exit 0
			;;
		-e | --examples)
			dotfiles::print_examples
			exit 0
			;;
		--verify)
			local verify_rc=0
			dotfiles::print_verification || verify_rc=$?
			exit "${verify_rc}"
			;;
		-d | --diff)
			dotfiles::assign_mode "--diff" "diff"
			shift
			;;

		# actions
		-u | --update)
			UPDATE=1
			shift
			;;
		--update-only)
			dotfiles::update || exit 1
			dotfiles::println '=> Successfully updated!'
			exit 0
			;;
		# cleaning
		-r | --repair)
			REPAIR_SYMLINKS=1
			shift
			;;
		--reset)
			dotfiles::assign_mode "--reset" "reset"
			shift
			;;
		--clean-backups)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				CLEAN_BACKUPS_DAYS="7"
				shift
			else
				if ! [[ "$2" =~ ^[0-9]+$ ]]; then
					dotfiles::println 'Error: Argument for "%s" must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
					exit 1
				fi
				CLEAN_BACKUPS_DAYS="$2"
				shift 2
			fi
			;;
		--clean-backups=*)
			if ! [[ "${1#*=}" =~ ^[0-9]+$ ]]; then
				dotfiles::println 'Error: Argument for "%s" must be a non-negative integer (days). Got "%s".' "--clean-backups" "${1#*=}" >&2
				exit 1
			fi
			CLEAN_BACKUPS_DAYS="${1#*=}"
			shift
			;;
		--clean-logs)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				CLEAN_LOGS_DAYS="7"
				shift
			else
				if ! [[ "$2" =~ ^[0-9]+$ ]]; then
					dotfiles::println 'Error: Argument for "%s" must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
					exit 1
				fi
				CLEAN_LOGS_DAYS="$2"
				shift 2
			fi
			;;
		--clean-logs=*)
			if ! [[ "${1#*=}" =~ ^[0-9]+$ ]]; then
				dotfiles::println 'Error: Argument for "%s" must be a non-negative integer (days). Got "%s".' "--clean-logs" "${1#*=}" >&2
				exit 1
			fi
			CLEAN_LOGS_DAYS="${1#*=}"
			shift
			;;
		--clean-all)
			CLEAN_BACKUPS_DAYS="0"
			CLEAN_LOGS_DAYS="0"
			shift
			;;
		--uninstall)
			# implies --reset; also removes the clone
			dotfiles::assign_mode "--uninstall" "uninstall"
			shift
			;;

			# modules
		-i | --install)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println 'Error: Missing argument for "%s".' "$1" >&2
				exit 1
			fi
			dotfiles::parse_module_list "$2" INSTALL_MODULES
			shift 2
			;;
		-i=* | --install=*)
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
		-x=* | --exclude=*)
			dotfiles::parse_module_list "${1#*=}" EXCLUDE_MODULES
			shift
			;;
		-l | --list)
			dotfiles::print_modules
			exit 0
			;;

		# setup
		--dir)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println 'Error: Missing argument for --dir.' "$1" >&2
				exit 1
			fi
			DOTFILES_INSTALL_DIR="$2"
			shift 2
			;;
		--dir=*)
			DOTFILES_INSTALL_DIR="${1#*=}"
			shift
			;;
		--ref)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println 'Error: Missing argument for --ref.' "$1" >&2
				exit 1
			fi
			DOTFILES_INSTALL_REF="$2"
			shift 2
			;;
		--ref=*)
			DOTFILES_INSTALL_REF="${1#*=}"
			shift
			;;

		# restore
		--restore)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				shift
			else
				RESTORE_FILES+=("$2")
				shift 2
			fi
			;;
		--restore-all)
			RESTORE_ALL=1
			shift
			;;
		--from)
			if [[ -z "${2:-}" || "$2" == -* ]]; then
				dotfiles::println 'Error: Missing argument for --from.' >&2
				exit 1
			fi
			RESTORE_FROM="$2"
			shift 2
			;;
		--from=*)
			RESTORE_FROM="${1#*=}"
			shift
			;;
		--backup-list)
			dotfiles::print_backups
			exit 0
			;;

		# behaviour
		-n | --dry-run)
			DRY_RUN=1
			shift
			;;
		-I | --interactive)
			if [[ "${NO_CONFIRM}" -eq 1 ]]; then
				dotfiles::println 'Error: %s conflicts with --noconfirm.' "$1" >&2
				exit 1
			fi
			INTERACTIVE=1
			shift
			;;
		--noconfirm | -y | --yes)
			if [[ "${INTERACTIVE}" -eq 1 ]]; then
				dotfiles::println 'Error: %s conflicts with --interactive.' "$1" >&2
				exit 1
			fi
			NO_CONFIRM=1
			shift
			;;
		-f | --force)
			FORCE=1
			shift
			;;
		-K | --autorestart)
			DOTFILES_AUTORESTART=1
			shift
			;;
		--no-backup)
			NO_BACKUP=1
			shift
			;;

		# logging
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
			DOTFILES_LOG=0
			shift
			;;

		# packages
		--no-deps)
			NO_DEPS=1
			shift
			;;
		--no-hooks)
			NO_HOOKS=1
			shift
			;;

		*)
			dotfiles::println 'Error: Invalid parameter "%s"' "$1"
			dotfiles::println 'Run "bash %s --help" for valid options.' "$(basename "$0")" >&2
			exit 1
			;;
		esac
	done

	# post validation
	local has_maintenance=0
	[[ -n "${CLEAN_BACKUPS_DAYS}" || -n "${CLEAN_LOGS_DAYS}" ]] && has_maintenance=1

	# repair and reset are mutually exclusive
	if [[ "${REPAIR_SYMLINKS}" -eq 1 && "${MODE}" == "reset" ]]; then
		dotfiles::println 'Error: --repair conflicts with --reset.' >&2
		exit 1
	fi

	# maintenance cannot combine with explicit install/exclude
	if [[ ${has_maintenance} -eq 1 ]]; then
		if [[ ${#INSTALL_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --clean-* is not valid with --install.' >&2
			exit 1
		fi
		if [[ ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --clean-* is not valid with --exclude.' >&2
			exit 1
		fi
	fi

	# restore conflicts with install/exclude
	local has_restore=0
	[[ ${#RESTORE_FILES[@]} -gt 0 || ${RESTORE_ALL} -eq 1 ]] && has_restore=1

	if [[ ${has_restore} -eq 1 ]]; then
		if [[ ${#INSTALL_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --restore is not valid with --install.' >&2
			exit 1
		fi
		if [[ ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --restore is not valid with --exclude.' >&2
			exit 1
		fi
		if [[ "${MODE}" == "reset" ]]; then
			dotfiles::println 'Error: --restore conflicts with --reset.' >&2
			exit 1
		fi
	fi

	# --from requires --restore or --restore-all
	if [[ -n "${RESTORE_FROM}" && ${has_restore} -eq 0 ]]; then
		dotfiles::println 'Error: --from requires --restore or --restore-all.' >&2
		exit 1
	fi

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

# Checks if a module should be installed.
# Returns 0 if enabled, 1 if skipped.
dotfiles::is_module_enabled() {
	local target_module="$1"                # e.g. "apps/git"
	local top_module="${target_module%%/*}" # e.g. "apps"
	# availability
	local entry
	local found=0
	for entry in "${AVAILABLE_MODULES[@]}"; do
		if [[ "$entry" == "$target_module" ]]; then
			found=1
			break
		fi
	done
	if ((!found)); then
		return 1
	fi

	# explicit exclude
	for entry in "${EXCLUDE_MODULES[@]}"; do
		if [[ "$entry" == "$target_module" || "$entry" == "$top_module" ]]; then
			return 1
		fi
	done

	# explicit include
	if [[ ${#INSTALL_MODULES[@]} -gt 0 ]]; then
		for entry in "${INSTALL_MODULES[@]}"; do
			if [[ "$entry" == "$target_module" || "$entry" == "$top_module" ]]; then
				return 0
			fi
		done
		return 1 # INSTALL_MODULES non-empty but this module not listed
	fi
	# install everything
	return 0
}

dotfiles::set_files_to_check() {
	FILES_TO_CHECK=()

	# shell
	local -r -a shell_zsh_files=(
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
	local -r -a shell_bash_files=(
		"${SHELL_DIR}/bash/.bashrc"
		"${SHELL_DIR}/bash/.bash_profile"
	)
	# app
	local -a app_git_files=(
		"${APP_DIR}/git/.gitignore"
		"${APP_DIR}/git/.gitattributes"
		"${APP_DIR}/git/.gitconfig"
	)
	local -r -a app_ssh_files=(
		"${APP_DIR}/ssh/config" # TODO: chmod 600 when symlink
		"${APP_DIR}/ssh/allowed_signers"
	)
	local -r -a app_curl_files=("${APP_DIR}/curl/.curlrc")
	local -r -a app_wget_files=("${APP_DIR}/wget/.wgetrc")
	local -r -a app_shellcheck_files=("${APP_DIR}/shellcheck/.shellcheckrc")
	local -r -a app_iterm2_files=(
		"${APP_DIR}/iterm2/Profiles.json"
		"${APP_DIR}/iterm2/schemas/0x96f.itermcolors"
		"${APP_DIR}/iterm2/schemas/Argonaut.itermcolors"
		"${APP_DIR}/iterm2/schemas/Aurora.itermcolors"
		"${APP_DIR}/iterm2/schemas/Floraverse.itermcolors"
	)

	case "${TARGET_OS}" in
	"${OS_MAC}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.local.mac")
		;;
	"${OS_ARCHLINUX}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.local.archlinux")
		;;
	"${OS_WINDOWS}")
		app_git_files+=("${APP_DIR}/git/.gitconfig.local.windows")
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

	declare -r FILES_TO_CHECK
}

dotfiles::do_mode() {
	case "$MODE" in
	install)
		dotfiles::symlink_all
		;;
	reset)
		dotfiles::clean_symlinks
		;;
	uninstall)
		dotfiles::clean_symlinks
		dotfiles::manifest_clear
		if ((DRY_RUN)); then
			dotfiles::println '  [dry-run] rm -rf %s' "${SRC_PATH}"
		else
			dotfiles::println '=> Removing clone at %s' "${SRC_PATH}"
			rm -rf "${SRC_PATH}" || {
				dotfiles::println 'Error: cannot remove %s' "${SRC_PATH}" >&2
				return 1
			}
		fi
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

	dotfiles::set_shell_dir # SHELL_DIR
	dotfiles::set_app_dir   # APP_DIR
	if [[ ! -d "${SHELL_DIR}" ]]; then
		dotfiles::println "Error: unable to locate shells/."
		exit 1
	fi
	if [[ ! -d "${APP_DIR}" ]]; then
		dotfiles::println "Error: unable to locate apps/."
		exit 1
	fi

	dotfiles::set_env || { # TARGET_OS & TARGET_RUNTIME
		dotfiles::println 'Warning: unable to determine $TARGET_OS or $TARGET_RUNTIME.'
		dotfiles::prompt_continue "Some functionality may be limited."
	}
	if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
		dotfiles::set_windows_sudo
	fi
	dotfiles::set_elevated          # IS_ELEVATED
	dotfiles::set_available_modules # AVAILABLE_MODULES

	lib_dir="${SRC_PATH}/lib"
	local -r -a lib_files=("${lib_dir}/filesystem.sh" "${lib_dir}/git.sh" "${lib_dir}/template.sh")
	dotfiles::check_exists "${lib_files[@]}" || exit 1

	dotfiles::source_file "${lib_dir}/filesystem.sh" || {
		exit 1
	}
	#dotfiles::source_file "${lib_dir}/git.sh" || {
	#	exit 1
	#}
	#dotfiles::source_file "${lib_dir}/template.sh" || {
	#	exit 1
	#}

	dotfiles::argparse "$@"
	if dotfiles::is_true "${DOTFILES_LOG}"; then
		echo "TODO: init logging"
	fi

	dotfiles::set_github_ref # DOTFILES_INSTALL_REF

	dotfiles::print_banner

	if [[ "${UPDATE}" -eq 1 ]]; then
		dotfiles::update || exit 1
		dotfiles::println '=> Successfully updated!'
	fi

	# switch to native powershell if non sudo windows bash
	if [[ "${IS_ELEVATED}" -eq 0 && "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
		case "${TARGET_RUNTIME}" in
		"${RUNTIME_GITBASH}" | "${RUNTIME_UNKNOWN}")
			if dotfiles::prompt_windows_handoff; then
				dotfiles::windows_handoff
			fi
			;;
		*) ;;
		esac
	fi

	# figure out what files are needed based on args
	dotfiles::println '=> Verifying files...'
	dotfiles::set_files_to_check # FILES_TO_CHECK
	dotfiles::check_exists "${FILES_TO_CHECK[@]}" || {
		exit 1
	}

	# dispatch
	local has_action=0
	[[ -n "${CLEAN_LOGS_DAYS}" ]] && has_action=1
	[[ -n "${CLEAN_BACKUPS_DAYS}" ]] && has_action=1
	[[ "${REPAIR_SYMLINKS}" -eq 1 ]] && has_action=1
	[[ "${MODE}" == "reset" ]] && has_action=1
	[[ ${#RESTORE_FILES[@]} -gt 0 || ${RESTORE_ALL} -eq 1 ]] && has_action=1

	if [[ ${has_action} -eq 1 ]]; then
		# maintenance
		[[ -n "${CLEAN_LOGS_DAYS}" ]] && dotfiles::clean_logs
		[[ -n "${CLEAN_BACKUPS_DAYS}" ]] && dotfiles::clean_backups

		# symlink / restore actions (mutually exclusive, validated in argparse)
		if [[ "${MODE}" == "reset" ]]; then
			dotfiles::clean_symlinks
		elif [[ "${REPAIR_SYMLINKS}" -eq 1 ]]; then
			dotfiles::repair_symlink
		elif [[ ${#RESTORE_FILES[@]} -gt 0 || ${RESTORE_ALL} -eq 1 ]]; then
			dotfiles::restore
		fi

		dotfiles::println '=> Done.'
		exit 0
	fi

	# TODO: logging

	# dotfiles::print_start
	# TODO: lib filesystem template git
	# TODO: symlink and template
	dotfiles::do_mode

	dotfiles::print_end
	if dotfiles::is_true "${DOTFILES_AUTORESTART}"; then
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
