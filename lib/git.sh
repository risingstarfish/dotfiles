#!/usr/bin/env bash

if [[ -n "${__GIT_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __GIT_SH_INCLUDED__=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootstrap.sh" || {
	printf "\n\e[31m[ERROR]\e[0m Failed to source bootstrap.sh. Exiting...\n" >&2
	exit 1
}

source_deps "common.sh" "log.sh" || exit 1

{
	# Determines the correct git credential helper for the current OS.
	# Usage: git::get_credential_helper <output_variable>
	#
	# Arguments:
	#   $1 (output_variable) : A name reference variable to store the resulting credential helper string.
	#
	# Returns:
	#   0 on success (helper successfully identified).
	#   1 on failure (unknown OS, unable to determine helper).
	#   2 on argument count mismatch.
	git::get_credential_helper() {
		common::assert_args "git::get_credential_helper" $# 0 || return $?

		if [[ "$OS" == "Windows_NT" ]]; then
			printf "git-credential-manager.exe\n"
			return 0
		fi

		case "$(uname -s)" in
		Darwin*)
			printf "osxkeychain\n"
			;;
		Linux*)
			if uname -r | grep -qi "microsoft"; then
				printf "git-credential-manager.exe\n"
			else
				printf "libsecret\n"
			fi
			;;
		CYGWIN* | MINGW* | MSYS*)
			printf "git-credential-manager.exe\n"
			;;
		*)
			log::warning "Unknown OS. Unable to determine git credential helper." 2
			printf "%s\n" "$INVALID_TOKEN"
			return 1
			;;
		esac

		return 0
	}

	# Verifies that a given git credential helper is available on the system.
	# Usage: git::verify_credential_helper <helper_string>
	#
	# Arguments:
	#   $1 (helper_string) : The name of the credential helper (e.g., "osxkeychain", "libsecret").
	#
	# Returns:
	#   0 on success (helper is available).
	#   1 on failure (helper missing or unverified).
	#   2 on argument count mismatch.
	git::verify_credential_helper() {
		common::assert_args "git::verify_credential_helper" $# 1 || return $?
		local -r helper_string="$1"

		if [[ "$helper_string" == "${INVALID_TOKEN}" ]]; then
			return 1
		fi

		case "$helper_string" in
		osxkeychain)
			if command -v git credential-osxkeychain >/dev/null 2>&1 || [[ -f /Library/Developer/CommandLineTools/usr/libexec/git-core/git-credential-osxkeychain ]] || xcode-select -p >/dev/null 2>&1; then
				log::success "Credential helper 'osxkeychain' is available."
				return 0
			fi
			;;
		libsecret)
			# Linux: Check if the libsecret binary exists in standard git core paths or if pkg-config/libsecret is present
			if command -v git credential-libsecret >/dev/null 2>&1 || [[ -f /usr/lib/git-core/git-credential-libsecret ]] || [[ -f /usr/libexec/git-core/git-credential-libsecret ]]; then
				log::success "Credential helper 'libsecret' is available."
				return 0
			# Alternatively check if the source/contrib path exists on typical distros
			elif [[ -f /usr/share/doc/git/contrib/credential/libsecret/git-credential-libsecret ]]; then
				log::success "Credential helper 'libsecret' source found."
				return 0
			fi
			;;
		*.exe)
			# Windows / WSL: Check for the executable in PATH
			if command -v "$helper_string" >/dev/null 2>&1; then
				log::success "Credential helper '${helper_string}' is installed."
				return 0
			fi
			;;
		esac

		# Fallback generic check via `command -v`
		if command -v "git credential-${helper_string}" >/dev/null 2>&1; then
			log::success "Credential helper 'git-credential-${helper_string}' is installed."
			return 0
		fi

		# If we reach here, it wasn't found
		log::warning "Credential helper '${helper_string}' could not be automatically verified." 2
		log::warning "You may need to install or configure it manually." 2
		return 1
	}

	# Locates the ssh-keygen executable on the system.
	# Usage: git::find_ssh_keygen
	#
	# Returns:
	#   0 on success (outputs the path to the executable).
	#   1 on failure (executable not found).
	#   2 on argument count mismatch.
	git::find_ssh_keygen() {
		common::assert_args "git::find_ssh_keygen" $# 0 || return $?

		local bin_name="ssh-keygen"

		if [[ "$OS" == "Windows_NT" ]]; then
			bin_name="ssh-keygen.exe"
		else
			case "$(uname -s)" in
			Darwin*)
				bin_name="ssh-keygen"
				;;
			Linux*)
				# WSL check: favor .exe if on Microsoft/WSL kernel, otherwise standard
				if uname -r | grep -qi "microsoft"; then
					bin_name="ssh-keygen.exe"
				else
					bin_name="ssh-keygen"
				fi
				;;
			CYGWIN* | MINGW* | MSYS*)
				bin_name="ssh-keygen.exe"
				;;
			*)
				bin_name="ssh-keygen"
				;;
			esac
		fi

		# verification
		local bin_path
		# Look for the target executable in PATH
		if bin_path=$(command -v "$bin_name" 2>/dev/null); then
			printf "%s\n" "$bin_path"
			return 0
		fi

		if [[ "$bin_name" == "ssh-keygen.exe" ]]; then
			if bin_path=$(command -v "ssh-keygen" 2>/dev/null); then
				printf "%s\n" "$bin_path"
				return 0
			fi
		fi

		log::warning "Application '${bin_name}' could not be found in PATH." 2
		printf "%s\n" "$INVALID_TOKEN"
		return 1
	}

	# git pull with fallback on windows because git bash and openssh have path issues (for me)
	git::pull() {
		if git pull origin main 2>&1; then
			return 0
		fi

		local git_output
		git_output=$(git pull origin main 2>&1)

		if [[ "${OS:-}" == "Windows_NT" ]] && command -v where >/dev/null 2>&1; then

			local -r first_ssh="$(where ssh 2>/dev/null | head -n 1)"
			local -r openssh_path="$(where ssh 2>/dev/null | grep -i "OpenSSH" | head -n 1)"

			if [[ -n "$openssh_path" && "$first_ssh" != "$openssh_path" ]]; then
				local -r windows_ssh="${openssh_path//\\//}"

				printf "\n"
				log::info "Git Bash ssh failed. Retrying explicitly with Windows OpenSSH..."

				if GIT_SSH_COMMAND="$windows_ssh" git pull origin main 2>&1; then
					log::success "Successfully pulled changes using Windows OpenSSH."
					return 0
				fi
			fi
		fi

		printf "\n"
		log::warning "Git pull failed. Reason: $git_output"
		return 1
	}
}
