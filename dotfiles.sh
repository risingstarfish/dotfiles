#!/usr/bin/env bash

set -euo pipefail

if [[ -z ${HOME:-} || ! -d $HOME ]]; then
    printf 'Error: unable to resolve $HOME' >&2
    exit 1
fi

readonly DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/.config/dotfiles/logs}"
readonly DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-$HOME/.cache/dotfiles}"
readonly MANIFEST_FILE="${DOTFILES_CACHE_DIR}/manifest.tsv"

readonly MERGE_TOP_SENTINEL='# --- Local Configuration (managed by dotfiles) ---'
readonly MERGE_BOTTOM_SENTINEL='# --- Do not edit this line or above ---'

# OS
readonly OS_CACHYOS='cachyos'
readonly OS_MACOS='macos'
readonly OS_WINDOWS='windows'
readonly OS_DEBIAN='debian'
readonly OS_UNKNOWN='unknown'
# runtime
readonly RUNTIME_NATIVE='native'
readonly RUNTIME_WSL='wsl'
readonly RUNTIME_GITBASH='gitbash'
readonly RUNTIME_UNKNOWN='unknown'

# detect if user has sudo available and enabled
readonly WINDOWS_SUDO_REG_LOCATION='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'

# user env vars
# DOTFILES_LOG_DIR
# DOTFILES_CACHE_DIR
readonly DOTFILES_PROMPT_WINDOWS_HANDOFF="${DOTFILES_PROMPT_WINDOWS_HANDOFF:-1}"

# src files
readonly SOURCE_FILES=(
    "src/print.sh"
)

# functions
bash_version_check() {
    if [[ -z ${BASH_VERSION:-} || -n ${ZSH_VERSION:-}   ]]; then
        printf 'Error: the install instructions explicitly say to use the install script with bash; please follow them.\n' >&2
        return 1
    fi
    # script requires bash >=4.0
    if ((BASH_VERSINFO[0] < 4)); then
        printf 'Error: This script requires bash v4.0 or newer. You are running %s.\n' "${BASH_VERSION}" >&2

        if [[ "$(uname -s)" == "Darwin" ]]; then
            printf '  On macOS, the default bash is severely outdated (v3.2).\n' >&2
            printf '  Please install modern bash via Homebrew:\n' >&2
            printf '    brew install bash\n' >&2
            printf '  or via MacPorts:\n' >&2
            printf '    sudo port install bash\n' >&2
            echo >&2
            printf '  Then restart your terminal and run this script again using the new bash.\n' >&2
        fi

        return 1
    fi
}

