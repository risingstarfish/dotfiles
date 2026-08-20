#!/usr/bin/env bash

if [[ -n "${__FILESYSTEM_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "common.sh" "log.sh" || exit 1

{
	# Checks if a file exists and is readable.
	# Usage: filesystem::require_readable <filepath> [file_description]
	#
	# Arguments:
	#   $1 (filepath)         : The path to the file being checked.
	#   $2 (file_description) : (Optional) A description of the file for the error message (e.g., "Template"). Defaults to "File".
	#
	# Returns:
	#   0 on success (file exists and is readable).
	#   1 on failure (file is missing or permission denied).
	#   2 on argument count mismatch.
	filesystem::require_readable() {
		common::assert_args "filesystem::require_readable" $# 1 2 || return $?

		local -r filepath="$1"
		local -r file_desc="${2:-File}"

		if [[ ! -r "$filepath" ]]; then
			log::error "${file_desc} missing or unreadable: ${filepath}" 2
			return 1
		fi

		log::success "${file_desc} confirmed readable: ${filepath}"
		return 0
	}

	# Checks if a path exists and is a regular file.
	# Usage: filesystem::require_file <filepath> [file_description]
	#
	# Arguments:
	#   $1 (filepath)         : The path to the file being checked.
	#   $2 (file_description) : (Optional) A description of the file for the error message (e.g., "Config"). Defaults to "File".
	#
	# Returns:
	#   0 on success (path exists and is a regular file).
	#   1 on failure (path is missing or is not a regular file).
	#   2 on argument count mismatch.
	filesystem::require_file() {
		common::assert_args "filesystem::require_file" $# 1 2 || return $?

		local -r filepath="$1"
		local -r file_desc="${2:-File}"

		# -f checks if the path exists AND is a regular file (not a directory/device)
		if [[ ! -f "$filepath" ]]; then
			log::error "${file_desc} missing or not a regular file: ${filepath}" 2
			return 1
		fi

		log::success "${file_desc} confirmed as regular file: ${filepath}"
		return 0
	}

	# Checks if a path exists and is a directory.
	# Usage: filesystem::require_directory <dirpath> [dir_description]
	#
	# Arguments:
	#   $1 (dirpath)         : The path to the directory being checked.
	#   $2 (dir_description) : (Optional) A description of the directory for the error message (e.g., "Target"). Defaults to "Directory".
	#
	# Returns:
	#   0 on success (path exists and is a directory).
	#   1 on failure (path is missing or is not a directory).
	#   2 on argument count mismatch.
	filesystem::require_directory() {
		common::assert_args "filesystem::require_directory" $# 1 2 || return $?

		local -r dirpath="$1"
		local -r dir_desc="${2:-Directory}"

		# -d checks if the path exists AND is a directory
		if [[ ! -d "$dirpath" ]]; then
			log::error "${dir_desc} missing or not a directory: ${dirpath}" 2
			return 1
		fi

		log::success "${dir_desc} confirmed as directory: ${dirpath}"
		return 0
	}

	# Backs up a file or symlink by appending .bak to its name.
	# Usage: filesystem::backup <target_path>
	#
	# Arguments:
	#   $1 (target_path) : The path to the file/symlink to back up.
	#
	# Returns:
	#   0 on success (backup created successfully, or no file existed to backup).
	#   1 on failure (mv command failed due to permissions, etc.).
	#   2 on argument count mismatch.
	filesystem::backup() {
		common::assert_args "filesystem::backup" $# 1 || return $?

		local -r target="$1"

		# -e checks existence, -L catches broken symlinks
		if [[ -e "$target" || -L "$target" ]]; then
			log::info "Found existing file. Backing up to ${target}.bak..."

			if ! mv -f "$target" "${target}.bak" 2>/dev/null; then
				log::error "Failed to backup ${target}" 2
				return 1
			fi
		fi

		return 0
	}

	# Creates a symlink, automatically backing up any existing destination.
	# Usage: filesystem::symlink <source_file> <destination_path>
	#
	# Arguments:
	#   $1 (source_file)      : The existing source path to link to.
	#   $2 (destination_path) : The location where the symlink will be created.
	#
	# Returns:
	#   0 on success (symlink created successfully).
	#   1 on failure (source unreadable, backup failed, or link creation failed).
	#   2 on argument count mismatch.
	filesystem::symlink() {
		common::assert_args "filesystem::symlink" $# 2 || return $?

		local -r source_file="$1"
		local -r dest_path="$2"

		filesystem::require_readable "$source_file" "Source file" || return 1

		log::info "Processing $(basename "$source_file")..."

		filesystem::backup "$dest_path" || return 1

		if ln -s "$source_file" "$dest_path"; then
			log::success "Symlinked: ${dest_path} -> ${source_file}"
			return 0
		else
			log::error "Failed to create symlink at ${dest_path}" 2
			return 1
		fi
	}

	# Installs multiple files as symlinks into a target directory.
	# Automatically skips .template and .DS_Store files.
	# Usage: filesystem::install_symlink <target_dir> <file1> [file2 ...]
	#
	# Arguments:
	#   $1 (target_dir) : The directory where the symlinks will be created.
	#   $@ (files)      : One or more source files to symlink.
	#
	# Returns:
	#   0 on success (iteration finished).
	#   1 on failure (target base directory is missing or invalid).
	#   2 on argument count mismatch.
	filesystem::install_symlink() {
		common::assert_args "filesystem::install_symlink" $# 2 999 || return $?

		local -r target_dir="$1"

		filesystem::require_directory "$target_dir" "Target directory" || return 1

		shift

		echo ""
		log::info "Installing ${#} config file(s) into ${target_dir}..."

		local file
		local filename
		local dest
		local abs_source

		for file in "$@"; do
			if [[ "$file" == *.template || "$file" == *.DS_Store ]]; then
				continue
			fi

			filename="$(basename "$file")"
			dest="${target_dir}/${filename}"

			if command -v realpath >/dev/null 2>&1; then
				abs_source=$(realpath "$file")
			else
				# fallback
				abs_source="$PWD/${file#./}"
			fi

			echo ""
			filesystem::symlink "$abs_source" "$dest"
		done

		return 0
	}
}
