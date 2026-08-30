#!/usr/bin/env bash
# filesystem.sh

set -euo pipefail

if [[ -n "${__FILESYSTEM_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

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

	# Prompts the user with a yes/no question.
	# Usage: filesystem::prompt_yes_no <prompt_text>
	#
	# Arguments:
	#   $1 (prompt_text) : The question to display to the user.
	#
	# Returns:
	#   0 on success (user answered yes).
	#   1 on failure (user answered no).
	#   2 on argument count mismatch.
	filesystem::prompt_yes_no() {
		common::assert_args "filesystem::prompt_yes_no" $# 1 || return $?

		local prompt_text="$1"
		local response
		read -r -p "$prompt_text (y/N) " response
		[[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
	}

	# Extracts everything from line 1 down to the marker from a given file.
	# Usage: filesystem::get_managed_area <target_file> <marker>
	#
	# Arguments:
	#   $1 (target_file) : The configuration file to read from.
	#   $2 (marker)      : The string marker delineating the end of the managed area.
	#
	# Returns:
	#   0 on success.
	#   2 on argument count mismatch.
	filesystem::get_managed_area() {
		common::assert_args "filesystem::get_managed_area" $# 2 || return $?

		local target_file="$1"
		local marker="$2"

		sed -n "1,/${marker}/p" "$target_file"
	}

	# Extracts everything strictly below the marker from a given file (the user's additions).
	# Usage: filesystem::get_user_area <target_file> <marker>
	#
	# Arguments:
	#   $1 (target_file) : The configuration file to read from.
	#   $2 (marker)      : The string marker delineating the start of the user area.
	#
	# Returns:
	#   0 on success.
	#   2 on argument count mismatch.
	filesystem::get_user_area() {
		common::assert_args "filesystem::get_user_area" $# 2 || return $?

		local target_file="$1"
		local marker="$2"

		sed "1,/${marker}/d" "$target_file"
	}

	# Merges a template with an existing local config file, preserving user additions.
	# Compares the managed area (above the marker) and prompts to update if different.
	# Usage: filesystem::install_local <source_file> <dest_file> [marker_string]
	#
	# Arguments:
	#   $1 (source_file)   : The template file containing the managed configuration.
	#   $2 (dest_file)     : The target local configuration file to update.
	#   $3 (marker_string) : (Optional) The boundary marker. Defaults to "# --- Do not edit this line or above ---".
	#
	# Returns:
	#   0 on success (file installed, updated, or safely skipped).
	#   1 on failure (source missing, or file operations failed).
	#   2 on argument count mismatch.
	filesystem::install_local() {
		common::assert_args "filesystem::install_local" $# 2 3 || return $?

		local source_file="$1"
		local dest_file="$2"
		local marker="${3:-# --- Do not edit this line or above ---}"

		if [[ ! -f "$source_file" ]]; then
			log::warning "Source file not found: %s\n" "$source_file"
			return 1
		fi

		if [[ ! -f "$dest_file" ]]; then
			cp "$source_file" "$dest_file" || return 1
			log::success "Installed new %s\n" "$dest_file"
			return 0
		fi

		# marker is missing
		if ! grep -qF "$marker" "$dest_file"; then
			log::warning "Marker missing in %s. Cannot safely merge.\n" "$dest_file"
			if filesystem::prompt_yes_no "Back up this file and overwrite it completely with the template?"; then
				cp "$dest_file" "${dest_file}.bak"
				cp "$source_file" "$dest_file" || return 1
				log::success "Backed up to .bak and overwrote %s.\n" "$dest_file"
			else
				log::info "Left %s unchanged.\n" "$dest_file"
			fi
			return 0
		fi

		# compare managed areas using process substitution
		if cmp -s <(filesystem::get_managed_area "$source_file" "$marker") \
			<(filesystem::get_managed_area "$dest_file" "$marker"); then
			# match
			return 0
		fi

		# managed areas differ
		log::warning "The managed configuration in %s is outdated or modified.\n" "$dest_file"
		if filesystem::prompt_yes_no "Overwrite the managed area with the latest template?"; then
			local temp_final
			temp_final="$(mktemp)"

			# merge
			filesystem::get_managed_area "$source_file" "$marker" >"$temp_final"
			filesystem::get_user_area "$dest_file" "$marker" >>"$temp_final"

			mv "$temp_final" "$dest_file" || return 1
			log::success "Updated managed area of %s (preserved local additions).\n" "$dest_file"
		else
			log::info "Left %s unchanged.\n" "$dest_file"
		fi

		return 0
	}

}