# set the absolute directory path of this script
# Source - https://stackoverflow.com/a/246128
set_src_path() {
    [[ -n ${SRC_PATH:-} ]] && return 0

    local source_path="${BASH_SOURCE[0]}"
    # piped to bash
    if [[ -z ${source_path} ]]; then
              printf 'Error: unable to determine source path.\n' >&2
        return 1
    fi

    local symlink_dir
    while [[ -L $source_path   ]]; do
        symlink_dir="$(cd -P "$(dirname "$source_path")" > /dev/null 2>&1 && pwd)"
        source_path="$(readlink "$source_path")"

        if [[ $source_path != /* ]]; then
            source_path=$symlink_dir/$source_path
        fi
    done

    SRC_PATH="$(cd -P "$(dirname "$source_path")" > /dev/null 2>&1 && pwd)"
    readonly SRC_PATH
}

set_module_dir() {
    [[ -n ${MODULE_DIR:-}  ]] && return 0

    readonly MODULE_DIR="${SRC_PATH}/modules"
    if [[ ! -d ${MODULE_DIR} ]]; then
        printf 'Error: unable to locate modules/.\n' >&2
        return 1
    fi
}

# Detects and sets TARGET_OS and TARGET_RUNTIME. Validates by comparing
# against OS_UNKNOWN and RUNTIME_UNKNOWN
# Usage: set_env
#
# Returns:
#   0 if TARGET_OS and TARGET_RUNTIME are set
#   1 if TARGET_OS and TARGET_RUNTIME remain 'unknown'
set_os_runtime() {
    [[ -n ${TARGET_OS:-} || -n ${TARGET_RUNTIME:-} ]] && return 0

    local kernel_name
    kernel_name="$(uname -s 2> /dev/null || echo "unknown")"

    case "${kernel_name}" in
        Linux*)
            # wsl vs native
            if uname -r | grep -qi "microsoft"; then
                readonly TARGET_RUNTIME="${RUNTIME_WSL}"
            else
                readonly TARGET_RUNTIME="${RUNTIME_NATIVE}"
            fi

            # distro
            if [[ -f "/etc/os-release" ]]; then
                if grep -qiE '^ID=.*cachyos' /etc/os-release; then
                    readonly TARGET_OS="${OS_CACHYOS}"
                elif grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release || [[ -f "/etc/debian_version" ]]; then
                    readonly TARGET_OS="${OS_DEBIAN}"
                else
                    readonly TARGET_OS="${OS_UNKNOWN}"
                fi
            else
                readonly TARGET_OS="${OS_UNKNOWN}"
            fi
            ;;

        Darwin*)
            readonly TARGET_OS="${OS_MACOS}"
            readonly TARGET_RUNTIME="${RUNTIME_NATIVE}"
            ;;

        MINGW*)
            readonly TARGET_OS="${OS_WINDOWS}"
            # Git Bash and standard MSYS2 MinGW output "MINGW*"
            # Git Bash explicitly places git-bash.exe at the root and sets $EXEPATH
            if [[ -f "/git-bash.exe" || -n ${EXEPATH:-} ]]; then
                readonly TARGET_RUNTIME="${RUNTIME_GITBASH}"
            else
                readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            fi
            ;;

        *)
            # Unknown
            if [[ ${OS:-} == "Windows_NT" ]]; then
                readonly TARGET_OS="${OS_WINDOWS}"
                readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            else
                readonly TARGET_OS="${OS_UNKNOWN}"
                readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            fi
            ;;
    esac

    readonly TARGET_ENV="${TARGET_OS}-${TARGET_RUNTIME}"

    if [[ ${TARGET_OS} == "{$OS_UNKNOWN}" || ${TARGET_RUNTIME} == "{$RUNTIME_UNKNOWN}" ]]; then
        return 1
    fi
}

# detect if windows user has sudo enabled
set_windows_sudo() {
    [[ -n ${WINDOWS_SUDO:-}  ]] && return 0

    WINDOWS_SUDO=0
    command -v sudo > /dev/null 2>&1 || return
    command -v reg.exe > /dev/null 2>&1 || return

    local sudo_reg
    sudo_reg=$(MSYS_NO_PATHCONV=1 reg.exe query "${WINDOWS_SUDO_REG_LOCATION}" /v Enabled 2> /dev/null)
    # output of 0x1, 0x2, or 0x3 means enabled
    if [[ ${sudo_reg} =~ 0x[1-3]  ]]; then
        WINDOWS_SUDO=1
    fi

    readonly WINDOWS_SUDO
    export MSYS=winsymlinks:nativestrict # enable native symlinking
    return 0
}

# Detect if script was run as sudo or root.
set_elevated() {
    [[ -n ${IS_ELEVATED:-}  ]] && return 0

    IS_ELEVATED=0
    if [[ ${EUID} -eq 0 || -n ${SUDO_USER:-}    ]]; then
        readonly IS_ELEVATED=1
    elif [[ ${TARGET_OS} == "${OS_WINDOWS}"  ]] && net session > /dev/null 2>&1; then
        # net session fails with exit code 5 if not admin
        readonly IS_ELEVATED=1
    fi
}

set_module_map() {
    [[ -n ${MODULE_MAP:-}  ]] && return 0

    if [[ ${TARGET_OS} == "${OS_WINDOWS}"   ]]; then
        local -r topgrade_dest="${APPDATA:-${HOME}/.config}/topgrade.toml"
    else
        local -r topgrade_dest="${XDG_CONFIG_HOME:-${HOME}/.config}/topgrade.toml"
    fi

    readonly MODULE_MAP=(
        "zsh/zshrc|${HOME}/.zshrc"
        "zsh/zsh_options|${HOME}/.zsh_options"
        "zsh/zstyles|${HOME}/.zstyles"
        "zsh/zimrc|${HOME}/.zimrc"
        "zsh/p10k.zsh|${HOME}/.p10k.zsh"
        "zsh/exports|${HOME}/.exports"
        "zsh/paths|${HOME}/.paths"
        "zsh/aliases|${HOME}/.aliases"
        "zsh/functions|${HOME}/.functions"
        "zsh/zshrc.toggles|${HOME}/.zshrc.toggles"

        "bash/bashrc|${HOME}/.bashrc"

        "git/gitconfig|${HOME}/.gitconfig"
        "git/gitconfig.local.${TARGET_OS}|${HOME}/.gitconfig.local"
        "git/gitignore|${HOME}/.gitignore"
        "git/gitattributes|${HOME}/.gitattributes"
        "git/diff-so-fancy|${HOME}/.local/bin/diff-so-fancy|chmod +x ${HOME}/.local/bin/diff-so-fancy"

        "ssh/config|${HOME}/.ssh/config|chmod 600 ${HOME}/.ssh/config"
        "ssh/allowed_signers.gen|${HOME}/.ssh/allowed_signers"

        "dev/gen-cmakepreset.py|${HOME}/.local/bin/gen-cmakepreset.py|chmod 600 ${HOME}/.local/bin/gen-cmakepreset.py"
        "dev/internal-flags.cmake|${HOME}/dev/internal-flags.cmake"
        "dev/cmake-format.py|${HOME}/dev/.cmake-format.py"
        "dev/clang-format|${HOME}/dev/.clang-format"
        "dev/clang-tidy|${HOME}/dev/.clang-tidy"
        "dev/editorconfig|${HOME}/dev/.editorconfig"

        "pwsh.${TARGET_ENV}/Microsoft.PowerShell_profile.ps1|${HOME}/Documents/Powershell/Microsoft.PowerShell_profile.ps1"
        "pwsh.${TARGET_ENV}/Set-MSVC-Environment.ps1|${HOME}/Documents/Powershell/Scripts/Set-MSVC-Environment.ps1"
        "pwsh.${TARGET_ENV}/Update-Modules.ps1|${HOME}/Documents/Powershell/Scripts/Update-Modules.ps1"
        "pwsh.${TARGET_ENV}/Print-Env.ps1|${HOME}/Documents/Powershell/Scripts/Print-Env.ps1"
        "pwsh.${TARGET_ENV}/nproc.ps1|${HOME}/Documents/Powershell/Scripts/nproc.ps1"
        "pwsh.${TARGET_ENV}/sha256.ps1|${HOME}/Documents/Powershell/Scripts/sha256.ps1"
        "pwsh.${TARGET_ENV}/sha1.ps1|${HOME}/Documents/Powershell/Scripts/sha1.ps1"
        "pwsh.${TARGET_ENV}/md5.ps1|${HOME}/Documents/Powershell/Scripts/md5.ps1"

        # --- Oh My Posh ---
        "oh-my-posh.${TARGET_ENV}/themes/tiger.omp.json|${HOME}/.oh-my-posh/themes/tiger.omp.json"
        "oh-my-posh.${TARGET_ENV}/themes/agnoster.omp.json|${HOME}/.oh-my-posh/themes/agnoster.omp.json"
        "oh-my-posh.${TARGET_ENV}/themes/kushal.omp.json|${HOME}/.oh-my-posh/themes/kushal.omp.json"
        "oh-my-posh.${TARGET_ENV}/themes/powerlevel10k_classic.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_classic.omp.json"
        "oh-my-posh.${TARGET_ENV}/themes/powerlevel10k_lean.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_lean.omp.json"
        "oh-my-posh.${TARGET_ENV}/themes/powerlevel10k_modern.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_modern.omp.json"

        "topgrade/topgrade.toml|${topgrade_dest}"
        "fastfetch/config.jsonc.${TARGET_OS}|${HOME}/.config/fastfetch/config.jsonc"
        "tmux/tmux.conf.${TARGET_OS}|${HOME}/.tmux.conf"
        "curl/curlrc|${HOME}/.curlrc"
        "wget/wgetrc|${HOME}/.wgetrc"
        "shellcheck/shellcheckrc|${HOME}/.shellcheckrc"

        "claude/settings.json|${HOME}/.claude/settings.json"
        "claude/plugin.json|${HOME}/.claude/plugin.json"
    )
}

set_available_modules() {
    [[ -n ${AVAILABLE_MODULES:-}  ]] && return 0

    set_module_map

    local -a active_modules=()

    for item in "${MODULE_MAP[@]}"; do
        IFS='|' read -r src dest post_cmd <<< "${item}"

        # skip if not available on os/runtime
        if [[ ! -e "${MODULE_DIR}/${src}"   ]]; then
            continue
        fi

        # skip specific combos
        if [[ ${src} == "topgrade/topgrade.toml" && ${TARGET_OS} == "${OS_WINDOWS}" ]]; then
            continue
        fi

        active_modules+=("${item}")
    done

    AVAILABLE_MODULES=("${active_modules[@]}")
    readonly AVAILABLE_MODULES
}

# Prompts the user to continue.
# Exits the script if the user chooses No (n/N).
# Usage: prompt_continue
#
# Arguments:
#   $1 (format) : (Optional) The warning message, or a printf-style format string.
#   $@ (args)   : (Optional) Arguments to populate the format string.
prompt_continue() {
    local msg
    if [[ $# -eq 0 ]]; then
        msg=""
    elif [[ $# -gt 1 ]]; then
        printf -v msg "$@"
    else
        printf -v msg '%b' "$1"
    fi

    if [[ -n $msg ]]; then
        printf "%s\n" "$msg" >&2
    fi

    local choice
    while true; do
        echo
        if ! read -r -p 'Do you want to continue anyway? [y/N]: ' choice; then
            printf 'Error: No input available for prompt.\n' >&2
            return 1
        fi

        case "$choice" in
            [yY])
                return 0
                ;;
            [nN])
                printf 'Aborting installation!\n' >&2
                exit 130
                ;;
            *)
                printf 'Error: Invalid input. Please enter y or n.\n' >&2
                ;;
        esac
    done
}

check_exists() {
    local -r -a paths=("$@")
    local -a missing_paths=()
    local -r prefix="${SRC_PATH}/"

    for path in "${paths[@]}"; do
        local target_path="$path"

        # If path is relative (does not start with '/' or '~')
        if [[ $path != /* ]] && [[ $path != ~* ]]; then
            # Resolve relative paths against SRC_PATH
            target_path="${prefix}${path}"
        fi

        # Check existence of the resolved path
        if [[ ! -e $target_path ]]; then
            # Strip the SRC_PATH prefix for clean output.
            # Absolute paths outside SRC_PATH remain unmodified.
            missing_paths+=("${target_path#"$prefix"}")
        fi
    done

    if [[ ${#missing_paths[@]} -gt 0 ]]; then
        printf "Missing %d path(s):\n" "${#missing_paths[@]}" >&2

        for missing in "${missing_paths[@]}"; do
            printf "✗ %s\n" "${missing}" >&2
        done

        return 1
    fi

    return 0
}

initialise() {
    bash_version_check || return 1
    set_src_path || return 1   # SRC_PATH
    set_module_dir || return 1 # MODULE_DIR
    set_os_runtime || {      # TARGET_OS TARGET_RUNTIME TARGET_ENV
        printf 'Warning: unable to determine $TARGET_OS or $TARGET_RUNTIME.\n' >&2
        prompt_continue 'Some functionality may be limited.'
    }

    if [[ ${TARGET_OS} == "${OS_WINDOWS}"   ]]; then
        set_windows_sudo # WINDOWS_SUDO
    fi

    set_elevated          # IS_ELEVATED
    set_module_map        # MODULE_MAP
    set_available_modules # AVAILABLE_MODULES
}

source_files() {
    for file in "${SOURCE_FILES[@]}"; do
        if [[ -z ${file} ]]; then
            printf 'Error: source_file called without a file path argument.\n' >&2
            return 1
        fi

        if [[ ! -f ${file} ]]; then
            printf 'Error: Cannot source "%s": File does not exist or is a directory.\n' "${file}" >&2
            return 1
        fi

        if [[ ! -r ${file} ]]; then
            printf 'Error: Cannot source "%s": Read permission denied.\n' "${file}" >&2
            return 1
        fi

        source "${file}" || {
            local ec=$?
            printf 'Error: File "%s" was read, but execution failed with exit code %d.\n' "${file}" "${ec}" >&2
            return 1
        }
    done
}

main() {
    initialise || exit 1
    check_exists "${SOURCE_FILES[@]}" || exit 1
    source_files "${SOURCE_FILES[@]}" || exit 1

    #argparse "$@"

    print_banner

    # TODO: logic

    print_end

    if (("${DOTFILES_AUTORESTART:-0}")); then
        exec zsh
    fi
    exit 0

}

main "$@"
