#!/usr/bin/env bash
# print.sh

####################
if [[ -n "${__PRINT_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __PRINT_SH_INCLUDED__=1
####################
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
  -x, --exclude <module...>  Install all modules EXCEPT specified <module>, semicolon-separated
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
