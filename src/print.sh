#!/usr/bin/env bash
# print.sh

if [[ -n ${__PRINT_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __PRINT_SH_INCLUDED__=1

print_help() {
    cat << EOF
OVERVIEW: Installs and synchronizes dotfiles and shell configuration.

USAGE: bash $(basename "$0") <action> [options]

ALL ACTIONS:

INSTALL
      --install              Install (or reinstall) all available dotfiles.
  -u, --update               Update from Git before installing.
  -r, --remove <module...>   Remove target modules <module>, semicolon-separated.
  -R, --repair               Remove orphaned symlinks and generated files, then re-link/generate.
      --reset                Remove all symlinks and generated files managed by this tool.
                             (note: copied/merged files will remain)
      --uninstall            Deletes symlinks, logs, and backups, then deletes install directory.

INFORMATION
  -l, --list                 Display all available modules.
      --verify               Check all managed dotfiles. (exit 0 = healthy, 1 = broken)
      --version              Show the version and git information of this program.
  -h, --help                 Show this help message.

ALL OPTIONS:

INSTALL MODULES
  -i, --include <module...>  Install ONLY the specified modules <module>, semicolon-separated.
  -x, --exclude <module...>  Install all modules EXCEPT specified <module>, semicolon-separated.

BEHAVIOUR
  -n, --dry-run              Print planned actions without modifying the disk.
  -I, --interactive          Prompt for confirmation before every action/modification.
      --noconfirm            Do not prompt for any confirmation.
  -y, --yes                  Auto-accept yes to prompts. Alias to --noconfirm.
  -f, --force                Overwrite existing files/links.
  -K, --autorestart          Automatically restart shell at script end.
      --no-backup            Delete existing conflicting files instead of backing up.
      --no-deps              Skip dotfiles dependency post installation.

LOGGING
  -d, --debug                Print debug output (useful for diagnosing).
  -q, --quiet                Suppress all standard output except errors.
      --log-level <level>    Set log verbosity <level>. Valid options are: debug, info, notice,
                             warn, or error. (default: info)
      --no-log               Disable logging to stdout (still writes to file).

ENVIRONMENT VARIABLES
  Global (Always Active):
    DOTFILES_LOG_DIR         Path to store log files. (default: ~/.config/dotfiles/logs)
    DOTFILES_CACHE_DIR       Path to store temporary cache. (default: ~/.cache/dotfiles)
    DOTFILES_LOG             Set to 0 or false to disable log file writing. (default: 1)
    DOTFILES_LOCAL_MODS      Set to 1 or true to install with uncommitted local changes.
                             (default: 0)
    DOTFILES_AUTORESTART     Set to 1 or true to restart shell at script finish. (default: 0)

  Windows Specific:
    DOTFILES_IGNORE_HANDOFF  Set to 1 or true to ignore the Windows Powershell notice. (default 0)

EOF
}

# utility
git_or_unknown() {
    local default="$1"
    shift

    local out
    if out=$(command git -C "${SRC_PATH}" "$@" 2> /dev/null); then
        printf '%s' "${out:-$default}"
    else
        printf '%s' "$default"
    fi
}

print_version() {
    local dotfiles_install_dir
    local dotfiles_branch
    local dotfiles_remote
    local dotfiles_version
    local dotfiles_commit_hash
    local dotfiles_version_commit_msg
    local -r dotfiles_version_last_checked=$(date +%Y-%m-%d\ %H:%M:%S\ %Z) || dotfiles_version_last_checked="<unknown>"

    dotfiles_install_dir=$(git_or_unknown "<unknown>" rev-parse --show-toplevel)
    dotfiles_branch=$(git_or_unknown "<unknown>" rev-parse --abbrev-ref HEAD)
    dotfiles_remote=$(git_or_unknown "<unknown>" config --get remote.origin.url)
    dotfiles_version=$(git_or_unknown "<unknown>" describe --tags --always)
    dotfiles_commit_hash=$(git_or_unknown "<unknown>" rev-parse HEAD)
    dotfiles_version_commit_msg=$(git_or_unknown "<unknown>" log -1 --pretty=%B)

    cat << EOF
dotfiles ${dotfiles_version} built from branch ${dotfiles_branch} at commit ${dotfiles_commit_hash:0:12} ($dotfiles_version_commit_msg)
Date: ${dotfiles_version_last_checked}
Repository: ${dotfiles_install_dir}
Remote: ${dotfiles_remote}

EOF
}

list_modules() {
    set_available_modules

    local -a manifest_sources=()
    local -a manifest_dests=()
    local -a manifest_ftypes=()
    if [[ -f ${MANIFEST}  ]]; then
        local _src
        local _dest
        local _ftype
        while IFS=$'\t' read -r _src _dest _ftype; do
            _ftype="${_ftype%$'\r'}" # windows crlf
            [[ -n ${_src} ]] && {
                manifest_sources+=("${_src}")
                manifest_dests+=("${_dest}")
                manifest_ftypes+=("${_ftype}")
            }
        done < "${MANIFEST}"
    fi

    printf '\nAVAILABLE MODULES\n\n'

    local current_category=""
    #local current_module_dir=""
    local item
    local src
    local dest
    local cmd
    local category
    local filename

    for item in "${AVAILABLE_MODULES[@]}"; do
        IFS='|' read -r src dest cmd <<< "${item}"

        category="${src%%/*}"
        src_file="${MODULE_DIR}/${src}"
        filename="${src##*/}"
        filename="${filename%.gen}" # remove .gen

        # category header
        if [[ $category != "$current_category"   ]]; then
            printf '%s\n' "${category}"
            current_category="${category}"
        fi

        local  status="✗"
        local i
        for i in "${!manifest_sources[@]}"; do
            if [[ ${manifest_sources[$i]} == "$src_file" ]]; then
                local _dest="${manifest_dests[$i]}"
                local ftype="${manifest_ftypes[$i]}"

                case "${ftype}" in
                    merged)
                        if [[ -f $dest ]]; then
                            status="✓"
                        else
                            status="!"
                        fi
                        ;;
                    generated)
                        if [[ -f $dest && -s $dest ]]; then
                            status="✓"
                        elif [[ -f $dest ]]; then
                            status="!"
                        fi
                        ;;
                    symlink)
                        if [[ -L $dest && -e $dest ]]; then
                            status="✓"
                        elif [[ -L $dest ]]; then
                            status="!"
                        fi
                        ;;
                    *)
                        die 1 'invalid type detected: %s.\nSomething went wrong!' "${ftype}"
                        ;;
                esac
                break
            fi
        done

        # fallback check disk
        if [[ ${status} == "✗" && -n ${dest}     ]]; then
            if [[ ${src_file} == *.gen   ]]; then
                # Generated: healthy if output exists and is non-empty
                if [[ -f ${dest} && -s ${dest}     ]]; then
                    status="✓"
                elif [[ -f ${dest}   ]]; then
                    status="!"
                fi
            elif [[ -L ${dest}   ]]; then
                if [[ -e ${dest}   ]]; then
                    status="✓"
                else
                    status="!" # Broken symlink
                fi
            elif [[ -f ${dest}   ]]; then
                status="✓" # Merged/copied file exists
            fi
        fi

        printf '  (%s) %s\n' "${status}" "${filename}"
    done

    echo
}

