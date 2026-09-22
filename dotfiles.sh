#!/usr/bin/env bash

set -euo pipefail

if [[ -z ${HOME:-} || ! -d $HOME ]]; then
    printf 'Error: unable to resolve $HOME' >&2
    exit 1
fi

readonly DOTFILES_ENV="${DOTFILES_ENV:-production}" # development testing production
readonly DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/.config/dotfiles/logs}"
readonly INIT_LOG_FILE="${DOTFILES_LOG_DIR}/initialise.log"
readonly DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-$HOME/.cache/dotfiles}"
readonly MANIFEST_FILE="${DOTFILES_CACHE_DIR}/manifest.tsv"

readonly MERGE_TOP_SENTINEL='# --- Local Configuration (managed by dotfiles) ---'
readonly MERGE_BOTTOM_SENTINEL='# --- Do not edit this line or above ---'

readonly DOTFILES_LOCAL_MODS="${DOTFILES_LOCAL_MODS:-0}"

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
readonly DOTFILES_PROMPT_WINDOWS_HANDOFF="${DOTFILES_PROMPT_WINDOWS_HANDOFF:-1}"

# src files
readonly SOURCE_FILES=(
    "src/utility.sh"
    "src/print.sh"
    "src/argparse.sh"
    # "src/logging.sh" see initialise
    "src/filesystem.sh"
    "src/action.sh"
    "src/dependencies.sh"
)

# functions
bash_version_check() {
    log_trace "${FUNCNAME[0]}: Entering (BASH_VERSION='${BASH_VERSION:-}', ZSH_VERSION='${ZSH_VERSION:-}')"

    if [[ -z ${BASH_VERSION:-} || -n ${ZSH_VERSION:-} ]]; then
        log_error "${FUNCNAME[0]}: Script not executing under pure Bash."
        printf 'Error: the install instructions explicitly say to use the install script with bash; please follow them.\n' >&2
        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    # script requires bash >=4.0
    if ((BASH_VERSINFO[0] < 4)); then
        log_error "${FUNCNAME[0]}: Bash version v4.0 or newer required. Detected version: ${BASH_VERSION}"
        printf 'Error: This script requires bash v4.0 or newer. You are running %s.\n' "${BASH_VERSION}" >&2

        if [[ "$(uname -s)" == "Darwin" ]]; then
            log_debug "${FUNCNAME[0]}: macOS detected with outdated default bash version."
            printf '  On macOS, the default bash is severely outdated (v3.2).\n' >&2
            printf '  Please install modern bash via Homebrew:\n' >&2
            printf '    brew install bash\n' >&2
            printf '  or via MacPorts:\n' >&2
            printf '    sudo port install bash\n' >&2
            echo >&2
            printf '  Then restart your terminal and run this script again using the new bash.\n' >&2
        fi

        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    log_debug "${FUNCNAME[0]}: Bash version ${BASH_VERSION} validated successfully."
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
}

