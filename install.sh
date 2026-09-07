#!/usr/bin/env bash
# install.sh

# ensure entire script is downloaded
{
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
			printf 'Error: unable to resolve %s' "${HOME}"
			exit 1
		fi

		readonly REPO_URL="https://github.com/risingstarfish/dotfiles.git"
		#  user defined  env
		readonly DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-${HOME}/.config/dotfiles/logs}"
		readonly DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-${HOME}/.cache/dotfiles}"
		readonly DOTFILES_LOCAL_MODS="${DOTFILES_LOCAL_MODS:-0}"
		readonly DOTFILES_IGNORE_HANDOFF="${DOTFILES_IGNORE_HANDOFF:-0}"

		readonly MANIFEST="${DOTFILES_CACHE_DIR}/manifest.tsv"
		readonly MERGE_TOP_SENTINEL="# --- Local Configuration (managed by dotfiles) ---"
		readonly MERGE_BOTTOM_SENTINEL="# --- Do not edit this line or above ---"

		readonly DEFAULT_NUM_BACKUP_PRINT="5"
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
		# FIXME: update or make more
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
				local target_path="$path"

				# If path is relative (does not start with '/' or '~')
				if [[ "$path" != /* ]] && [[ "$path" != ~* ]]; then
					# Resolve relative paths against SRC_PATH
					target_path="${prefix}${path}"
				fi

				# Check existence of the resolved path
				if [[ ! -e "$target_path" ]]; then
					# Strip the SRC_PATH prefix for clean output.
					# Absolute paths outside SRC_PATH remain unmodified.
					missing_paths+=("${target_path#"$prefix"}")
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
			declare -r SRC_PATH
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

		# Removes a specific module and all its children
		dotfiles::remove_module() {
			local target="$1"
			local filtered_modules=()

			for mod in "${AVAILABLE_MODULES[@]}"; do
				# Keep the module if it doesn't match the target exactly
				# AND doesn't start with "target/"
				if [[ "${mod}" != "${target}" && "${mod}" != "${target}/"* ]]; then
					filtered_modules+=("${mod}")
				fi
			done

			AVAILABLE_MODULES=("${filtered_modules[@]}")
		}

		# Replaces '*' with TARGET_OS, but only keeps the module if the resulting path exists
		dotfiles::replace_os_wildcards() {
			local updated_modules=()
			local os_mod
			local runtime_mod # fallback

			for mod in "${AVAILABLE_MODULES[@]}"; do
				# Check if the module contains an asterisk
				if [[ "${mod}" == *"*"* ]]; then
					os_mod="${mod//\*/${TARGET_OS}}"

					if [[ -e "${MODULE_DIR}/${os_mod}" ]]; then
						updated_modules+=("${os_mod}")
					else # try runtime
						runtime_mod="${mod//\*/${TARGET_RUNTIME}}"
						if [[ -e "${MODULE_DIR}/${runtime_mod}" ]]; then
							updated_modules+=("${runtime_mod}")
						fi
					fi
				else
					updated_modules+=("${mod}")
				fi
			done

			AVAILABLE_MODULES=("${updated_modules[@]}")
		}

		dotfiles::set_available_modules() {
			[[ -n "${AVAILABLE_MODULES:-}" ]] && return 0
			# order matters for help message
			# * == TARGET_OS
			# FIXME: declare -A

			AVAILABLE_MODULES=(
				"zsh/zshrc"
				"zsh/zsh_options"
				"zsh/zstyles"
				"zsh/zimrc"
				"zsh/p10k.zsh"
				"zsh/exports"
				"zsh/paths"
				"zsh/aliases"
				"zsh/functions"
				"zsh/zshrc.toggles"

				"bash/bashrc"

				"git/gitconfig"
				"git/gitconfig.local.*"
				"git/gitignore"
				"git/gitattributes"
				"git/diff-so-fancy"

				"ssh/config"
				"ssh/allowed_signers.gen"

				"dev/CMakeUserPresets.json"
				"dev/internal-flags.cmake"
				"dev/cmake-format.py"
				"dev/clang-format"
				"dev/clang-tidy"
				"dev/editorconfig"

				"topgrade/topgrade.toml"

				"fastfetch/config.jsonc.*"

				"tmux/tmux.conf.*"

				"curl/curlrc"

				"wget/wgetrc"

				"shellcheck/shellcheckrc"

				"claude/settings.json"
				"claude/plugin.json"
			)

			dotfiles::replace_os_wildcards
			if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
				dotfiles::remove_module 'topgrade/topgrade.toml'
			fi
			declare -r AVAILABLE_MODULES
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
			if [[ $# -eq 0 ]]; then
				msg=""
			elif [[ $# -gt 1 ]]; then
				printf -v msg "$@"
			else
				printf -v msg '%b' "$1"
			fi

			if [[ -n "$msg" ]]; then
				printf "%s\n" "$msg" >&2
			fi

			local choice
			while true; do
				echo
				if ! read -r -p 'Do you want to continue anyway? [y/N]: ' choice; then
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
  -u, --update               Update from Git and copy/link.
  -r, --repair               Remove orphaned symlinks and generated files, then re-link/generate.
      --reset                Remove all symlinks and generated files managed by this tool.
                             (note: copied/merged files will remain)
  -b, --backup [file...]     Copy current managed file(s) to the backup directory. Without 
                             arguments, backs up all managed files.
      --clean-backups [N]    Remove backups older than <N> days. (default: 7, 0 = all)
      --clean-logs [N]       Remove logs older than <N> days. (default: 7, 0 = all)
      --clean-all            Remove all backups and logs.
      --uninstall            Deletes symlinks, logs, and backups, then deletes install directory.

MODULES
  -i, --include <module...>  Install ONLY the specified modules <module>, semicolon-separated.
  -x, --exclude <module...>  Install all modules EXCEPT specified <module>, semicolon-separated.
  -l, --list                 Display all available modules, status, and information.

GIT
  -p, --pull                 Update from Git. (note: can be combined with --ref)
      --ref <ref>            Git branch, tag, or commit to install. (default: main)

RESTORE
      --restore [file...]    Restore file(s) from the most recent backup.
                             Without arguments, lists restorable files.
      --restore-all          Restore ALL files from the most recent backup run.
      --from <run>           Restore from a specific run (e.g. 2026-07-16/14-52-31).  
                             (default: most recent)
      --backup-list <N>      Show <N> available backup runs and their files. (default: 5)

BEHAVIOUR
  -n, --dry-run              Print planned actions without modifying the disk.
  -I, --interactive          Prompt for confirmation before every action/modification.
      --noconfirm            Do not prompt for any confirmation.
  -y, --yes                  Auto-accept yes to prompts. Alias to --noconfirm.
  -f, --force                Overwrite existing files/links.
  -K, --autorestart          Automatically restart shell at script end.
      --no-backup            Delete existing conflicting files instead of backing up.

LOGGING
  -v, --verbose              Print detailed step-by-step instructions.
  -q, --quiet                Suppress all standard output except errors.
      --log-level <level>    Set log verbosity <level>. Valid options are: debug, info, warn, or 
                             error. (default: info)
      --no-log               Disable writing to the log file.

///PACKAGES & HOOKS
      ///--no-deps              Skip dotfiles dependency installation.
      ///--no-hooks             Skip pre/post installation scripts.

INFORMATION
  -d, --diff                 Show diff between current files and incoming dotfiles.
      --verify               Check all managed symlinks. (exit 0 = healthy, 1 = broken)
      --examples             Show some example commands.
      --version              Show the version and git information of this program.
  -h, --help                 Show this help message.

ENVIRONMENT VARIABLES
  Global (Always Active):
    DOTFILES_INSTALL_DIR     Target directory for installation. (default: ~/dotfiles)
    DOTFILES_INSTALL_REF     Specific git branch, tag, or commit to install. (default: main)
    DOTFILES_LOG_DIR         Path to store log files. (default: ~/.config/dotfiles/logs)
    DOTFILES_CACHE_DIR       Path to store temporary cache. (default: ~/.cache/dotfiles)
    DOTFILES_LOG             Set to 0 or false to disable log file writing. (default: 1)
    DOTFILES_LOCAL_MODS      Set to 1 or true to stash uncommitted local changes. (default: 0)
    DOTFILES_AUTORESTART     Set to 1 or true to restart shell at script finish. (default: 0)

  Windows Specific:
    DOTFILES_IGNORE_HANDOFF  Set to 1 or true to ignore the Windows Powershell notice. (default 0)

EOF
		}

		dotfiles::git_or_unknown() {
			local default="$1"
			shift

			local out
			if out=$(command git -C "${SRC_PATH}" "$@" 2>/dev/null); then
				printf '%s' "${out:-$default}"
			else
				printf '%s' "$default"
			fi
		}

		# https://github.com/HyDE-Project/HyDE/blob/master/Scripts/version.sh
		dotfiles::print_version() {
			local dotfiles_install_dir
			local dotfiles_branch
			local dotfiles_remote
			local dotfiles_version
			local dotfiles_commit_hash
			local dotfiles_version_commit_msg
			local -r dotfiles_version_last_checked=$(date +%Y-%m-%d\ %H:%M:%S\ %Z) || dotfiles_version_last_checked="<unknown>"

			dotfiles_install_dir=$(dotfiles::git_or_unknown "<unknown>" rev-parse --show-toplevel)
			dotfiles_branch=$(dotfiles::git_or_unknown "<unknown>" rev-parse --abbrev-ref HEAD)
			dotfiles_remote=$(dotfiles::git_or_unknown "<unknown>" config --get remote.origin.url)
			dotfiles_version=$(dotfiles::git_or_unknown "<unknown>" describe --tags --always)
			dotfiles_commit_hash=$(dotfiles::git_or_unknown "<unknown>" rev-parse HEAD)
			dotfiles_version_commit_msg=$(dotfiles::git_or_unknown "<unknown>" log -1 --pretty=%B)

			cat <<EOF
dotfiles ${dotfiles_version} built from branch ${dotfiles_branch} at commit ${dotfiles_commit_hash:0:12} ($dotfiles_version_commit_msg)
Date: ${dotfiles_version_last_checked}
Repository: ${dotfiles_install_dir}
Remote: ${dotfiles_remote}

EOF
		}

		dotfiles::print_modules() {
			dotfiles::set_available_modules

			local -a manifest_sources=()
			local -a manifest_dests=()
			local -a manifest_ftypes=()
			if [[ -f "${MANIFEST}" ]]; then
				local _src
				local _dest
				local _ftype
				while IFS=$'\t' read -r _src _dest _ftype; do
					[[ -n "${_src}" ]] && {
						manifest_sources+=("${_src}")
						manifest_dests+=("${_dest}")
						manifest_ftypes+=("${_ftype}")
					}
				done <"${MANIFEST}"
			fi

			dotfiles::println
			dotfiles::println 'AVAILABLE MODULES'
			dotfiles::println

			local current_category=""
			#local current_module_dir=""
			local category
			#local module_dir
			local src_file
			local filename

			for item in "${AVAILABLE_MODULES[@]}"; do
				category="${item%%/*}"
				#module_dir="${item%/*}"
				src_file="${MODULE_DIR}/${item}"
				filename="${item##*/}"
				filename="${filename%.gen}" # remove .gen

				# category header
				if [[ "$category" != "$current_category" ]]; then
					#[[ -n "$current_category" ]] && dotfiles::println
					dotfiles::println "${category}"
					current_category="${category}"
					#current_module_dir=""
				fi

				# # sub-directory header (once per group)
				# if [[ "$module_dir" != "$current_module_dir" ]]; then
				# 	printf '  %s:\n' "${module_dir#*/}"
				# 	current_module_dir="${module_dir}"
				# fi

				local status="✗"
				local i
				for i in "${!manifest_sources[@]}"; do
					if [[ "${manifest_sources[$i]}" == "$src_file" ]]; then
						local dest="${manifest_dests[$i]}"
						local ftype="${manifest_ftypes[$i]}"

						case "${ftype}" in
						merged)
							if [[ -f "$dest" ]]; then
								status="✓"
							else
								status="!"
							fi
							;;
						generated)
							if [[ -f "$dest" && -s "$dest" ]]; then
								status="✓"
							elif [[ -f "$dest" ]]; then
								status="!"
							fi
							;;
						symlink)
							if [[ -L "$dest" && -e "$dest" ]]; then
								status="✓"
							elif [[ -L "$dest" ]]; then
								status="!"
							fi
							;;
						*)
							dotfiles::println 'Error: invalid type %s' "${ftype}"
							exit 1
							;;
						esac
						break
					fi
				done

				# fallback check disk directly
				if [[ "${status}" == "✗" ]]; then
					local resolved_dest
					if resolved_dest="$(dotfiles::resolve_dest "${src_file}")"; then
						if [[ "${src_file}" == *.gen ]]; then
							# generated: healthy if output exists and is non-empty
							if [[ -f "${resolved_dest}" && -s "${resolved_dest}" ]]; then
								status="✓"
							elif [[ -f "${resolved_dest}" ]]; then
								status="!"
							fi
						elif [[ -L "${resolved_dest}" ]]; then
							if [[ -e "${resolved_dest}" ]]; then
								status="✓"
							else
								status="!"
							fi
						elif [[ -f "${resolved_dest}" ]]; then
							status="✓" # merged/copy file exists
						fi
					fi
				fi

				#printf '    (%s) %s\n' "$status" "$filename"
				printf '  (%s) %s\n' "$status" "$filename"

			done
			dotfiles::println
		}

		dotfiles::print_backups() {
			local -r num_print="${1:-${DEFAULT_NUM_BACKUP_PRINT}}"
			local -r base="${DOTFILES_CACHE_DIR}/backups"

			if [[ ! -d "${base}" ]]; then
				dotfiles::println 'No backups found.'
				return 0
			fi

			# collect YYYY-MM-DD dirs, sorted newest first
			local -a days=()
			local -a runs=()

			while IFS= read -r day; do
				days+=("$day")
			done < <(find "${base}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)

			local day time
			for day in "${days[@]}"; do
				while IFS= read -r time; do
					runs+=("${day##*/}/${time##*/}")
				done < <(find "${day}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
			done

			if [[ ${#runs[@]} -eq 0 ]]; then
				dotfiles::println 'No backup runs found.'
				return 0
			fi

			local total_runs="${#runs[@]}"

			# Cap the runs array to the max number specified by num_print
			if [[ ${total_runs} -gt ${num_print} ]]; then
				runs=("${runs[@]:0:num_print}")
			fi

			if [[ ${total_runs} -gt ${num_print} ]]; then
				dotfiles::println 'AVAILABLE BACKUPS (Showing latest %d of %d runs):' "${#runs[@]}" "${total_runs}"
			else
				dotfiles::println 'AVAILABLE BACKUPS %d run(s):' "${#runs[@]}"
			fi
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
			if [[ ! -f "${MANIFEST}" ]]; then
				dotfiles::println '  [verify] No manifest found. Nothing to verify.'
				return 0
			fi

			local -a broken_merged_files=()
			local -a broken_generated_files=()
			local -a broken_symlink_files=()

			local broke_merged=0
			local broke_generated=0
			local broke_symlink=0

			local ok_merged=0
			local ok_generated=0
			local ok_symlink=0

			local src
			local dest

			while IFS=$'\t' read -r src dest ftype; do
				[[ -z "${dest}" ]] && continue
				case "${ftype}" in
				merged)
					# healthy if file exists and has both sentinels
					if [[ -f "${dest}" ]] &&
						grep -qxF "${MERGE_TOP_SENTINEL}" "${dest}" &&
						grep -qxF "${MERGE_BOTTOM_SENTINEL}" "${dest}"; then
						ok_merged=$((ok_merged + 1))
					else
						broken_merged_files+=("${dest}")
						dotfiles::println '  [merged] %s (missing or broken sentinels)' "${dest}" >&2
					fi
					;;
				generated)
					if [[ -f "${dest}" && -s "${dest}" ]]; then
						ok_generated=$((ok_generated + 1))
					else
						broken_generated_files+=("${dest}")
						dotfiles::println '  [generated] %s (missing or empty)' "${dest}" >&2
					fi
					;;
				symlink)
					if [[ -L "${dest}" && -e "${dest}" && "$(readlink "${dest}")" == "${src}" ]]; then
						ok_symlink=$((ok_symlink + 1))
					else
						broken_symlink_files+=("${dest}")
						dotfiles::println '  [symlink] %s (broken or incorrect target)' "${dest}" >&2
					fi
					;;
				*)
					dotfiles::println 'Error: invalid type detected: %s' "${ftype}" >&2
					exit 1
					;;
				esac
			done <"${MANIFEST}"

			broke_symlink="${#broken_symlink_files[@]}"
			broke_merged="${#broken_merged_files[@]}"
			broke_generated="${#broken_generated_files[@]}"

			local total_broken=$((broke_symlink + broke_merged + broke_generated))
			local total_ok=$((ok_merged + ok_generated + ok_symlink))
			local total=$((total_broken + total_ok))

			if [[ ${total_broken} -eq 0 ]]; then
				dotfiles::println '  [verify] OK: All %d files verified successfully.' "${total_ok}"
				dotfiles::println '           (%d symlinks, %d generated, %d merged)' "${ok_symlink}" "${ok_generated}" "${ok_merged}"
				return 0
			else
				dotfiles::println '  [verify] NOT OK: %d out of %d files are broken.' "${total_broken}" "${total}" >&2
				dotfiles::println '           Symlinks  : %2d OK, %2d broken' "${ok_symlink}" "${broke_symlink}" >&2
				dotfiles::println '           Generated : %2d OK, %2d broken' "${ok_generated}" "${broke_generated}" >&2
				dotfiles::println '           Merged    : %2d OK, %2d broken' "${ok_merged}" "${broke_merged}" >&2
				dotfiles::println >&2
				dotfiles::println '  [verify] Broken File Details:' >&2
				# print exactly which files are broken
				if [[ "${broke_symlink}" -gt 0 ]]; then
					for f in "${broken_symlink_files[@]}"; do
						printf '    - [symlink]   %s (broken or incorrect target)\n' "${f}" >&2
					done
				fi

				if [[ "${broke_generated}" -gt 0 ]]; then
					for f in "${broken_generated_files[@]}"; do
						printf '    - [generated] %s (missing or empty)\n' "${f}" >&2
					done
				fi

				if [[ "${broke_merged}" -gt 0 ]]; then
					for f in "${broken_merged_files[@]}"; do
						printf '    - [merged]    %s (missing or broken sentinels)\n' "${f}" >&2
					done
				fi

				echo "" >&2
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
│  Restarting shell...                        │
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

		dotfiles::default_ref() {
			local ref="${DOTFILES_INSTALL_REF:-}"

			if [[ -z "$ref" ]]; then
				ref="$(git -C "${SRC_PATH}" config --local dotfiles.ref 2>/dev/null || true)"
			fi

			printf '%s' "${ref:-main}"
		}

		dotfiles::install_from_git() {
			local -r install_dir="$(dotfiles::install_dir)"
			local -r ref="$(dotfiles::default_ref)"

			# path is not directory
			if [[ -e "${install_dir}" && ! -d "${install_dir}" ]]; then
				dotfiles::println 'Error: path "%s" is not a directory.' "${install_dir}" >&2
				return 1
			fi
			# already cloned
			if [[ -d "${install_dir}/.git" ]]; then
				if [[ -f "${install_dir}/install.sh" ]]; then
					dotfiles::println '=> Existing clone at %s.' "${install_dir}" >&2
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
			command git clone --depth=1 -b "${ref}" "${REPO_URL}" "${install_dir}" || {
				dotfiles::println 'Error: Clone failed for %s (ref: %s)' "${REPO_URL}" "${ref}" >&2
				return 1
			}

			command git -C "${install_dir}" reflog expire --expire=now --all 2>/dev/null || true
			command git -C "${install_dir}" gc --auto --prune=now 2>/dev/null || true

			# restart script with local copy
			dotfiles::println '=> Restarting script with local copy.' # FIXME: stderr?
			exec bash "${install_dir}/install.sh" "$@"
		}

		############
		dotfiles::update() {
			if [[ ! -d "${SRC_PATH}/.git" ]]; then
				dotfiles::println 'Error: %s is not a git clone. Run install first.' "${SRC_PATH}" >&2
				exit 1
			fi

			local has_local_mods=0
			if ! command git -C "${SRC_PATH}" diff --quiet HEAD 2>/dev/null; then
				has_local_mods=1
			fi

			dotfiles::println '=> Updating dotfiles in %s (ref: %s)' "${SRC_PATH}" "${DOTFILES_REF}"

			# block non-dev users with local modifications
			if ((has_local_mods)) && ! dotfiles::is_true "${DOTFILES_LOCAL_MODS}"; then
				{
					printf '\n'
					printf 'Error: You have uncommitted changes in %s:\n' "${SRC_PATH}"
					command git -C "${SRC_PATH}" diff --stat HEAD 2>/dev/null
					printf '\n'
					printf '  This repo is publicly maintained. Do not edit tracked files directly.\n'
					printf '  Use .local override files for personal customisation:\n'
					printf '    e.g.  tmux.conf  ->  tmux.conf.local\n'
					printf '\n'
					printf '  Revert your changes or move them to a .local file, then re-run.\n'
					printf '  (dev: set DOTFILES_LOCAL_MODS=1 to bypass this check)\n'
					printf '\n'
				} >&2
				return 1
			fi

			# fetch
			if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "${DOTFILES_REF}" 2>/dev/null; then
				dotfiles::println 'Error: Fetch failed (ref: %s). Check network or repo URL.' "${DOTFILES_REF}" >&2
				return 1
			fi

			# rebase devs
			if ((has_local_mods)) && dotfiles::is_true "${DOTFILES_LOCAL_MODS}"; then
				dotfiles::println '=> Local modifications detected. Rebasing onto FETCH_HEAD.'
				if ! command git -C "${SRC_PATH}" rebase FETCH_HEAD 2>/dev/null; then
					dotfiles::println 'Error: Rebase failed. Resolve conflicts, then:' >&2
					dotfiles::println '    git -C "%s" rebase --continue' "${SRC_PATH}" >&2
					dotfiles::println '  Or abort with:' >&2
					dotfiles::println '    git -C "%s" rebase --abort' "${SRC_PATH}" >&2
					return 1
				fi
			else
				# Hard reset to the fetched ref.
				# Works for branches, tags, and raw commit SHAs alike.
				if ! command git -C "${SRC_PATH}" reset --hard FETCH_HEAD 2>/dev/null; then
					dotfiles::println 'Error: Reset to %s failed in %s' "${DOTFILES_REF}" "${SRC_PATH}" >&2
					return 1
				fi

				# Optionally keep the local branch pointer in sync (branches only).
				# This is cosmetic; reset --hard already moves the working tree.
				if command git -C "${SRC_PATH}" show-ref --verify --quiet "refs/heads/${DOTFILES_REF}" 2>/dev/null; then
					command git -C "${SRC_PATH}" branch -f "${DOTFILES_REF}" FETCH_HEAD 2>/dev/null || true
				fi
			fi

			return 0
		}

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
			local -r ftype="${3:-symlink}"
			# ensure parent dir exists
			mkdir -p "$(dirname "${MANIFEST}")" 2>/dev/null || true
			# skip if already recorded
			if [[ -f "${MANIFEST}" ]]; then
				if awk -F'\t' -v d="${dest}" '$2 == d { found=1; exit } END { exit found ? 0 : 1 }' "${MANIFEST}"; then
					return 0
				fi
			fi

			printf '%s\t%s\t%s\n' "${source}" "${dest}" "${ftype}" >>"${MANIFEST}"
		}

		# Remove a dest entry from the manifest.
		# Usage: dotfiles::manifest_remove <dest>
		dotfiles::manifest_remove() {
			local -r dest="$1"

			[[ -f "${MANIFEST}" ]] || return 0

			local tmp
			tmp="$(mktemp "${MANIFEST}.tmp.XXXXXX")"
			if ! command awk -F'\t' -v d="${dest}" '$2 != d' "${MANIFEST}" >"${tmp}"; then
				rm -f "${tmp}"
				return 1
			fi

			mv -- "${tmp}" "${MANIFEST}" # NOTE: i have alias '--'

			return 0
		}

		# Remove all manifest entries (called after a full clean).
		# Usage: dotfiles::clear
		dotfiles::manifest_clear() {
			[[ -f "${MANIFEST}" ]] || return 0
			: >"${MANIFEST}"
		}
	}

	#############################
	# windows
	{
		# detect if windows user has sudo enabled
		dotfiles::set_windows_sudo() {
			[[ -n "${WINDOWS_SUDO:-}" ]] && return 0

			command -v sudo >/dev/null 2>&1 || return 0
			command -v reg.exe >/dev/null 2>&1 || return 0 # NOTE: redundant?

			local sudo_reg
			sudo_reg=$(MSYS_NO_PATHCONV=1 reg.exe query "${WINDOWS_SUDO_REG_LOC}" /v Enabled 2>/dev/null)
			# output of 0x1, 0x2, or 0x3 means enabled
			if [[ "${sudo_reg}" =~ 0x[1-3] ]]; then
				readonly WINDOWS_SUDO=0
			else
				readonly WINDOWS_SUDO=1
			fi

			return 0
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

			# NOTE: adding exec makes it auto close
			local rc=0
			"${PWSH_CMD}" "${ps_args[@]}" || rc=$?

			echo
			read -rn 1 -p "Press any key to exit..."
			exit "${rc}"
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
			local -a managed=()
			local -a managed_generated=()
			local -a orphans=()
			local src
			local dest

			# manifest entries
			if [[ -f "${MANIFEST}" ]]; then
				while IFS=$'\t' read -r src dest ftype; do
					[[ -z "${dest}" ]] && continue
					# merged files always stay
					[[ "${ftype:-symlink}" == "merged" ]] && continue
					case "${ftype:-symlink}" in
					generated)
						managed_generated+=("${dest}")
						;;
					*)
						managed+=("${dest}")
						;;
					esac
				done <"${MANIFEST}"
			fi

			# safety net: orphaned symlinks pointing into $SRC_PATH
			local -a scan_dirs=("$HOME" "$HOME/.ssh")
			if [[ "${TARGET_OS:-}" == "${OS_MAC}" ]]; then
				scan_dirs+=("$HOME/Library/Application Support/iTerm2")
			fi

			local dir link target
			for dir in "${scan_dirs[@]}"; do
				[[ -d "$dir" ]] || continue
				while IFS= read -r -d '' link; do
					target="$(readlink "$link" 2>/dev/null)" || continue
					[[ "$target" == "${SRC_PATH}/"* ]] || continue
					local in_manifest=0
					for d in "${managed[@]}"; do
						[[ "$d" == "$link" ]] && in_manifest=1 && break
					done
					((in_manifest)) || orphans+=("${link}")
				done < <(find "$dir" -maxdepth 2 -type l -print0 2>/dev/null)
			done

			local total_symlinks=$((${#managed[@]} + ${#orphans[@]}))
			local total=$((total_symlinks + ${#managed_generated[@]}))
			if [[ ${total} -eq 0 ]]; then
				dotfiles::println '  [clean] No managed files found.'
				return 0
			fi

			dotfiles::println '  [clean] Found %d symlink(s), %d generated file(s).' \
				"${total_symlinks}" "${#managed_generated[@]}"

			local removed=0
			local failed=0
			local already_gone=0

			# remove symlinks (managed + orphans)
			local -a all_links=("${managed[@]}" "${orphans[@]}")
			for link in "${all_links[@]}"; do
				if [[ ! -L "$link" ]]; then
					already_gone=$((already_gone + 1))
					continue
				fi
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

			# remove generated files (real files, not symlinks)
			for dest in "${managed_generated[@]}"; do
				if [[ ! -f "$dest" ]]; then
					already_gone=$((already_gone + 1))
					continue
				fi
				printf '    %s (generated)\n' "$dest"

				if ((DRY_RUN)); then
					dotfiles::println '    [dry-run] rm %s' "$dest"
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
						dotfiles::println '    [skip] %s (user declined)' "$dest"
						continue
						;;
					esac
				fi

				if rm -f "$dest" 2>/dev/null; then
					dotfiles::manifest_remove "$dest"
					removed=$((removed + 1))
				else
					dotfiles::println 'Error: cannot remove %s' "$dest" >&2
					failed=$((failed + 1))
				fi
			done

			dotfiles::println '  [clean] Removed %d, skipped %d (already gone), failed %d.' \
				"${removed}" "${already_gone}" "${failed}"
			if ((failed > 0)); then
				return 1
			fi
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
			local -r days="${CLEAN_BACKUPS_DAYS}"

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

			# FIX (style): was a fragile $([[ ]] && printf ...) inline substitution.
			local suffix=""
			if [[ "${days}" != "0" ]]; then
				suffix=" older than ${days} day(s)"
			fi
			dotfiles::println '  [clean-logs] Removed %d log file(s)%s.' "${removed}" "${suffix}"
			return 0
		}

		dotfiles::repair_symlink() {
			printf "\n\nFIXME: broken\n\n"
			# TODO: check manifest -> compare to installed/symlink modules
			local -a orphans=()
			local src
			local dest

			# pass 1: find broken symlinks (link exists, target gone)
			if [[ -f "${MANIFEST}" ]]; then
				while IFS=$'\t' read -r src dest ftype; do
					[[ -z "${dest}" ]] && continue
					[[ "${ftype:-symlink}" == "merged" ]] && continue
					[[ "${ftype:-symlink}" == "generated" ]] && continue
					if [[ -L "${dest}" && ! -e "${dest}" ]]; then
						orphans+=("${dest}")
					fi
				done <"${MANIFEST}"
			fi

			# remove orphans
			if [[ ${#orphans[@]} -gt 0 ]]; then
				dotfiles::println '  [repair] Removing %d broken symlink(s):' "${#orphans[@]}"
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
				dotfiles::println '  [repair] Removed %d orphan(s).' "$removed"
			fi

			# pass 2: check all files, dispatch by type
			local -a to_relink=()
			local -a to_regen=()
			local -a to_remerge=()
			local base

			for source in "${FILES_TO_CHECK[@]}"; do
				base="${source##*/}"

				if ! dest="$(dotfiles::resolve_dest "${source}")"; then
					continue
				fi

				# generated: re-run if output missing or empty
				if [[ "${base}" == *.gen ]]; then
					if [[ ! -f "${dest}" || ! -s "${dest}" ]]; then
						to_regen+=("${source}")
					fi
					continue
				fi

				# merged: re-merge if file missing or sentinels absent
				if [[ "${base}" == *.local || "${base}" == *.local.* ]]; then
					if [[ ! -f "${dest}" ]] ||
						! grep -qxF "${MERGE_TOP_SENTINEL}" "${dest}" 2>/dev/null; then
						to_remerge+=("${source}")
					fi
					continue
				fi

				# symlink: existing healthy check
				if [[ -L "${dest}" && -e "${dest}" && "$(readlink "${dest}")" == "${source}" ]]; then
					if ! ((DRY_RUN)); then
						dotfiles::manifest_add "${source}" "${dest}" "symlink"
					fi
					continue
				fi

				# real file at a symlink dest — user file, not managed
				if [[ -f "${dest}" && ! -L "${dest}" ]]; then
					dotfiles::println '  [skip] %s (user file, not managed)' "${dest}"
					continue
				fi

				# broken symlink (not ours) — safe to remove and re-link
				if [[ -L "${dest}" && ! -e "${dest}" ]]; then
					if ((DRY_RUN)); then
						dotfiles::println '    [dry-run] rm broken symlink %s' "${dest}"
					else
						rm -f "${dest}"
					fi
				fi

				to_relink+=("${source}")
			done

			# pass 3: relink
			local ok=0
			local failed=0

			if [[ ${#to_relink[@]} -gt 0 ]]; then
				dotfiles::println '  [repair] Relinking %d file(s)...' "${#to_relink[@]}"
				for source in "${to_relink[@]}"; do
					dest="$(dotfiles::resolve_dest "${source}")" || continue
					if dotfiles::symlink_file "${source}" "${dest}"; then
						ok=$((ok + 1))
					else
						failed=$((failed + 1))
					fi
				done
				dotfiles::println '  [repair] Symlinks: %d ok, %d failed.' "${ok}" "${failed}"
			fi

			# pass 4: regenerate
			if [[ ${#to_regen[@]} -gt 0 ]]; then
				dotfiles::println '  [repair] Regenerating %d file(s)...' "${#to_regen[@]}"
				local regen_ok=0
				local regen_failed=0
				for source in "${to_regen[@]}"; do
					dest="$(dotfiles::resolve_dest "${source}")" || continue
					if dotfiles::generate_file "${source}" "${dest}"; then
						regen_ok=$((regen_ok + 1))
					else
						regen_failed=$((regen_failed + 1))
					fi
				done
				dotfiles::println '  [repair] Generated: %d ok, %d failed.' "${regen_ok}" "${regen_failed}"
				failed=$((failed + regen_failed))
			fi

			# pass 5: re-merge
			if [[ ${#to_remerge[@]} -gt 0 ]]; then
				dotfiles::println '  [repair] Re-merging %d file(s)...' "${#to_remerge[@]}"
				local merge_ok=0
				local merge_failed=0
				for source in "${to_remerge[@]}"; do
					dest="$(dotfiles::resolve_dest "${source}")" || continue
					if dotfiles::copy_file "${source}" "${dest}"; then
						merge_ok=$((merge_ok + 1))
					else
						merge_failed=$((merge_failed + 1))
					fi
				done
				dotfiles::println '  [repair] Merged: %d ok, %d failed.' "${merge_ok}" "${merge_failed}"
				failed=$((failed + merge_failed))
			fi

			# summary
			if [[ ${#to_relink[@]} -eq 0 && ${#to_regen[@]} -eq 0 && ${#to_remerge[@]} -eq 0 ]]; then
				dotfiles::println '  [repair] All managed files are healthy.'
			fi

			if ((failed > 0)); then
				return 1
			fi
			return 0
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
			local -r name="${1:-}"
			local -r run="${2:-}"
			local -r base="${DOTFILES_CACHE_DIR}/backups"
			local -r backup_src="${base}/${run}/${name}.bak"

			if [[ ! -f "${backup_src}" ]]; then
				dotfiles::println 'Error: no backup of "%s" in run %s.' "${name}" "${run}" >&2
				return 1
			fi

			# Determine destination from manifest, fall back to $HOME/<name>
			local dest="${HOME}/${name}"
			local src=""
			if [[ -f "${MANIFEST}" ]]; then
				local _dest
				local _ftype
				while IFS=$'\t' read -r _src _dest _ftype; do
					if [[ "${_dest##*/}" == "${name}" ]]; then
						dest="${_dest}"
						break
					fi
				done <"${MANIFEST}"
			fi

			dotfiles::println '  [restore] %s -> %s' "${backup_src}" "${dest}"

			# handle existing destination

			if [[ -L "${dest}" ]]; then
				local link_target
				link_target="$(readlink "${dest}" 2>/dev/null)"

				if [[ "${link_target}" == "${SRC_PATH}/"* ]]; then
					# Managed symlink pointing into our repo — remove it
					if ((DRY_RUN)); then
						dotfiles::println '    [dry-run] rm symlink %s' "${dest}"
					else
						rm -f "${dest}"
						dotfiles::manifest_remove "${dest}"
					fi
				elif [[ ! -e "${dest}" ]]; then
					# Broken symlink pointing elsewhere — safe to remove
					if ((DRY_RUN)); then
						dotfiles::println '    [dry-run] rm broken symlink %s' "${dest}"
					else
						rm -f "${dest}"
					fi
				else
					# Valid symlink pointing elsewhere — do NOT overwrite
					dotfiles::println 'Error: %s is a valid symlink to %s. Refusing to overwrite.' "${dest}" "${link_target}" >&2
					return 1
				fi
			elif [[ -e "${dest}" ]]; then
				# Regular file at dest — back it up before replacing
				if ! dotfiles::backup_file "${dest}"; then
					return 1
				fi
			fi

			# copy backup into place
			if ((DRY_RUN)); then
				dotfiles::println '    [dry-run] cp %s %s' "${backup_src}" "${dest}"
			else
				if ! cp "${backup_src}" "${dest}"; then
					dotfiles::println 'Error: cannot restore %s to %s.' "${backup_src}" "${dest}" >&2
					return 1
				fi
			fi

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
					printf '%s' "${run#"${base}"/}"
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
			# trim whitespace
			m="${m#"${m%%[![:space:]]*}"}"
			m="${m%"${m##*[![:space:]]}"}"
			[[ -z "$m" ]] && continue

			valid=0
			if [[ "$m" == */* ]]; then
				for mod in "${AVAILABLE_MODULES[@]}"; do
					if [[ "$mod" == "$m" || "$mod" == "$m/"* ]]; then
						valid=1
						break
					fi
				done
			else
				for mod in "${AVAILABLE_MODULES[@]}"; do
					[[ "${mod%%/*}" == "$m" ]] && valid=1 && break
				done
			fi

			if [[ $valid -eq 0 ]]; then
				dotfiles::println 'Error: Unknown module "%s".' "$m" >&2
				dotfiles::println '  Run with --list to see valid module names.' >&2
				exit 2
			fi
			arr+=("$m")
		done
	}

	# Warn about merged/local files that still exist on disk.
	# Primary source: COPY_FILES (readonly, set by set_file_types in main).
	# Secondary source: manifest "merged" entries (in case manifest survived
	#   a failed clean_symlinks and contains entries no longer in COPY_FILES).
	#
	# Precondition:
	#   COPY_FILES is populated (or empty). MANIFEST may or may not exist.
	#
	# Returns: always 0 (informational only)
	dotfiles::detect_local_files() {
		local -a remaining=()
		local src
		local dest

		# in-memory: COPY_FILES
		if [[ ${#COPY_FILES[@]} -gt 0 ]]; then
			for src in "${COPY_FILES[@]}"; do
				if dest="$(dotfiles::resolve_dest "${src}")"; then
					[[ -f "${dest}" ]] && remaining+=("${dest}")
				fi
			done
		fi

		# manifest: merged entries (fallback)
		if [[ -f "${MANIFEST}" ]]; then
			local _src _dest _ftype
			while IFS=$'\t' read -r _src _dest _ftype; do
				if [[ "${_ftype:-}" == "merged" && -f "${_dest}" ]]; then
					remaining+=("${_dest}")
				fi
			done <"${MANIFEST}"
		fi

		# de-duplicate
		local -a unique=()
		local _f _u dup
		for _f in "${remaining[@]}"; do
			dup=0
			for _u in "${unique[@]}"; do
				[[ "${_u}" == "${_f}" ]] && dup=1 && break
			done
			((dup)) || unique+=("${_f}")
		done

		if [[ ${#unique[@]} -gt 0 ]]; then
			dotfiles::println ''
			dotfiles::println '  Note: merged file(s) with user data remain on disk:'
			for _f in "${unique[@]}"; do
				dotfiles::println '    %s' "${_f}"
			done
			dotfiles::println '  These may contain personal credentials. Remove them manually if no longer needed.'
		fi

		return 0
	}

	dotfiles::clean_installs() {
		dotfiles::clean_symlinks || return 1
		dotfiles::detect_local_files
	}

	dotfiles::install() {
		dotfiles::println "=== Beginning install ==="
		local rc=0

		dotfiles::symlink_all || rc=1
		dotfiles::copy_all || rc=1
		dotfiles::generate_all || rc=1

		if ((rc)); then
			dotfiles::println '=> Install finished with errors!' >&2
			return 1
		fi
		dotfiles::println '=== Install complete ==='
	}

	dotfiles::uninstall() {
		dotfiles::println "=== Beginning uninstall ==="
		local rc=0

		if ((NOCONFIRM)); then
			: # -y / --noconfirm: skip prompt
		elif ((DRY_RUN)); then
			: # dry-run: nothing will be modified, no prompt needed
		else
			local choice
			dotfiles::println 'This will remove all managed files (symlinks, generated files),' \
				'backups, logs, the manifest, and the dotfiles clone.' >&2
			while true; do
				if ! read -r -p 'Do you really want to uninstall? [y/N]: ' choice; then
					dotfiles::println 'Error: No input available for prompt.' >&2
					return 1
				fi
				case "${choice}" in
				[yY])
					break
					;;
				[nN])
					dotfiles::println 'Aborting uninstallation!' >&2
					exit 130
					;;
				*)
					dotfiles::println 'Error: Invalid input. Please enter y or n.' >&2
					;;
				esac
			done
		fi

		# remove symlinks (and warn about merged/generated files that remain)
		dotfiles::clean_symlinks || rc=1

		# remove generated files (tool-owned, no personal data)
		if [[ ${#GENERATE_FILES[@]} -gt 0 ]]; then
			local src dest
			for src in "${GENERATE_FILES[@]}"; do
				if ! dest="$(dotfiles::resolve_dest "${src}")"; then
					continue
				fi
				if [[ -f "${dest}" ]]; then
					dotfiles::println '  [uninstall] removing generated: %s' "${dest}"
					if ((DRY_RUN)); then
						: # dry-run: nothing to do
					else
						rm -f "${dest}" 2>/dev/null || {
							dotfiles::println 'Warning: could not remove %s' "${dest}" >&2
						}
						dotfiles::manifest_remove "${dest}"
					fi
				fi
			done
		fi

		# warn about merged files (contain user data, NOT removed)
		dotfiles::detect_local_files

		if ((DRY_RUN)); then
			dotfiles::println '  [dry-run] rm -rf %s' "${SRC_PATH}"
		else
			dotfiles::manifest_clear
			dotfiles::println '=> Removing clone at %s' "${SRC_PATH}"
			if ((rc)); then
				dotfiles::prompt_continue '=> Errors occurred before reaching final uninstall'
			fi
			if ! rm -rf "${SRC_PATH}"; then
				dotfiles::println 'Error: cannot remove %s' "${SRC_PATH}" >&2
				rc=1
			fi
			# remove cache (backups, manifest) and logs
			if [[ -d "${DOTFILES_CACHE_DIR}" ]]; then
				dotfiles::println '=> Removing cache at %s' "${DOTFILES_CACHE_DIR}"
				rm -rf "${DOTFILES_CACHE_DIR}" 2>/dev/null || true
			fi
			if [[ -d "${DOTFILES_LOG_DIR}" ]]; then
				dotfiles::println '=> Removing logs at %s' "${DOTFILES_LOG_DIR}"
				rm -rf "${DOTFILES_LOG_DIR}" 2>/dev/null || true
			fi
		fi

		if ((rc)); then
			dotfiles::println '=> Uninstall finished with errors!' >&2
			return 1
		fi

		dotfiles::println '=== Uninstall complete ==='
	}

	dotfiles::argparse() {
		UNINSTALL=0
		# setup
		DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-${HOME}/dotfiles}"
		DOTFILES_REF="$(dotfiles::default_ref)"
		# behaviour
		DOTFILES_AUTORESTART="${DOTFILES_AUTORESTART:-0}"
		DOTFILES_LOG="${DOTFILES_LOG:-1}"

		DRY_RUN=0
		FORCE=0
		UPDATE=0
		UPDATE_ONLY=0
		INTERACTIVE=0
		NO_BACKUP=0
		NO_DEPS=0
		NO_HOOKS=0
		NOCONFIRM=0
		VERBOSE=0
		QUIET=0
		MODE=""
		REPAIR_SYMLINKS=0
		CLEAN_BACKUPS_DAYS=""
		CLEAN_LOGS_DAYS=""
		LOG_LEVEL="info"
		INCLUDE_MODULES=()
		EXCLUDE_MODULES=()
		# restore
		RESTORE_FILES=()
		RESTORE_ALL=0
		RESTORE_FROM=""
		# backup
		BACKUP_FILES=()
		DO_BACKUP=0

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
			--examples)
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
			# cleaning
			-r | --repair)
				REPAIR_SYMLINKS=1
				shift
				;;
			--reset)
				dotfiles::assign_mode "--reset" "reset"
				shift
				;;
			-b | --backup) # FIXME: delete
				DO_BACKUP=1
				shift
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					:
				else
					shift
					while [[ $# -gt 0 && "$1" != -* ]]; do
						BACKUP_FILES+=("$1")
						shift
					done
					#dotfiles::check_exists "${BACKUP_FILES[@]}"
				fi
				;;
			--clean-backups)
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					CLEAN_BACKUPS_DAYS="7"
					shift
				else
					if ! [[ "$2" =~ ^[0-9]+$ ]]; then
						dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
						exit 1
					fi
					CLEAN_BACKUPS_DAYS="$2"
					shift 2
				fi
				;;
			--clean-backups=*)
				if ! [[ "${1#*=}" =~ ^[0-9]+$ ]]; then
					dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "--clean-backups" "${1#*=}" >&2
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
						dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
						exit 1
					fi
					CLEAN_LOGS_DAYS="$2"
					shift 2
				fi
				;;
			--clean-logs=*)
				if ! [[ "${1#*=}" =~ ^[0-9]+$ ]]; then
					dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "--clean-logs" "${1#*=}" >&2
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
				UNINSTALL=1
				shift
				;;

			# modules
			-i | --include)
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
					exit 1
				fi
				dotfiles::parse_module_list "$2" INCLUDE_MODULES
				shift 2
				;;
			-i=* | --include=*)
				dotfiles::parse_module_list "${1#*=}" INCLUDE_MODULES
				shift
				;;
			-x | --exclude)
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
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

			# git
			-p | --pull)
				UPDATE_ONLY=1
				shift
				;;
			--ref)
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
					exit 1
				fi
				DOTFILES_REF="$2"
				shift 2
				;;
			--ref=*)
				DOTFILES_REF="${1#*=}"
				shift
				;;

			# restore
			--restore)
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
					exit 2
				else
					shift
					while [[ $# -gt 0 && "$1" != -* ]]; do
						RESTORE_FILES+=("$1")
						shift
					done
					#dotfiles::check_exists "${RESTORE_FILES[@]}"
				fi
				;;
			--restore-all)
				RESTORE_ALL=1
				shift
				;;
			--from)
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
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
				if [[ -z "${2:-}" || "$2" == -* ]]; then
					:
				else
					if ! [[ "$2" =~ ^[0-9]+$ ]]; then
						dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
						exit 1
					fi
				fi
				dotfiles::print_backups "${2:-${DEFAULT_NUM_BACKUP_PRINT}}"
				exit 0
				;;
			--backup-list=*)
				if ! [[ "${1#*=}" =~ ^[0-9]+$ ]]; then
					dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "--backup-list" "${1#*=}" >&2
					exit 1
				fi
				dotfiles::print_backups "$1"
				exit 0
				;;

			# behaviour
			-n | --dry-run)
				DRY_RUN=1
				shift
				;;
			-I | --interactive)
				if [[ "${NOCONFIRM}" -eq 1 ]]; then
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
				NOCONFIRM=1
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
					dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
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
				dotfiles::println 'Error: Invalid parameter "%s"' "$1" >&2
				dotfiles::println "Run \`bash %s --help\` for valid options." "$(basename "$0")" >&2
				exit 1
				;;
			esac
		done

		if ((UNINSTALL)); then
			dotfiles::uninstall || {
				cat <<EOF
  You can attempt to run the uninstallation again. If it continues to fail, you may need to
  manually delete all relevant directories:
    Install   |  \""${SRC_PATH}"\"
	Log       |  \""${DOTFILES_LOG_DIR}"\"
	Cache     |  \""${DOTFILES_CACHE_DIR}"\"

EOF
				exit 1
			}
			exit 0

		fi

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
			if [[ ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
				dotfiles::println 'Error: --clean-* is not valid with --include.' >&2
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
			if [[ ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
				dotfiles::println 'Error: --restore is not valid with --include.' >&2
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

		if [[ "$MODE" != "install" && ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --include is not valid with --%s.' "$MODE" >&2
			exit 1
		fi
		if [[ "$MODE" != "install" && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --exclude is not valid with --%s.' "$MODE" >&2
			exit 1
		fi
		if [[ ${#INCLUDE_MODULES[@]} -gt 0 && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
			dotfiles::println 'Error: --include and --exclude are mutually exclusive.' >&2
			exit 1
		fi
	}

	# Builds the final list of absolute file paths to process.
	# Filters AVAILABLE_MODULES based on --install / --exclude, then
	# prepends SRC_PATH to produce absolute paths.
	#
	# Precondition:
	#   AVAILABLE_MODULES is populated (and readonly).
	#   INCLUDE_MODULES / EXCLUDE_MODULES are populated by argparse.
	#
	# Postcondition:
	#   FILES_TO_CHECK is a readonly array of absolute paths.
	dotfiles::set_files_to_check() {
		FILES_TO_CHECK=()
		local mod
		local inc
		local exc

		for mod in "${AVAILABLE_MODULES[@]}"; do
			# ── --install filter: only include listed modules ──
			if [[ ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
				local included=0
				for inc in "${INCLUDE_MODULES[@]}"; do
					if [[ "${mod}" == "${inc}" || "${mod}" == "${inc}/"* ]]; then
						included=1
						break
					fi
				done
				((included)) || continue
			fi

			# ── --exclude filter: skip listed modules ──
			if [[ ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
				local excluded=0
				for exc in "${EXCLUDE_MODULES[@]}"; do
					if [[ "${mod}" == "${exc}" || "${mod}" == "${exc}/"* ]]; then
						excluded=1
						break
					fi
				done
				((excluded)) && continue
			fi

			FILES_TO_CHECK+=("${MODULE_DIR}/${mod}")
		done

		declare -r FILES_TO_CHECK
	}

	# Classifies FILES_TO_CHECK into SYMLINK_FILES, COPY_FILES, or GENERATE_FILES.
	# Rule: basename ending in ".local" → copy/merge; everything else → symlink.
	#
	# Precondition:
	#   FILES_TO_CHECK is populated (readonly).
	#
	# Postcondition:
	#   SYMLINK_FILES  = readonly array of absolute paths (for symlink_all)
	#   COPY_FILES     = readonly array of absolute paths (for copy_all)
	#   GENERATE_FILES = readonly array of absolute paths (for generate_all)
	dotfiles::set_file_types() {
		[[ -n "${SYMLINK_FILES:-}" || -n "${COPY_FILES:-}" || -n "${GENERATE_FILES:-}" ]] && return 0

		SYMLINK_FILES=()
		COPY_FILES=()
		GENERATE_FILES=()

		local file
		local base
		for file in "${FILES_TO_CHECK[@]}"; do
			base="${file##*/}"
			if [[ "${base}" == *.local || "${base}" == *.local.* ]]; then
				COPY_FILES+=("${file}")
			elif [[ "${base}" == *.gen ]]; then
				GENERATE_FILES+=("${file}")
			else
				SYMLINK_FILES+=("${file}")
			fi
		done
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

		declare -r MODULE_DIR="${SRC_PATH}/modules"
		if [[ ! -d "${MODULE_DIR}" ]]; then
			dotfiles::println "Error: unable to locate modules/."
			exit 1
		fi

		dotfiles::set_env || { # TARGET_OS & TARGET_RUNTIME
			dotfiles::println 'Warning: unable to determine $TARGET_OS or $TARGET_RUNTIME.'
			dotfiles::prompt_continue "Some functionality may be limited."
		}
		if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
			dotfiles::set_windows_sudo || true
			export MSYS=winsymlinks:nativestrict # enable native symlinking
		fi
		dotfiles::set_elevated          # IS_ELEVATED
		dotfiles::set_available_modules # AVAILABLE_MODULES

		#FIXME: ^^^^^^init^^^^^^

		local -r src_dir="${SRC_PATH}/src"
		local -r -a src_files=(
			"${src_dir}/filesystem.sh"
		)
		dotfiles::check_exists "${src_files[@]}" || exit 1
		dotfiles::source_file "${src_dir}/filesystem.sh" || exit 1

		dotfiles::argparse "$@"
		if dotfiles::is_true "${DOTFILES_LOG}"; then
			echo "TODO: init logging"
		fi

		dotfiles::print_banner

		if [[ "${UPDATE}" -eq 1 || "${UPDATE_ONLY}" -eq 1 ]]; then
			if dotfiles::update; then
				dotfiles::println '=> Successfully updated!'

				if ((UPDATE_ONLY)); then
					exit 0
				fi
			else
				if ((UPDATE_ONLY)); then
					printf "\nExiting...\n"
					exit 0
				else
					dotfiles::prompt_continue
				fi
			fi
		fi

		# switch to native powershell if non sudo windows bash
		if ! dotfiles::is_true "${DOTFILES_IGNORE_HANDOFF:-}"; then
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
		fi

		# figure out what files are needed based on args
		dotfiles::println '=> Verifying files...'
		dotfiles::set_files_to_check # FILES_TO_CHECK
		dotfiles::set_file_types     #SYMLINK_FILES COPY_FILES

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
		[[ ${DO_BACKUP} -eq 1 ]] && has_action=1

		if [[ ${has_action} -eq 1 ]]; then
			# maintenance
			[[ -n "${CLEAN_LOGS_DAYS}" ]] && dotfiles::clean_logs
			[[ -n "${CLEAN_BACKUPS_DAYS}" ]] && dotfiles::clean_backups

			# symlink / restore actions (mutually exclusive, validated in argparse)
			if [[ "${MODE}" == "reset" ]]; then
				dotfiles::clean_installs || exit 1
			elif [[ "${REPAIR_SYMLINKS}" -eq 1 ]]; then
				dotfiles::repair_symlink || exit 1
			elif [[ ${#RESTORE_FILES[@]} -gt 0 || ${RESTORE_ALL} -eq 1 ]]; then
				dotfiles::restore || exit 1
			elif [[ ${DO_BACKUP} -eq 1 ]]; then
				if [[ ${#BACKUP_FILES[@]} -gt 0 ]]; then
					dotfiles::backup_now "${BACKUP_FILES[@]}" || exit 1
				else
					dotfiles::backup_now || exit 1
				fi
			fi

			dotfiles::println '=> Done.'
			exit 0
		fi

		# TODO: logging

		dotfiles::install

		dotfiles::print_end
		if dotfiles::is_true "${DOTFILES_AUTORESTART}"; then
			exec zsh
		fi

		exit 0
	}
	main "$@"
	####################
}
