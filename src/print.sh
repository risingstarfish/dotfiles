#!/usr/bin/env bash
# print.sh

if [[ -n ${__PRINT_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __PRINT_SH_INCLUDED__=1

print_help() {
    _enter
    cat << EOF
OVERVIEW: Installs and synchronizes dotfiles and shell configuration.

USAGE: bash $(basename "$0") <action> [options]

ALL ACTIONS:

INSTALL
      --install              Install (or reinstall) available dotfiles.
  -u, --update               Update from Git before installing.
  -r, --remove <module...>   Remove target modules <module>, semicolon-separated.
  -R, --repair               Remove orphaned symlinks and generated files, then re-link/generate.
      --reset                Remove all symlinks and generated files managed by this tool.
                             (note: copied/merged files will remain)
      --uninstall            Deletes symlinks, logs, and backups, then deletes install directory.

INFORMATION
  -l, --list                 Display all available modules.
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
      --no-deps              Skip dotfiles dependency post installation.

LOGGING
  -d, --debug                Print debug output (useful for diagnosing).
  -q, --quiet                Suppress all standard output except errors.
      --log-level <level>    Set log verbosity <level>. Valid options are: trace, debug, info,
                             notice, warn, or error. (default: info)
      --no-log               Disable logging to stdout (still writes to file).
      --time                 Print total execution time at script finish.

ENVIRONMENT VARIABLES
  Global (Always Active):
    DOTFILES_LOG_DIR         Path to store log files. (default: ~/.config/dotfiles/logs)
    DOTFILES_CACHE_DIR       Path to store temporary cache. (default: ~/.cache/dotfiles)
    DOTFILES_LOG             Set to 0 or false to disable log file writing. (default: 1)
    DOTFILES_LOCAL_MODS      Set to 1 or true to install with uncommitted local changes.
                             (default: 0)
    DOTFILES_AUTORESTART     Set to 1 or true to restart shell at script finish. (default: 0)

EOF
    _exit
}

# utility
git_or_unknown() {
    _enter
    local default="$1"
    shift

    local out
    if out=$(command git -C "${SRC_PATH}" "$@" 2> /dev/null); then
        printf '%s' "${out:-$default}"
    else
        printf '%s' "$default"
    fi
    _exit
}

print_version() {
    _enter
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
    _exit
}

list_modules() {
    _enter

    local -A installed_src=()
    manifest_read installed_src

    printf '\nAVAILABLE MODULES\n\n'

    local current_category=""
    local src dest action filename status category raw_cat

    local _env_sfx=".${TARGET_ENV}"
    local _os_sfx=".${TARGET_OS}"
    for src in "${AVAILABLE_MODULES[@]}"; do
        dest="${MODULE_DEST["${src}"]:-}"
        action="${MODULE_ACTION["${src}"]:-}"
        filename="${src##*/}"
        filename="${filename%.gen}"
        raw_cat="${src%%/*}"
        category="${MODULE_CATEGORY_MAP["${raw_cat}"]:-${raw_cat}}"

        if [[ ${filename} == *"${_env_sfx}" ]]; then
            filename="${filename%${_env_sfx}}"
        elif [[ ${filename} == *"${_os_sfx}" ]]; then
            filename="${filename%${_os_sfx}}"
        fi

        # category header
        if [[ ${category} != "${current_category}" ]]; then
            printf '%s\n' "${category}"
            current_category="${category}"
        fi

        status="✗"
        if [[ -n ${installed_src["${dest}"]:-} ]]; then
            case "${action}" in
                symlink)
                    if [[ -L ${dest} && -e ${dest} ]]; then
                        status="✓"
                    elif [[ -L ${dest} ]]; then
                        status="!"   # broken link (target missing)
                    else
                        status="!"   # link removed from disk
                    fi
                    ;;
                copy)
                    if [[ -f ${dest} ]]; then
                        status="✓"
                    else
                        status="!"
                    fi
                    ;;
                generate)
                    if [[ -f ${dest} && -s ${dest} ]]; then
                        status="✓"
                    elif [[ -f ${dest} ]]; then
                        status="!"   # exists but empty
                    else
                        status="!"   # missing
                    fi
                    ;;
            esac
        else
            # Not in manifest — fallback disk check
            if [[ -n ${dest} ]]; then
                case "${action}" in
                    symlink)
                        if [[ -L ${dest} && -e ${dest} ]]; then
                            status="✓"
                        elif [[ -L ${dest} ]]; then
                            status="!"
                        fi
                        ;;
                    generate)
                        if [[ -f ${dest} && -s ${dest} ]]; then
                            status="✓"
                        elif [[ -f ${dest} ]]; then
                            status="!"
                        fi
                        ;;
                    *)
                        [[ -f ${dest} ]] && status="✓"
                        ;;
                esac
            fi
        fi

        printf '  %s %s\n' "${status}" "${filename}"
    done

    printf '\n  ✓  installed & healthy\n'
    printf '  ✗  not installed\n'
    printf '  !  installed but broken / stale\n\n'

    _exit
}

print_banner() {
    _enter
    printf '%b\n' "$(
        cat          << 'EOF'
\e[1;96m  ____        _    __ _ _             \e[0m
\e[1;96m |  _ \  ___ | |_ / _(_) | ___  ___   \e[0m
\e[1;96m | | | |/ _ \| __| |_| | |/ _ \/ __|  \e[0m
\e[1;96m | |_| | (_) | |_|  _| | |  __/\__ \  \e[0m
\e[1;96m |____/ \___/ \__|_| |_|_|\___||___/  \e[0m
\e[1;90m -----------------------------------\e[0m
\e[1;97m     Automated Environment Setup    \e[0m
\e[1;90m -----------------------------------\e[0m
EOF
    )"
    _exit
}

print_end() {
    _enter
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
    _exit
}
