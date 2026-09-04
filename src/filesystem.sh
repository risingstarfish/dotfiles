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
	modules/ssh/config)
		printf '%s' "600"
		;;
	*)
		return 1
		;;
	esac
}

# symlink
{
	# Ensure a single backup run directory exists for this script invocation.
	# Computes the timestamp once; all subsequent calls reuse it.
	#
	# Usage: ensure_backup_run
	# Returns: 0 on success, 1 if directory cannot be created.
	dotfiles::ensure_backup_run() {
		if [[ -n "${BACKUP_RUN_DIR:-}" ]]; then
			return 0
		fi

		local day time
		day="$(date '+%Y-%m-%d')"
		time="$(date '+%H-%M-%S')"

		BACKUP_RUN_DIR="${DOTFILES_CACHE_DIR}/backups/${day}/${time}"

		if ((DRY_RUN)); then
			return 0
		fi

		if ! mkdir -p "${BACKUP_RUN_DIR}"; then
			dotfiles::println 'Error: cannot create backup directory: %s' "${BACKUP_RUN_DIR}" >&2
			return 1
		fi

		return 0
	}

	# MOVE an existing file into the current run's backup directory.
	# The source file is removed from its original location.
	# Used automatically when a symlink conflicts with an existing user file.
	#
	# Usage: backup_file <path>
	# Returns: 0 on success (including DRY_RUN and "file does not exist"), 1 on error
	dotfiles::backup_file() {
		local -r src="${1:-}"

		if [[ -z "${src}" ]]; then
			dotfiles::println 'Error: backup_file requires a path argument.' >&2
			return 1
		fi

		if [[ ! -f "${src}" ]]; then
			return 0
		fi

		dotfiles::ensure_backup_run || return 1

		local -r base="${src##*/}"
		local -r dest="${BACKUP_RUN_DIR}/${base}.bak"

		if ((DRY_RUN)); then
			dotfiles::println '  [backup] %s -> %s' "${src}" "${dest}"
			return 0
		fi

		if ! mv "${src}" "${dest}"; then
			dotfiles::println 'Error: cannot back up %s to %s' "${src}" "${dest}" >&2
			return 1
		fi

		dotfiles::println '  [backup] %s -> %s' "${src}" "${dest}"
		return 0
	}

	# COPY (not move) current managed files into a new backup run.
	# The source files remain in place.
	# Used by --backup for explicit user-initiated snapshots.
	#
	# Usage: backup_now [basename...]
	#   With arguments: back up only the specified basenames (e.g. ".zshrc")
	#   Without:        back up all managed files from the manifest
	#
	# Returns: 0 on success, 1 if one or more copies failed
	dotfiles::backup_now() {
		local -a targets=()

		local src
		local dest
		local ftype
		# Build the list of destination paths to copy
		if [[ $# -gt 0 ]]; then
			# User specified specific basenames
			for name in "$@"; do
				local found=0
				if [[ -f "${MANIFEST}" ]]; then
					while IFS=$'\t' read -r src dest ftype; do
						if [[ "${dest##*/}" == "${name}" ]]; then
							targets+=("${dest}")
							found=1
							break
						fi
					done <"${MANIFEST}"
				fi
				if ((found == 0)); then
					targets+=("${HOME}/${name}")
				fi
			done
		else
			# Back up all managed files
			if [[ ! -f "${MANIFEST}" ]]; then
				dotfiles::println 'No manifest found. Nothing to back up.'
				return 0
			fi

			while IFS=$'\t' read -r src dest ftype; do
				[[ -z "${dest}" ]] && continue
				targets+=("${dest}")
			done <"${MANIFEST}"
		fi

		if [[ ${#targets[@]} -eq 0 ]]; then
			dotfiles::println 'No managed files found to back up.'
			return 0
		fi

		dotfiles::ensure_backup_run || return 1

		local ok=0 skipped=0 failed=0

		dotfiles::println '=> Backing up %d file(s) to %s' "${#targets[@]}" "${BACKUP_RUN_DIR}"

		local dest base backup_dest
		for dest in "${targets[@]}"; do
			base="${dest##*/}"
			backup_dest="${BACKUP_RUN_DIR}/${base}.bak"

			# Skip symlinks (not user files)
			if [[ -L "${dest}" ]]; then
				dotfiles::println '    [skip] %s (symlink)' "${dest}"
				skipped=$((skipped + 1))
				continue
			fi

			# Skip missing files
			if [[ ! -f "${dest}" ]]; then
				dotfiles::println '    [skip] %s (does not exist)' "${dest}"
				skipped=$((skipped + 1))
				continue
			fi

			if ((DRY_RUN)); then
				dotfiles::println '    [dry-run] cp %s %s' "${dest}" "${backup_dest}"
				ok=$((ok + 1))
				continue
			fi

			if cp "${dest}" "${backup_dest}"; then
				dotfiles::println '    [backed up] %s' "${dest}"
				ok=$((ok + 1))
			else
				dotfiles::println 'Error: cannot copy %s to %s' "${dest}" "${backup_dest}" >&2
				failed=$((failed + 1))
			fi
		done

		dotfiles::println '  Backup done: %d copied, %d skipped, %d failed.' \
			"${ok}" "${skipped}" "${failed}"

		if ((failed > 0)); then
			return 1
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
		modules/zsh/aliases)
			printf '%s' "${HOME}/.aliases"
			;;
		modules/zsh/exports)
			printf '%s' "${HOME}/.exports"
			;;
		modules/zsh/functions)
			printf '%s' "${HOME}/.functions"
			;;
		modules/zsh/p10k.zsh)
			printf '%s' "${HOME}/.p10k.zsh"
			;;
		modules/zsh/paths)
			printf '%s' "${HOME}/.paths"
			;;
		modules/zsh/zimrc)
			printf '%s' "${HOME}/.zimrc"
			;;
		modules/zsh/zsh_options)
			printf '%s' "${HOME}/.zsh_options"
			;;
		modules/zsh/zshrc)
			printf '%s' "${HOME}/.zshrc"
			;;
		modules/zsh/zshrc.toggles)
			printf '%s' "${HOME}/.zshrc.toggles"
			;;
		modules/zsh/zstyles)
			printf '%s' "${HOME}/.zstyles"
			;;
		# bash
		modules/bash/bashrc)
			printf '%s' "${HOME}/.bashrc"
			;;

		# git
		modules/git/gitconfig)
			printf '%s' "${HOME}/.gitconfig"
			;;
		modules/git/gitconfig.local.*)
			printf '%s' "${HOME}/.gitconfig.local"
			;;
		modules/git/gitignore)
			printf '%s' "${HOME}/.gitignore"
			;;
		modules/git/gitattributes)
			printf '%s' "${HOME}/.gitattributes"
			;;
		# ssh
		modules/ssh/config)
			printf '%s' "${HOME}/.ssh/config"
			;;
		modules/ssh/allowed_signers.gen)
			printf '%s' "${HOME}/.ssh/allowed_signers"
			;;
			# dev
		modules/dev/CMakeUserPresets.json)
			printf '%s' "${HOME}/dev/CMakeUserPresets.json"
			;;
		modules/dev/internal-flags.cmake)
			printf '%s' "${HOME}/dev/internal-flags.cmake"
			;;
		modules/dev/cmake-format.py)
			printf '%s' "${HOME}/dev/.cmake-format.py"
			;;
		modules/dev/clang-format)
			printf '%s' "${HOME}/dev/.clang-format"
			;;
		modules/dev/clang-tidy)
			printf '%s' "${HOME}/dev/.clang-tidy"
			;;
		# tmux
		modules/tmux/tmux.conf.*)
			printf '%s' "${HOME}/.tmux.conf"
			;;

		# curl
		modules/curl/curlrc)
			printf '%s' "${HOME}/.curlrc"
			;;
		# wget
		modules/wget/wgetrc)
			printf '%s' "${HOME}/.wgetrc"
			;;
		# .shellcheck
		modules/shellcheck/shellcheckrc)
			printf '%s' "${HOME}/.shellcheckrc"
			;;
		# claude
		modules/claude/settings.json)
			printf '%s' "${HOME}/.claude/settings.json"
			;;
		modules/claude/plugin.json)
			printf '%s' "${HOME}/.claude/plugin.json"
			;;
		# fastfetch
		modules/fastfetch/config.jsonc.*)
			printf '%s' "${HOME}/.config/fastfetch/config.jsonc"
			;;
		# topgrade
		modules/topgrade/topgrade.toml)
			if [[ "${TARGET_OS}" == "${OS_WINDOWS}" ]]; then
				printf "${APPDATA:-${HOME}/.config}/topgrade.toml"
			else
				printf "${XDG_CONFIG_HOME:-${HOME}/.config}/topgrade.toml"
			fi
			;;
		# iterm2
		# modules/iterm2/Profiles.json)
		# 	printf '%s' "${HOME}/Library/Application Support/iTerm2/Profiles.json"
		# 	;;
		# modules/iterm2/schemas/*)
		# 	local filename="${relative##*/}"
		# 	printf '%s' "${HOME}/Library/Application Support/iTerm2/schemas/${filename}"
		# 	;;
		*)
			return 1
			;;
		esac
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
			if ! ((DRY_RUN)); then
				dotfiles::manifest_add "${source}" "${dest}" "symlink"
			fi
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
			dotfiles::manifest_add "${source}" "${dest}" "symlink"
		fi

		return 0
	}

	# Symlink every file in SYMLINK_FILES to its resolved destination.
	# Usage: symlink_all
	#
	# Precondition:
	#   SYMLINK_FILES must be populated (see set_file_types)
	#
	# Returns:
	#   0 if all symlinks were created or already existed
	#   1 if one or more symlinks failed
	dotfiles::symlink_all() {
		if [[ ${#SYMLINK_FILES[@]} -eq 0 ]]; then
			dotfiles::println 'No files to symlink.'
			return 0
		fi

		local total=${#SYMLINK_FILES[@]}
		local ok=0
		local failed=0
		local source
		local dest

		dotfiles::println '=> Symlinking %d file(s)…' "${total}"

		for source in "${SYMLINK_FILES[@]}"; do
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

	# Merges a template into a user-managed .local file using sentinel markers.
	# The tool owns the block between sentinels; the user owns everything below.
	#
	# Usage: copy_file <source> <dest>
	#
	# Returns:
	#   0 on success (including "up to date" and "no sentinels, skipped")
	#   1 on error
	dotfiles::copy_file() {
		local -r source="$1"
		local -r dest="$2"

		# validate
		if [[ -z "${source}" || -z "${dest}" ]]; then
			dotfiles::println 'Error: copy_file requires both source and dest.' >&2
			return 1
		fi

		if [[ ! -f "${source}" ]]; then
			dotfiles::println 'Error: source does not exist: %s' "${source}" >&2
			return 1
		fi

		# refuse to modify symlinks
		if [[ -L "${dest}" ]]; then
			dotfiles::println 'Error: %s is a symlink. Refusing to modify.' "${dest}" >&2
			return 1
		fi

		# ensure parent directory
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

		# dest doesn't exist
		if [[ ! -f "${dest}" ]]; then
			if ((DRY_RUN)); then
				dotfiles::println '  [dry-run] create %s (from %s)' "${dest}" "$(basename "${source}")"
				return 0
			fi
			{
				printf '%s\n' "${MERGE_TOP_SENTINEL}"
				cat "${source}"
				printf '\n%s\n' "${MERGE_BOTTOM_SENTINEL}"
			} >"${dest}" || return 1
			chmod 600 "${dest}"
			dotfiles::println '  [merged] created %s' "${dest}"
			dotfiles::manifest_add "${source}" "${dest}" "merged"
			return 0
		fi

		# verify sentinels
		if ! grep -qxF "${MERGE_TOP_SENTINEL}" "${dest}" ||
			! grep -qxF "${MERGE_BOTTOM_SENTINEL}" "${dest}"; then
			dotfiles::println '  [skip] %s (no sentinel markers found — not managed)' "${dest}"
			return 0
		fi

		# compare tool-managed block
		local current_block
		current_block="$(awk -v top="${MERGE_TOP_SENTINEL}" -v bottom="${MERGE_BOTTOM_SENTINEL}" '
			$0 == top    { in_block=1; next }
			$0 == bottom { in_block=0 }
			in_block     { print }
		' "${dest}")"

		local new_block
		new_block="$(cat "${source}")"

		if [[ "${current_block}" == "${new_block}" ]]; then
			dotfiles::println '  [skip] %s (up to date)' "${dest}"
			if ! ((DRY_RUN)); then
				dotfiles::manifest_add "${source}" "${dest}" "merged"
			fi
			return 0
		fi

		# extract user section
		local user_section
		user_section="$(awk -v sentinel="${MERGE_BOTTOM_SENTINEL}" '
			seen     { print }
			$0 == sentinel { seen=1 }
		' "${dest}")"

		# write
		if ((DRY_RUN)); then
			dotfiles::println '  [dry-run] update %s (tool block changed)' "${dest}"
			return 0
		fi

		local tmp
		tmp="$(mktemp "${dest}.tmp.XXXXXX")" || return 1

		{
			printf '%s\n' "${MERGE_TOP_SENTINEL}"
			printf '%s\n' "${new_block}"
			printf '\n%s\n' "${MERGE_BOTTOM_SENTINEL}"
			if [[ -n "${user_section}" ]]; then
				printf '\n%s\n' "${user_section}"
			fi
		} >"${tmp}" || {
			rm -f "${tmp}"
			return 1
		}

		chmod 600 "${tmp}"
		mv -- "${tmp}" "${dest}" || {
			rm -f "${tmp}"
			return 1
		}

		dotfiles::println '  [merged] updated %s (user section preserved)' "${dest}"
		dotfiles::manifest_add "${source}" "${dest}" "merged"
		return 0
	}

	# Copy/merge every file in COPY_FILES to its resolved destination.
	# Usage: copy_all
	#
	# Precondition:
	#   COPY_FILES must be populated (see set_file_types)
	#
	# Returns:
	#   0 if all copies succeeded or were skipped
	#   1 if one or more copies failed
	dotfiles::copy_all() {
		if [[ ${#COPY_FILES[@]} -eq 0 ]]; then
			return 0
		fi

		local total=${#COPY_FILES[@]}
		local ok=0
		local failed=0
		local source dest

		dotfiles::println '=> Merging %d local file(s)…' "${total}"

		for source in "${COPY_FILES[@]}"; do
			if ! dest="$(dotfiles::resolve_dest "${source}")"; then
				dotfiles::println 'Warning: no dest mapping for %s — skipping.' "${source}" >&2
				failed=$((failed + 1))
				continue
			fi

			if dotfiles::copy_file "${source}" "${dest}"; then
				ok=$((ok + 1))
			else
				failed=$((failed + 1))
			fi
		done

		dotfiles::println '  Merge done: %d/%d succeeded.' "${ok}" "${total}"
		if ((failed > 0)); then
			dotfiles::println '  %d file(s) failed.' "${failed}" >&2
			return 1
		fi

		return 0
	}

	# Executes a .gen script. The script is responsible for creating
	# its own output at the resolved destination.
	# Idempotent: if dest already exists and is non-empty, it is a no-op.
	#
	# Usage: generate_file <source_gen> <dest>
	#
	# Arguments:
	#   $1 (source_gen) : Absolute path to the .gen file (must exist).
	#   $2 (dest)       : Absolute path where the generated output is expected to appear.
	#
	# Returns:
	#   0 on success (including "already generated" and "user skipped")
	#   1 on error (missing source, script failed)
	dotfiles::generate_file() {
		local source="$1"
		local dest="$2"

		if [[ -z "${source}" || -z "${dest}" ]]; then
			dotfiles::println 'Error: generate_file requires both source and dest.' >&2
			return 1
		fi

		if [[ ! -f "${source}" ]]; then
			dotfiles::println 'Error: generator script does not exist: %s' "${source}" >&2
			return 1
		fi

		# idempotency: if dest already exists and is non-empty, skip
		if [[ -f "${dest}" && -s "${dest}" ]]; then
			dotfiles::println '  [skip] %s (already generated)' "${dest}"
			if ! ((DRY_RUN)); then
				dotfiles::manifest_add "${source}" "${dest}" "generated"
			fi
			return 0
		fi

		if ((DRY_RUN)); then
			dotfiles::println '  [dry-run] bash %s' "${source}"
			return 0
		fi

		# interactive confirmation
		if ((INTERACTIVE)); then
			local choice
			printf '  Generate: %s (output -> %s)\n' "${source##*/}" "${dest}" >&2
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

		if ! command bash "${source}"; then
			dotfiles::println 'Error: generator %s failed.' "${source}" >&2
			return 1
		fi

		if [[ ! -f "${dest}" ]]; then
			dotfiles::println 'Warning: generator ran but %s was not created.' "${dest}" >&2
		fi

		dotfiles::println '  [generated] %s' "${dest}"
		dotfiles::manifest_add "${source}" "${dest}" "generated"

		return 0
	}

	# Execute every .gen file in GENERATE_FILES.
	# Usage: generate_all
	#
	# Precondition:
	#   GENERATE_FILES must be populated (see set_file_types)
	#
	# Returns:
	#   0 if all generators succeeded or were skipped
	#   1 if one or more failed
	dotfiles::generate_all() {
		if [[ ${#GENERATE_FILES[@]} -eq 0 ]]; then
			return 0
		fi

		local total=${#GENERATE_FILES[@]}
		local ok=0
		local failed=0
		local source dest

		dotfiles::println '=> Generating %d file(s)…' "${total}"

		for source in "${GENERATE_FILES[@]}"; do
			if ! dest="$(dotfiles::resolve_dest "${source}")"; then
				dotfiles::println 'Warning: no dest mapping for %s — skipping.' "${source}" >&2
				failed=$((failed + 1))
				continue
			fi

			if dotfiles::generate_file "${source}" "${dest}"; then
				ok=$((ok + 1))
			else
				failed=$((failed + 1))
			fi
		done

		dotfiles::println '  Generate done: %d/%d succeeded.' "${ok}" "${total}"
		if ((failed > 0)); then
			dotfiles::println '  %d file(s) failed.' "${failed}" >&2
			return 1
		fi

		return 0
	}
}
