#!/usr/bin/env bash

if [[ -n "${__TEMPLATE_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __TEMPLATE_SH_INCLUDED__=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "common.sh" "log.sh" "filesystem.sh" || exit 1

{
	# Validates that a file does not contain a specific unresolved token.
	# Usage: template::validate <file_path> <invalid_token>
	#
	# Arguments:
	#   $1 (file_path)     : The path to the file being checked.
	#   $2 (invalid_token) : The string token to search for (Default INVALID_TOKEN).
	#
	# Returns:
	#   0 on success (token not found, file is valid).
	#   1 on failure (token found, or file unreadable).
	#   2 on argument count mismatch.
	template::validate() {
		common::assert_args "template::validate" $# 1 2 || return $?

		local -r file_path="$1"
		local -r invalid_token="${2:-$INVALID_TOKEN}"

		filesystem::require_readable "$file_path" "File for validation" || return 1

		if grep -qF "$invalid_token" "$file_path"; then
			log::error "Your ${file_path} contains unresolved '${invalid_token}' tags."
			log::error "You must configure these values manually before committing."
			log::error "Run: ${COLOUR_CYAN}${EDITOR:-${VISUAL:-nano}} ${file_path}${COLOUR_RESET} to fix them."
			return 1
		fi

		return 0
	}

	# Creates a file from a template if it doesn't already exist.
	# Usage: template::install <dest_file> <template_file> [sed_replacement]
	#
	# Arguments:
	#   $1 (dest_file)       : The path where the new file should be created.
	#   $2 (template_file)   : The path to the source template file.
	#   $3 (sed_replacement) : (Optional) A sed expression to apply during the copy.
	#
	# Returns:
	#   0 on success (file exists or was successfully created).
	#   1 on failure (template missing, or copy/sed operation failed).
	#   2 on argument count mismatch.
	template::install() {
		common::assert_args "template::install" $# 2 3 || return $?
		local -r dest_file="$1"
		local -r template_file="$2"
		local -r sed_replacement="${3:-}"

		if [[ -f "$dest_file" ]]; then
			log::info "${dest_file} already exists."
			return 0
		fi

		log::info "Creating ${dest_file} from template..."
		filesystem::require_readable "$template_file" "Template" || return 1

		# Catch the exit codes of the file generation commands
		if [[ -n "$sed_replacement" ]]; then
			if ! sed "$sed_replacement" "$template_file" >"$dest_file"; then
				log::error "Failed to generate ${dest_file} using sed." 2
				return 1
			fi
		else
			if ! cp "$template_file" "$dest_file"; then
				log::error "Failed to copy template to ${dest_file}." 2
				return 1
			fi
		fi

		log::success "Created ${dest_file}"
		return 0
	}
}
