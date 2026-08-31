#!/usr/bin/env bash
# filesystem.sh

set -euo pipefail

if [[ -n "${__FILESYSTEM_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

####################
# symlink
{
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
			printf '%s' "${HOME}/.config/shellcheck/.shellcheckrc"
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

	# Create a symlink from source to dest, honouring FORCE, NO_BACKUP,
	# DRY_RUN, and INTERACTIVE flags.
	# Idempotent: if dest already points to source, it is a no-op.
	# Usage: symlink_file <source> <dest>
	#
	# Arguments:
	#   $1 (source) : Absolute path to the source file (must exist).
	#   $2 (dest)   : Absolute path where the symlink will be created.
	#
	# Returns:
	#   0 on success (including "already linked" and "user skipped")
	#   1 on error (missing source, permission denied, etc.)
	dotfiles::symlink_file() {
		local source="$1"
		local dest="$2"

		if [[ -z "${source}" || -z "${dest}" ]]; then
			dotfiles::println 'Error: symlink_file requires both source and dest.' >&2
			return 1
		fi

		if [[ ! -f "${source}" ]]; then
			dotfiles::println 'Error: source does not exist: %s' "${source}" >&2
			return 1
		fi

		# already linked correctly
		if [[ -L "${dest}" && "$(readlink "${dest}")" == "${source}" ]]; then
			dotfiles::println '  [skip] %s (already linked)' "${dest}"
			return 0
		fi

		# ensure parent directory of dest exists
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

		# dest already exists
		if [[ -e "${dest}" || -L "${dest}" ]]; then
			if ((FORCE)); then
				dotfiles::println '  [force] removing existing: %s' "${dest}"
				if ((DRY_RUN)); then
					dotfiles::println '  [dry-run] rm -f %s' "${dest}"
				else
					rm -f "${dest}" || {
						dotfiles::println 'Error: cannot remove: %s' "${dest}" >&2
						return 1
					}
				fi
			elif ((NO_BACKUP)); then
				dotfiles::println '  [no-backup] removing existing: %s' "${dest}"
				if ((DRY_RUN)); then
					dotfiles::println '  [dry-run] rm -f %s' "${dest}"
				else
					rm -f "${dest}" || {
						dotfiles::println 'Error: cannot remove: %s' "${dest}" >&2
						return 1
					}
				fi
			else
				# default: back up
				local backup="${dest}.bak"
				dotfiles::println '  [backup] %s -> %s' "${dest}" "${backup}"
				if ((DRY_RUN)); then
					dotfiles::println '  [dry-run] mv %s %s' "${dest}" "${backup}"
				else
					mv "${dest}" "${backup}" || {
						dotfiles::println 'Error: cannot back up %s to %s' "${dest}" "${backup}" >&2
						return 1
					}
				fi
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
		fi

		return 0
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