# set the absolute directory path of this script
# Source - https://stackoverflow.com/a/246128
set_src_path() {
    log_trace "${FUNCNAME[0]}: Entering (SRC_PATH='${SRC_PATH:-}')"

    if [[ -n ${SRC_PATH:-} ]]; then
        log_debug "${FUNCNAME[0]}: SRC_PATH is already set to '${SRC_PATH}'. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already set)"
        return 0
    fi

    local source_path="${BASH_SOURCE[0]}"
    log_trace "${FUNCNAME[0]}: BASH_SOURCE[0]='${source_path}'"

    # piped to bash
    if [[ -z ${source_path} ]]; then
        log_error "${FUNCNAME[0]}: Unable to determine source path from BASH_SOURCE."
        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    local symlink_dir
    while [[ -L $source_path ]]; do
        log_trace "${FUNCNAME[0]}: Resolving symlink for '${source_path}'"
        symlink_dir="$(cd -P "$(dirname "$source_path")" > /dev/null 2>&1 && pwd)"
        source_path="$(readlink "$source_path")"

        if [[ $source_path != /* ]]; then
            source_path=$symlink_dir/$source_path
        fi
        log_trace "${FUNCNAME[0]}: Resolved symlink target to '${source_path}'"
    done

    SRC_PATH="$(cd -P "$(dirname "$source_path")" > /dev/null 2>&1 && pwd)"
    log_debug "${FUNCNAME[0]}: Resolved SRC_PATH='${SRC_PATH}'"
    log_trace "${FUNCNAME[0]}: Setting SRC_PATH as readonly and exiting successfully"
    readonly SRC_PATH
}

set_module_dir() {
    log_trace "${FUNCNAME[0]}: Entering (MODULE_DIR='${MODULE_DIR:-}', SRC_PATH='${SRC_PATH:-}')"

    if [[ -n ${MODULE_DIR:-} ]]; then
        log_debug "${FUNCNAME[0]}: MODULE_DIR is already set to '${MODULE_DIR}'. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already set)"
        return 0
    fi

    MODULE_DIR="${SRC_PATH}/modules"
    log_trace "${FUNCNAME[0]}: Set MODULE_DIR='${MODULE_DIR}'"

    if [[ ! -d ${MODULE_DIR} ]]; then
        log_error "${FUNCNAME[0]}: Unable to locate module directory at '${MODULE_DIR}'"
        printf 'Error: unable to locate modules/.\n' >&2
        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    log_debug "${FUNCNAME[0]}: Verified module directory exists at '${MODULE_DIR}'"
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
    readonly MODULE_DIR
}

# Detects and sets TARGET_OS and TARGET_RUNTIME. Validates by comparing
# against OS_UNKNOWN and RUNTIME_UNKNOWN
# Usage: set_env
#
# Returns:
#   0 if TARGET_OS and TARGET_RUNTIME are set
#   1 if TARGET_OS and TARGET_RUNTIME remain 'unknown'
set_target_env() {
    log_trace "${FUNCNAME[0]}: Entering (TARGET_OS='${TARGET_OS:-}', TARGET_RUNTIME='${TARGET_RUNTIME:-}', TARGET_ENV='${TARGET_ENV:-}')"

    if [[ -n ${TARGET_OS:-} || -n ${TARGET_RUNTIME:-} || -n ${TARGET_ENV:-} ]]; then
        log_debug "${FUNCNAME[0]}: Environment variables already set. Skipping environment detection."
        log_trace "${FUNCNAME[0]}: Exiting (already set)"
        return 0
    fi

    local kernel_name
    kernel_name="$(uname -s 2> /dev/null || echo "unknown")"
    log_trace "${FUNCNAME[0]}: Detected kernel_name='${kernel_name}'"

    case "${kernel_name}" in
        Linux*)
            log_debug "${FUNCNAME[0]}: Linux kernel detected."
            # wsl vs native
            if uname -r | grep -qi "microsoft"; then
                log_trace "${FUNCNAME[0]}: WSL runtime detected."
                readonly TARGET_RUNTIME="${RUNTIME_WSL}"
            else
                log_trace "${FUNCNAME[0]}: Native Linux runtime detected."
                readonly TARGET_RUNTIME="${RUNTIME_NATIVE}"
            fi

            # distro
            if [[ -f "/etc/os-release" ]]; then
                if grep -qiE '^ID=.*cachyos' /etc/os-release; then
                    log_trace "${FUNCNAME[0]}: CachyOS detected in /etc/os-release."
                    readonly TARGET_OS="${OS_CACHYOS}"
                elif grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release || [[ -f "/etc/debian_version" ]]; then
                    log_trace "${FUNCNAME[0]}: Debian-based OS detected in /etc/os-release."
                    readonly TARGET_OS="${OS_DEBIAN}"
                else
                    log_warn "${FUNCNAME[0]}: Unsupported Linux distribution."
                    readonly TARGET_OS="${OS_UNKNOWN}"
                fi
            else
                log_warn "${FUNCNAME[0]}: /etc/os-release not found. Unable to identify Linux distribution."
                readonly TARGET_OS="${OS_UNKNOWN}"
            fi
            ;;

        Darwin*)
            log_debug "${FUNCNAME[0]}: macOS (Darwin) environment detected."
            readonly TARGET_OS="${OS_MACOS}"
            readonly TARGET_RUNTIME="${RUNTIME_NATIVE}"
            ;;

        MINGW*)
            log_debug "${FUNCNAME[0]}: Windows MINGW environment detected."
            readonly TARGET_OS="${OS_WINDOWS}"
            if [[ -f "/git-bash.exe" || -n ${EXEPATH:-} ]]; then
                log_trace "${FUNCNAME[0]}: Git Bash runtime detected."
                readonly TARGET_RUNTIME="${RUNTIME_GITBASH}"
            else
                log_trace "${FUNCNAME[0]}: Unknown MinGW environment detected."
                readonly TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            fi
            ;;

        *)
            log_debug "${FUNCNAME[0]}: Fallback environment detection for kernel '${kernel_name}'."
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
    log_debug "${FUNCNAME[0]}: Detected environment: TARGET_OS='${TARGET_OS}', TARGET_RUNTIME='${TARGET_RUNTIME}', TARGET_ENV='${TARGET_ENV}'"

    if [[ ${TARGET_OS} == "${OS_UNKNOWN}" || ${TARGET_RUNTIME} == "${RUNTIME_UNKNOWN}" ]]; then
        log_error "${FUNCNAME[0]}: Failed to fully detect target environment."
        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
}

# detect if windows user has sudo enabled
set_windows_sudo() {
    log_trace "${FUNCNAME[0]}: Entering"

    if [[ -n ${WINDOWS_SUDO:-} ]]; then
        log_debug "${FUNCNAME[0]}: WINDOWS_SUDO is already set to '${WINDOWS_SUDO}'. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already set)"
        return 0
    fi

    WINDOWS_SUDO=0

    if ! command -v sudo > /dev/null 2>&1; then
        log_trace "${FUNCNAME[0]}: 'sudo' executable not found in PATH."
        readonly WINDOWS_SUDO
        return 0
    fi

    if ! command -v reg.exe > /dev/null 2>&1; then
        log_trace "${FUNCNAME[0]}: 'reg.exe' executable not found in PATH."
        readonly WINDOWS_SUDO
        return 0
    fi

    local sudo_reg
    log_trace "${FUNCNAME[0]}: Querying Windows Registry: ${WINDOWS_SUDO_REG_LOCATION}"
    sudo_reg=$(MSYS_NO_PATHCONV=1 reg.exe query "${WINDOWS_SUDO_REG_LOCATION}" /v Enabled 2> /dev/null)

    if [[ ${sudo_reg} =~ 0x[1-3] ]]; then
        log_debug "${FUNCNAME[0]}: Windows sudo detected as ENABLED in registry."
        WINDOWS_SUDO=1
    else
        log_debug "${FUNCNAME[0]}: Windows sudo disabled or key not found."
    fi

    log_trace "${FUNCNAME[0]}: Setting MSYS=winsymlinks:nativestrict"
    export MSYS=winsymlinks:nativestrict

    log_debug "${FUNCNAME[0]}: WINDOWS_SUDO set to ${WINDOWS_SUDO}"
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
    readonly WINDOWS_SUDO
}

# Detect if script was run as sudo or root.
set_is_elevated() {
    log_trace "${FUNCNAME[0]}: Entering (IS_ELEVATED='${IS_ELEVATED:-}', EUID='${EUID}', SUDO_USER='${SUDO_USER:-}')"

    if [[ -n ${IS_ELEVATED:-} ]]; then
        log_debug "${FUNCNAME[0]}: IS_ELEVATED is already set to '${IS_ELEVATED}'. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already set)"
        return 0
    fi

    IS_ELEVATED=0
    if [[ ${EUID} -eq 0 || -n ${SUDO_USER:-} ]]; then
        log_debug "${FUNCNAME[0]}: Running as root/sudo user."
        readonly IS_ELEVATED=1
    elif [[ ${TARGET_OS} == "${OS_WINDOWS}" ]] && net session > /dev/null 2>&1; then
        log_debug "${FUNCNAME[0]}: Windows administrative session detected."
        readonly IS_ELEVATED=1
    else
        log_debug "${FUNCNAME[0]}: Non-elevated execution context."
        readonly IS_ELEVATED=0
    fi

    log_debug "${FUNCNAME[0]}: Privilege level IS_ELEVATED=${IS_ELEVATED}"
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
}

set_module_map() {
    log_trace "${FUNCNAME[0]}: Entering)"

    if [[ -n ${MODULE_MAP+x} ]] && ((${#MODULE_MAP[@]} > 0)); then
        log_debug "${FUNCNAME[0]}: MODULE_MAP already populated (${#MODULE_MAP[@]} items). Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already populated)"
        return 0
    fi

    if [[ ${TARGET_OS} == "${OS_WINDOWS}" ]]; then
        local -r topgrade_dest="${APPDATA}/topgrade/topgrade.toml"
    else
        local -r topgrade_dest="${XDG_CONFIG_HOME:-${HOME}/.config}/topgrade.toml"
    fi
    log_trace "${FUNCNAME[0]}: Resolved topgrade_dest='${topgrade_dest}'"

    # name | src | dest | (post-install cmd)
    readonly MODULE_MAP=(
        ".zshrc|zsh/zshrc|${HOME}/.zshrc"
        ".zsh_options|zsh/zsh_options|${HOME}/.zsh_options"
        ".zstyles|zsh/zstyles|${HOME}/.zstyles"
        ".zimrc|zsh/zimrc|${HOME}/.zimrc"
        ".p10k.zsh|zsh/p10k.zsh|${HOME}/.p10k.zsh"
        ".exports|zsh/exports|${HOME}/.exports"
        ".paths|zsh/paths|${HOME}/.paths"
        ".aliases|zsh/aliases|${HOME}/.aliases"
        ".functions|zsh/functions|${HOME}/.functions"
        ".zshrc.toggles|zsh/zshrc.toggles|${HOME}/.zshrc.toggles"

        ".bashrc|bash/bashrc|${HOME}/.bashrc"

        ".gitconfig|git/gitconfig|${HOME}/.gitconfig"
        ".gitconfig.local|git/gitconfig.local.${TARGET_OS}|${HOME}/.gitconfig.local"
        ".gitignore|git/gitignore|${HOME}/.gitignore"
        ".gitattributes|git/gitattributes|${HOME}/.gitattributes"
        "diff-so-fancy|git/diff-so-fancy|${HOME}/.local/bin/diff-so-fancy|chmod +x ${HOME}/.local/bin/diff-so-fancy"

        "config|ssh/config|${HOME}/.ssh/config|chmod 600 ${HOME}/.ssh/config"
        "allowed_signers|ssh/allowed_signers.gen|${HOME}/.ssh/allowed_signers"

        "gen-cmakepreset.py|dev/gen-cmakepreset.py|${HOME}/.local/bin/gen-cmakepreset.py|chmod 600 ${HOME}/.local/bin/gen-cmakepreset.py"
        "internal-flags.cmake|dev/internal-flags.cmake|${HOME}/dev/internal-flags.cmake"
        ".cmake-format.py|dev/cmake-format.py|${HOME}/dev/.cmake-format.py"
        ".clang-format|dev/clang-format|${HOME}/dev/.clang-format"
        ".clang-tidy|dev/clang-tidy|${HOME}/dev/.clang-tidy"
        ".editorconfig|dev/editorconfig|${HOME}/dev/.editorconfig"

        "Microsoft.PowerShell_profile.ps1|pwsh.${TARGET_ENV}/Microsoft.PowerShell_profile.ps1|${HOME}/Documents/Powershell/Microsoft.PowerShell_profile.ps1"
        "Set-MSVC-Environment.ps1|pwsh.${TARGET_ENV}/Set-MSVC-Environment.ps1|${HOME}/Documents/Powershell/Scripts/Set-MSVC-Environment.ps1"
        "Update-Modules.ps1|pwsh.${TARGET_ENV}/Update-Modules.ps1|${HOME}/Documents/Powershell/Scripts/Update-Modules.ps1"
        "Print-Env.ps1|pwsh.${TARGET_ENV}/Print-Env.ps1|${HOME}/Documents/Powershell/Scripts/Print-Env.ps1"
        "nproc.ps1|pwsh.${TARGET_ENV}/nproc.ps1|${HOME}/Documents/Powershell/Scripts/nproc.ps1"
        "sha256.ps1|pwsh.${TARGET_ENV}/sha256.ps1|${HOME}/Documents/Powershell/Scripts/sha256.ps1"
        "sha1.ps1|pwsh.${TARGET_ENV}/sha1.ps1|${HOME}/Documents/Powershell/Scripts/sha1.ps1"
        "md5.ps1|pwsh.${TARGET_ENV}/md5.ps1|${HOME}/Documents/Powershell/Scripts/md5.ps1"

        "tiger.omp.json|oh-my-posh.${TARGET_ENV}/themes/tiger.omp.json|${HOME}/.oh-my-posh/themes/tiger.omp.json"
        "agnoster.omp.json|oh-my-posh.${TARGET_ENV}/themes/agnoster.omp.json|${HOME}/.oh-my-posh/themes/agnoster.omp.json"
        "kushal.omp.json|oh-my-posh.${TARGET_ENV}/themes/kushal.omp.json|${HOME}/.oh-my-posh/themes/kushal.omp.json"
        "powerlevel10k_classic.omp.json|oh-my-posh.${TARGET_ENV}/themes/powerlevel10k_classic.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_classic.omp.json"
        "powerlevel10k_lean.omp.json|oh-my-posh.${TARGET_ENV}/themes/powerlevel10k_lean.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_lean.omp.json"
        "powerlevel10k_modern.omp.json|oh-my-posh.${TARGET_ENV}/themes/powerlevel10k_modern.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_modern.omp.json"

        "topgrade.toml|topgrade/topgrade.toml|${topgrade_dest}"
        "config.jsonc|fastfetch/config.jsonc.${TARGET_OS}|${HOME}/.config/fastfetch/config.jsonc"
        ".tmux.conf|tmux/tmux.conf.${TARGET_OS}|${HOME}/.tmux.conf"
        ".curlrc|curl/curlrc|${HOME}/.curlrc"
        ".wgetrc|wget/wgetrc|${HOME}/.wgetrc"
        ".shellcheckrc|shellcheck/shellcheckrc|${HOME}/.shellcheckrc"

        "settings.json|claude/settings.json|${HOME}/.claude/settings.json"
        "plugin.json|claude/plugin.json|${HOME}/.claude/plugin.json"
    )

    log_debug "${FUNCNAME[0]}: Initialized MODULE_MAP with ${#MODULE_MAP[@]} items."
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
}

set_available_modules() {
    log_trace "${FUNCNAME[0]}: Entering"

    if [[ -n ${AVAILABLE_MODULES+x} ]] && ((${#AVAILABLE_MODULES[@]} > 0)); then
        log_debug "${FUNCNAME[0]}: AVAILABLE_MODULES is already set. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already set)"
        return 0
    fi

    local -a active_modules=()
    local item name src dest post_cmd

    for item in "${MODULE_MAP[@]}"; do
        IFS='|' read -r name src dest post_cmd <<< "${item}"

        # skip if not available on os/runtime
        if [[ ! -e "${MODULE_DIR}/${src}" ]]; then
            log_trace "${FUNCNAME[0]}: Skipping module '${src}': source does not exist at '${MODULE_DIR}/${src}'"
            continue
        fi

        # skip specific combos
        if [[ ${src} == "topgrade/topgrade.toml" && ${TARGET_OS} == "${OS_WINDOWS}" ]]; then
            log_trace "${FUNCNAME[0]}: Skipping '${src}' for OS '${TARGET_OS}'"
            continue
        fi

        log_debug "${FUNCNAME[0]}: Module available: '${src}'"
        active_modules+=("${src}")
    done

    AVAILABLE_MODULES=("${active_modules[@]}")
    log_debug "${FUNCNAME[0]}: Resolved ${#AVAILABLE_MODULES[@]} available modules."
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
    readonly AVAILABLE_MODULES
}

check_exists() {
    log_trace "${FUNCNAME[0]}: Entering"

    local -r -a paths=("$@")
    local -a missing_paths=()
    local -r prefix="${SRC_PATH}/"

    for path in "${paths[@]}"; do
        local target_path="$path"

        if [[ $path != /* ]] && [[ $path != ~* ]]; then
            target_path="${prefix}${path}"
        fi

        log_trace "${FUNCNAME[0]}: Testing existence of '${target_path}'"
        if [[ ! -e $target_path ]]; then
            log_error "${FUNCNAME[0]}: Missing path: '${target_path}'"
            missing_paths+=("${target_path#"$prefix"}")
        fi
    done

    if [[ ${#missing_paths[@]} -gt 0 ]]; then
        log_error "${FUNCNAME[0]}: Missing ${#missing_paths[@]} required path(s)."
        printf "Missing %d path(s):\n" "${#missing_paths[@]}" >&2

        for missing in "${missing_paths[@]}"; do
            printf "✗ %s\n" "${missing}" >&2
        done

        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    log_debug "${FUNCNAME[0]}: All path checks passed successfully."
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
    return 0
}

source_files() {
    log_trace "${FUNCNAME[0]}: Entering (SOURCE_FILES count: ${#SOURCE_FILES[@]})"

    for file in "${SOURCE_FILES[@]}"; do
        log_trace "${FUNCNAME[0]}: Processing source file: '${file}'"

        if [[ -z ${file} ]]; then
            log_error "${FUNCNAME[0]}: Called without a file path argument."
            # printf 'Error: source_file called without a file path argument.\n' >&2
            return 1
        fi

        if [[ ! -f ${file} ]]; then
            log_error "${FUNCNAME[0]}: File '${file}' does not exist or is a directory."
            # printf 'Error: cannot source "%s": File does not exist or is a directory.\n' "${file}" >&2
            return 1
        fi

        if [[ ! -r ${file} ]]; then
            log_error "${FUNCNAME[0]}: Read permission denied for '${file}'."
            # printf 'Error: cannot source "%s": Read permission denied.\n' "${file}" >&2
            return 1
        fi

        log_trace "${FUNCNAME[0]}: Sourcing '${file}'..."
        source "${file}" || {
            local ec=$?
            log_error "${FUNCNAME[0]}: Failed to source '${file}' (exit code: ${ec})."
            # printf 'Error: file "%s" was read, but execution failed with exit code %d.\n' "${file}" "${ec}" >&2
            return 1
        }
    done

    log_debug "${FUNCNAME[0]}: Successfully sourced ${#SOURCE_FILES[@]} file(s)."
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
}

initialise() {
    source "src/logging.sh" || {
        exit 1
    }
    if ! init_logger --log "${INIT_LOG_FILE}" --level TRACE --quiet --no-init-message --format "[%l] %d %z [%s] %m"; then
        die 1 'failed to initialise logger.\nCheck that log directory exists and is writable.'
    fi

    log_trace "${FUNCNAME[0]}: Entering initialisation sequence..."

    bash_version_check || die 1 'Bash version validation failed.'

    # SRC_PATH
    set_src_path || die 1 'Failed to determine script source path.'

    if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
        log_error "${FUNCNAME[0]}: SOURCE_FILES array is empty."
        die 1 "No source files defined."
    fi

    # check src/
    check_exists "${SOURCE_FILES[@]}" || die 1 "One or more required source files are missing."
    source_files "${SOURCE_FILES[@]}" || die 1 "Failed to source framework files."

    set_module_dir || die 1 "Failed to establish module directory."
    set_target_env || {      # TARGET_ENV TARGET_OS TARGET_RUNTIME
        log_warn "${FUNCNAME[0]}: Target environment detection failed. Prompting user to proceed."
        printf 'Warning: unable to determine $TARGET_OS or $TARGET_RUNTIME.\n' >&2
        prompt_continue 'Some functionality may be limited.'
    }

    set_is_elevated      # IS_ELEVATED
    if [[ ${TARGET_OS} == "${OS_WINDOWS}"   ]]; then
        set_windows_sudo # WINDOWS_SUDO
    fi

    set_module_map        # MODULE_MAP
    set_available_modules # AVAILABLE_MODULES

    log_trace "${FUNCNAME[0]}: Initialisation complete."
}

main() {
    local SRC_PATH MODULE_DIR \
        TARGET_OS TARGET_RUNTIME TARGET_ENV \
        IS_ELEVATED
    local -a MODULE_MAP AVAILABLE_MODULES

    initialise

    # NOTE: no DOTFILES_AUTORESTART
    local MAIN_ACTION \
        REMOVE_SET INCLUDE_SET EXCLUDE_SET \
        DRY_RUN NOCONFIRM FORCE \
        NO_BACKUP  NO_DEPS \
        LOG_LEVEL NO_LOG
    argparse "$@"

    # init logger
    local log_cmd=(
        "--log" "${DOTFILES_LOG_DIR}/main.log"
        "--level" "${LOG_LEVEL}"
        "--format" "[%l] %d %z [%s] %m")
    if ((NO_LOG)); then
        log_cmd+=("--quiet")
    fi

    case "${DOTFILES_ENV}" in
        development)
            log_cmd+=("--verbose" "--colour")
            ;;
        testing)
            log_cmd+=("--no-colour")
            ;;
        production)
            ;;
    esac

    if ! init_logger "${log_cmd[@]}"; then
        die 1 'failed to initialise logger.\nCheck that log directory exists and is writable.'
    fi
    unset -v log_cmd

    print_banner
    case "$MAIN_ACTION" in
        install)
            do_install
            ;;
        remove)
            printf "\n\n--> TODO: Beginning removal! <--\n"
            ;;
        uninstall)
            printf "\n\n--> TODO: Beginning uninstallation! <--\n"
            ;;
        update)
            do_update
            do_install
            ;;
        repair)
            printf "\n\n--> TODO: Beginning repair! <--\n"
            ;;
        reset)
            printf "\n\n--> TODO: Beginning reset! <--\n"
            ;;
    esac
    print_end

    # FIXME:
    # if [[ ${DRY_RUN} -eq 0 && ${DOTFILES_AUTORESTART} -eq 1 ]]; then
    #     if ! is_windows_bash; then
    #         exec "${SHELL:-/bin/zsh}" -l
    #     fi
    # fi

    exit 0
}

main "$@"
