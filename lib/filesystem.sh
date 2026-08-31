#!/usr/bin/env bash
# filesystem.sh

set -euo pipefail

if [[ -n "${__FILESYSTEM_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

####################
# Returns the desired permission string for a given source path.
# Prints nothing (returns 1) if no special permission is required.
#
# Usage: file_perm <source_path>
# Output: e.g. "600", "644", "755"
# Returns: 0 if a permission was found, 1 otherwise.
dotfiles::file_perm() {
	local -r source="$1"
	local relative="${source#"${SRC_PATH}"/}"

	case "${relative}" in
	apps/ssh/config)
		printf '%s' "600"
		;;
	apps/ssh/allowed_signers)
		printf '%s' "600"
		;;
	*)
		return 1
		;;
	esac
}

# symlink
{
	# Resolve the backup directory for this run.
	# Creates the full path: $DOTFILES_CACHE_DIR/backups/YYYY-MM-DD/HH-MM-SS/
	#
	# Usage: backup_dir
	# Output: prints the absolute path to the current run's backup directory.
	# Returns: 0 on success, 1 if directory cannot be created.
	dotfiles::backup_dir() {
		local -r day="$(date '+%Y-%m-%d')"
		local -r time="$(date '+%H-%M-%S')"
		local -r dir="${DOTFILES_CACHE_DIR}/backups/${day}/${time}"

		if ((DRY_RUN)); then
			printf '%s' "${dir}"
			return 0
		fi

		mkdir -p "${dir}" || {
			dotfiles::println 'Error: cannot create backup directory: %s' "${dir}" >&2
			return 1
		}

		printf '%s' "${dir}"
	}

	# Move an existing file into the current run's backup directory.
	# The file keeps its basename; the run directory provides uniqueness.
	#
	# Usage: backup_file <path>
	#
	# Arguments:
	#   $1 (path) : Absolute path to the existing file to back up.
	#
	# Returns:
	#   0 on success (including DRY_RUN and "file does not exist")
	#   1 on error
	dotfiles::backup_file() {
		local -r src="$1"

		if [[ -z "${src}" ]]; then
			dotfiles::println 'Error: backup_file requires a path argument.' >&2
			return 1
		fi

		# nothing to back up
		if [[ ! -f "${src}" ]]; then
			return 0
		fi

		local backup_dir
		if ! backup_dir="$(dotfiles::backup_dir)"; then
			return 1
		fi

		local -r base="${src##*/}"
		local -r dest="${backup_dir}/${base}.bak"

		if ((DRY_RUN)); then
			dotfiles::println '  [backup] %s -> %s' "${src}" "${dest}"
			return 0
		fi

		mv "${src}" "${dest}" || {
			dotfiles::println 'Error: cannot back up %s to %s' "${src}" "${dest}" >&2
			return 1
		}

		dotfiles::println '  [backup] %s -> %s' "${src}" "${dest}"
		return 0
	}

	# Create a symlink from source to dest, honouring FORCE, NO_BACKUP,
	# DRY_RUN, and INTERACTIVE flags.
	# Idempotent: if dest already points to source, it is a no-op.
	#
	# Usage: symlink_file <source> <dest>
	#
	# Arguments:
	#   $1 (source) : Absolute path to the source file (must exist).
	#   $2 (dest)   : Absolute path where the symlink will be created.
	#
	# Returns:
	#   0 on success (including "already linked" and "user skipped")
	#   1 on error
	dotfiles::symlink_file() {
		local source="$1"
		local dest="$2"

		echo
		# validate
		if [[ -z "${source}" || -z "${dest}" ]]; then
			dotfiles::println 'Error: symlink_file requires both source and dest.' >&2
			return 1
		fi

		if [[ ! -f "${source}" ]]; then
			dotfiles::println 'Error: source does not exist: %s' "${source}" >&2
			return 1
		fi

		# enforce permissions
		local perm
		if perm="$(dotfiles::file_perm "${source}")"; then
			local current
			current="$(stat -f '%Lp' "${source}" 2>/dev/null || stat -c '%a' "${source}" 2>/dev/null)"
			if [[ "${current}" != "${perm}" ]]; then
				if ((DRY_RUN)); then
					dotfiles::println '  [dry-run] chmod %s %s' "${perm}" "${source}"
				else
					chmod "${perm}" "${source}" || {
						dotfiles::println 'Error: chmod %s failed on %s' "${perm}" "${source}" >&2
						return 1
					}
					dotfiles::println '  [chmod] %s -> %s' "${perm}" "${source}"
				fi
			fi
		fi

		# already linked
		if [[ -L "${dest}" && "$(readlink "${dest}")" == "${source}" ]]; then
			dotfiles::println '  [skip] %s (already linked)' "${dest}"
			dotfiles::manifest_add "${source}" "${dest}"
			return 0
		fi

		# ensure parent directory exists
		local dest_dir
		dest_dir="$(dirname "${dest}")"
		if [[ ! -d "${dest_dir}" ]]; then
			if ((DRY_RUN)); then
				dotfiles::println '  [dry-run] mkdir -p %s' "${dest_dir}"
			else
				mkdir -p "${dest_dir}" || {
					dotfiles::println 'Error: cannot create directory: %s' "${dest_dir}" >&2
					return 1
				}
			fi
		fi

		# handle existing destination
		if [[ -e "${dest}" || -L "${dest}" ]]; then
			if ((FORCE)) || ((NO_BACKUP)); then
				if ((DRY_RUN)); then
					dotfiles::println '  [dry-run] rm -f %s' "${dest}"
				else
					rm -f "${dest}" || {
						dotfiles::println 'Error: cannot remove: %s' "${dest}" >&2
						return 1
					}
				fi
			else
				# default: back up to cache dir
				dotfiles::backup_file "${dest}" || return 1
			fi
		fi

		# interactive confirmation
		if ((INTERACTIVE)); then
			local choice
			printf '  Create symlink: %s -> %s\n' "${dest}" "${source}" >&2
			if ! read -r -p '  Continue? [Y/n]: ' choice; then
				dotfiles::println 'Error: no input available for prompt.' >&2
				return 1
			fi
			case "${choice}" in
			[nN])
				dotfiles::println '  [skip] %s (user declined)' "${dest}"
				return 0
				;;
			esac
		fi

		# create symlink
		if ((DRY_RUN)); then
			dotfiles::println '  [dry-run] ln -s %s %s' "${source}" "${dest}"
		else
			ln -s "${source}" "${dest}" || {
				dotfiles::println 'Error: failed to symlink %s -> %s' "${dest}" "${source}" >&2
				return 1
			}
			dotfiles::println '  [new] %s -> %s' "${dest}" "${source}"
			dotfiles::manifest_add "${source}" "${dest}"
		fi

		return 0
	}

	# Resolve the destination path for a source file in the dotfiles repo.
	# Maps repo-relative paths to their target locations under $HOME.
	# Usage: resolve_dest <source_path>
	#
	# Arguments:
	#   $1 (source_path) : Absolute path to the source file within the repo.
	#
	# Output:
	#   Prints the resolved destination path to stdout.
	#
	# Returns:
	#   0 if a mapping was found
	#   1 if no mapping exists for the given path
	dotfiles::resolve_dest() {
		local -r source="$1"
		local relative="${source#"${SRC_PATH}"/}"

		case "${relative}" in
		# zsh
		shells/zsh/.aliases)
			printf '%s' "${HOME}/.aliases"
			;;
		shells/zsh/.exports)
			printf '%s' "${HOME}/.exports"
			;;
		shells/zsh/.functions)
			printf '%s' "${HOME}/.functions"
			;;
		shells/zsh/.p10k.zsh)
			printf '%s' "${HOME}/.p10k.zsh"
			;;
		shells/zsh/.paths)
			printf '%s' "${HOME}/.paths"
			;;
		shells/zsh/.zimrc)
			printf '%s' "${HOME}/.zimrc"
			;;
		shells/zsh/.zsh_options)
			printf '%s' "${HOME}/.zsh_options"
			;;
		shells/zsh/.zshrc)
			printf '%s' "${HOME}/.zshrc"
			;;
		shells/zsh/.zshrc.toggles)
			printf '%s' "${HOME}/.zshrc.toggles"
			;;
		shells/zsh/.zstyles)
			printf '%s' "${HOME}/.zstyles"
			;;
		# bash
		shells/bash/.bash_profile)
			printf '%s' "${HOME}/.bash_profile"
			;;
		shells/bash/.bashrc)
			printf '%s' "${HOME}/.bashrc"
			;;

		# git
		apps/git/.gitconfig)
			printf '%s' "${HOME}/.gitconfig"
			;;
		apps/git/.gitconfig.local.*)
			printf '%s' "${HOME}/.gitconfig.local"
			;;
		apps/git/.gitignore)
			printf '%s' "${HOME}/.gitignore"
			;;
		apps/git/.gitattributes)
			printf '%s' "${HOME}/.gitattributes"
			;;
		# ssh
		apps/ssh/config)
			printf '%s' "${HOME}/.ssh/config"
			;;
		apps/ssh/allowed_signers)
			printf '%s' "${HOME}/.ssh/allowed_signers"
			;;
		# curl
		apps/curl/.curlrc)
			printf '%s' "${HOME}/.curlrc"
			;;
		# wget
		apps/wget/.wgetrc)
			printf '%s' "${HOME}/.wgetrc"
			;;
		# .shellcheck
		apps/shellcheck/.shellcheckrc)
			printf '%s' "${HOME}/.shellcheckrc"
			;;
		# iterm2
		apps/iterm2/Profiles.json)
			printf '%s' "${HOME}/Library/Application Support/iTerm2/Profiles.json"
			;;
		apps/iterm2/schemas/*)
			local filename="${relative##*/}"
			printf '%s' "${HOME}/Library/Application Support/iTerm2/schemas/${filename}"
			;;
		*)
			return 1
			;;
		esac
	}

	# Symlink every file in FILES_TO_CHECK to its resolved destination.
	# Usage: symlink_all
	#
	# Precondition:
	#   FILES_TO_CHECK must be populated (see set_files_to_check)
	#
	# Returns:
	#   0 if all symlinks were created or already existed
	#   1 if one or more symlinks failed
	dotfiles::symlink_all() {
		if [[ ${#FILES_TO_CHECK[@]} -eq 0 ]]; then
			dotfiles::println 'No files to symlink.'
			return 0
		fi

		local total=${#FILES_TO_CHECK[@]}
		local ok=0
		local failed=0
		local source dest

		dotfiles::println '=> Symlinking %d file(s)…' "${total}"

		for source in "${FILES_TO_CHECK[@]}"; do
			if ! dest="$(dotfiles::resolve_dest "${source}")"; then
				dotfiles::println 'Warning: no dest mapping for %s — skipping.' "${source}" >&2
				failed=$((failed + 1))
				continue
			fi

			if dotfiles::symlink_file "${source}" "${dest}"; then
				ok=$((ok + 1))
			else
				failed=$((failed + 1))
			fi
		done

		dotfiles::println '  Symlink done: %d/%d succeeded.' "${ok}" "${total}"
		if ((failed > 0)); then
			dotfiles::println '  %d file(s) failed.' "${failed}" >&2
			return 1
		fi

		return 0
	}
}