print_verification()   {
    if [[ ! -f ${MANIFEST}   ]]; then
        printf 'No manifest found. Nothing to verify.\n'
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
        ftype="${ftype%$'\r'}"
        [[ -z ${dest}   ]] && continue
        case "${ftype}" in
            merged)
                # healthy if file exists and has both sentinels
                if [[ -f ${dest}   ]] \
                    && grep -qxF "${MERGE_TOP_SENTINEL}" "${dest}" \
                    && grep -qxF "${MERGE_BOTTOM_SENTINEL}" "${dest}"; then
                    ok_merged=$((ok_merged + 1))
                else
                    broken_merged_files+=("${dest}")
                    printf '  [merged] %s (missing or broken sentinels)\n' "${dest}" >&2
                fi
                ;;
            generated)
                if [[ -f ${dest} && -s ${dest}     ]]; then
                    ok_generated=$((ok_generated + 1))
                else
                    broken_generated_files+=("${dest}")
                    printf '  [generated] %s (missing or empty)\n' "${dest}" >&2
                fi
                ;;
            symlink)
                if [[ -L ${dest} && -e ${dest} && "$(    readlink "${dest}")" == "${src}" ]]; then
                    ok_symlink=$((ok_symlink + 1))
                else
                    broken_symlink_files+=("${dest}")
                    printf '  [symlink] %s (broken or incorrect target)\n' "${dest}" >&2
                fi
                ;;
            *)
                printf 'Error: invalid type detected: %s.\nSomething went wrong!\n' "${ftype}" >&2
                return 1
                ;;
        esac
    done < "${MANIFEST}"

    broke_symlink="${#broken_symlink_files[@]}"
    broke_merged="${#broken_merged_files[@]}"
    broke_generated="${#broken_generated_files[@]}"

    local total_broken=$((broke_symlink + broke_merged + broke_generated))
    local total_ok=$((ok_merged + ok_generated + ok_symlink))
    local total=$((total_broken + total_ok))

    if [[ ${total_broken} -eq 0 ]]; then
        printf '  [verify] OK: All %d files verified successfully.\n' "${total_ok}"
        printf '           (%d symlinks, %d generated, %d merged)\n' "${ok_symlink}" "${ok_generated}" "${ok_merged}"
        return 0
    else
        printf '  [verify] NOT OK: %d out of %d files are broken.\n' "${total_broken}" "${total}" >&2
        printf '           Symlinks  : %2d OK, %2d broken\n' "${ok_symlink}" "${broke_symlink}" >&2
        printf '           Generated : %2d OK, %2d broken\n' "${ok_generated}" "${broke_generated}" >&2
        printf '           Merged    : %2d OK, %2d broken\n' "${ok_merged}" "${broke_merged}" >&2
        printf '\n' >&2
        printf '  [verify] Broken File Details:\n' >&2
        # print exactly which files are broken
        if [[ ${broke_symlink} -gt 0   ]]; then
            for f in "${broken_symlink_files[@]}"; do
                printf '    - [symlink]   %s (broken or incorrect target)\n' "${f}" >&2
            done
        fi

        if [[ ${broke_generated} -gt 0   ]]; then
            for f in "${broken_generated_files[@]}"; do
                printf '    - [generated] %s (missing or empty)\n' "${f}" >&2
            done
        fi

        if [[ ${broke_merged} -gt 0   ]]; then
            for f in "${broken_merged_files[@]}"; do
                printf '    - [merged]    %s (missing or broken sentinels)\n' "${f}" >&2
            done
        fi

        printf "\n" >&2
        return 1
    fi
}

print_banner() {
    cat << 'EOF'

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

print_end() {
    if ((DOTFILES_AUTORESTART)); then
        if is_windows_bash; then
            cat << 'EOF'

╭───────────────────────────────────────────╮
│                                           │
│          INSTALLATION COMPLETE!           │
│                                           │
│  Returning to shell...                    │
│                                           │
╰───────────────────────────────────────────╯

EOF
        else
            cat << 'EOF'

╭───────────────────────────────────────────╮
│                                           │
│          INSTALLATION COMPLETE!           │
│                                           │
│  Restarting shell...                      │
│                                           │
╰───────────────────────────────────────────╯

EOF
        fi
    else
        cat << 'EOF'

╭───────────────────────────────────────────╮
│                                           │
│          INSTALLATION COMPLETE!           │
│                                           │
│  Run `exec zsh` to apply your changes.    │
│                                           │
╰───────────────────────────────────────────╯

EOF
    fi
}
