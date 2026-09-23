#!/usr/bin/env bash

set -euo pipefail

if [[ -z ${HOME:-} || ! -d $HOME ]]; then
    printf 'Error: unable to resolve $HOME' >&2
    exit 1
fi

readonly DOTFILES_START_TIME="$(date +%Y-%m-%d_%H%M%S)"
readonly DOTFILES_ENV="${DOTFILES_ENV:-production}" # development testing production
readonly DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-$HOME/.config/dotfiles/logs}"
readonly INIT_LOG_FILE="${DOTFILES_LOG_DIR}/initialise.log"
readonly DOTFILES_CACHE_DIR="${DOTFILES_CACHE_DIR:-$HOME/.cache/dotfiles}"
readonly DOTFILES_BACKUP_DIR="${DOTFILES_CACHE_DIR}/backups"
readonly DOTFILES_MANIFEST_FILE="${DOTFILES_CACHE_DIR}/manifest.tsv"
readonly DOTFILES_LOG="${DOTFILES_LOG:-1}"
SILENCE_INIT_LOG_MSG="true" # logging.sh
readonly DOTFILES_LOCAL_MODS="${DOTFILES_LOCAL_MODS:-0}"
readonly DOTFILES_MAX_BACKUPS="${DOTFILES_MAX_BACKUPS:-10}"

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

# Runtime state: single global namespace (DF_*).
# Functions read/write these directly — no local shadows, no readonly —
# so the state is always unambiguous to follow.
DF_MAIN_ACTION=""
DF_LOG_LEVEL=""
DF_DRY_RUN=0
DF_NOCONFIRM=0
DF_INTERACTIVE=0
DF_FORCE=0
DF_NO_LOG=0
DF_PRINT_TIME=0
DF_NO_REGENERATE=0
DF_NO_BACKUP=0
DF_REMOVE_ERRORS=0
DF_UNINSTALL_ERRORS=0
DF_REPAIR_ERRORS=0
DF_RESET_ERRORS=0
DF_CLEAN_ERRORS=0
DF_CLEAN_DAYS=""
DF_CLEAN_KEEP=""
DF_ERROR_COUNT=0
DF_CLEAN_LOGS=0
DF_CLEAN_BACKUPS=0

declare -A DF_MODULE_ACTION DF_MODULE_DEST DF_MODULE_CMD DF_CATEGORY_MAP

# src files
readonly SOURCE_FILES=(
    "src/utility.sh"
    "src/print.sh"
    "src/argparse.sh"
    # "src/logging.sh" see initialise
    "src/action.sh"
)

# functions
bash_version_check() {
    log_trace "Entering (BASH_VERSION='${BASH_VERSION:-}', ZSH_VERSION='${ZSH_VERSION:-}')"

    if [[ -z ${BASH_VERSION:-} || -n ${ZSH_VERSION:-} ]]; then
        log_error "Script not executing under pure Bash."
        printf 'Error: the install instructions explicitly say to use the install script with bash; please follow them.\n' >&2
        log_trace "Exiting with status 1"
        return 1
    fi

    # script requires bash >=4.0
    if ((BASH_VERSINFO[0] < 4)); then
        log_error "Bash version v4.0 or newer required. Detected version: ${BASH_VERSION}"
        printf 'Error: This script requires bash v4.0 or newer. You are running %s.\n' "${BASH_VERSION}" >&2

        if [[ "$(uname -s)" == "Darwin" ]]; then
            log_debug "macOS detected with outdated default bash version."
            printf '  On macOS, the default bash is severely outdated (v3.2).\n' >&2
            printf '  Please install modern bash via Homebrew:\n' >&2
            printf '    brew install bash\n' >&2
            printf '  or via MacPorts:\n' >&2
            printf '    sudo port install bash\n' >&2
            echo >&2
            printf '  Then restart your terminal and run this script again using the new bash.\n' >&2
        fi

        log_trace "Exiting with status 1"
        return 1
    fi

    log_debug "Bash version ${BASH_VERSION} validated successfully."
    log_trace "Exiting successfully with status 0"
}

# set the absolute directory path of this script
# Source - https://stackoverflow.com/a/246128
_set_src_path() {
    log_trace "Entering (DF_SRC_PATH='${DF_SRC_PATH:-}')"

    if [[ -n ${DF_SRC_PATH:-} ]]; then
        log_debug "DF_SRC_PATH is already set to '${DF_SRC_PATH}'. Skipping."
        log_trace "Exiting (already set)"
        return 0
    fi

    local source_path="${BASH_SOURCE[0]}"
    log_trace "BASH_SOURCE[0]='${source_path}'"

    # piped to bash
    if [[ -z ${source_path} ]]; then
        log_error "Unable to determine source path from BASH_SOURCE."
        log_trace "Exiting with status 1"
        return 1
    fi

    local symlink_dir
    while [[ -L $source_path ]]; do
        log_trace "Resolving symlink for '${source_path}'"
        symlink_dir="$(cd -P "$(dirname "$source_path")" > /dev/null 2>&1 && pwd)"
        source_path="$(readlink "$source_path")"

        if [[ $source_path != /* ]]; then
            source_path=$symlink_dir/$source_path
        fi
        log_trace "Resolved symlink target to '${source_path}'"
    done

    DF_SRC_PATH="$(cd -P "$(dirname "$source_path")" > /dev/null 2>&1 && pwd)"
    log_debug "Resolved DF_SRC_PATH='${DF_SRC_PATH}'"
    log_trace "Exiting successfully with DF_SRC_PATH set"
}

_set_module_dir() {
    log_trace "Entering (DF_MODULE_DIR='${DF_MODULE_DIR:-}', DF_SRC_PATH='${DF_SRC_PATH:-}')"

    if [[ -n ${DF_MODULE_DIR:-} ]]; then
        log_debug "DF_MODULE_DIR is already set to '${DF_MODULE_DIR}'. Skipping."
        log_trace "Exiting (already set)"
        return 0
    fi

    DF_MODULE_DIR="${DF_SRC_PATH}/modules"
    log_trace "Set DF_MODULE_DIR='${DF_MODULE_DIR}'"

    if [[ ! -d ${DF_MODULE_DIR} ]]; then
        log_error "Unable to locate module directory at '${DF_MODULE_DIR}'"
        printf 'Error: unable to locate modules/.\n' >&2
        log_trace "Exiting with status 1"
        return 1
    fi

    log_debug "Verified module directory exists at '${DF_MODULE_DIR}'"
    log_trace "Exiting successfully with status 0"
}

# Detects and sets DF_TARGET_OS and DF_TARGET_RUNTIME. Validates by comparing
# against OS_UNKNOWN and RUNTIME_UNKNOWN
# Usage: _set_env
#
# Returns:
#   0 if DF_TARGET_OS and DF_TARGET_RUNTIME are set
#   1 if DF_TARGET_OS and DF_TARGET_RUNTIME remain 'unknown'
_set_target_env() {
    log_trace "Entering (DF_TARGET_OS='${DF_TARGET_OS:-}', DF_TARGET_RUNTIME='${DF_TARGET_RUNTIME:-}', DF_TARGET_ENV='${DF_TARGET_ENV:-}')"

    if [[ -n ${DF_TARGET_OS:-} || -n ${DF_TARGET_RUNTIME:-} || -n ${DF_TARGET_ENV:-} ]]; then
        log_debug "Environment variables already set. Skipping environment detection."
        log_trace "Exiting (already set)"
        return 0
    fi

    local kernel_name
    kernel_name="$(uname -s 2> /dev/null || echo "unknown")"
    log_trace "Detected kernel_name='${kernel_name}'"

    case "${kernel_name}" in
        Linux*)
            log_debug "Linux kernel detected."
            # wsl vs native
            if uname -r | grep -qi "microsoft"; then
                log_trace "WSL runtime detected."
                DF_TARGET_RUNTIME="${RUNTIME_WSL}"
            else
                log_trace "Native Linux runtime detected."
                DF_TARGET_RUNTIME="${RUNTIME_NATIVE}"
            fi

            # distro
            if [[ -f "/etc/os-release" ]]; then
                if grep -qiE '^ID=.*cachyos' /etc/os-release; then
                    log_trace "CachyOS detected in /etc/os-release."
                    DF_TARGET_OS="${OS_CACHYOS}"
                elif grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release || [[ -f "/etc/debian_version" ]]; then
                    log_trace "Debian-based OS detected in /etc/os-release."
                    DF_TARGET_OS="${OS_DEBIAN}"
                else
                    log_warn "Unsupported Linux distribution."
                    DF_TARGET_OS="${OS_UNKNOWN}"
                fi
            else
                log_warn "/etc/os-release not found. Unable to identify Linux distribution."
                DF_TARGET_OS="${OS_UNKNOWN}"
            fi
            ;;

        Darwin*)
            log_debug "macOS (Darwin) environment detected."
            DF_TARGET_OS="${OS_MACOS}"
            DF_TARGET_RUNTIME="${RUNTIME_NATIVE}"
            ;;

        MINGW*)
            log_debug "Windows MINGW environment detected."
            DF_TARGET_OS="${OS_WINDOWS}"
            if [[ -f "/git-bash.exe" || -n ${EXEPATH:-} ]]; then
                log_trace "Git Bash runtime detected."
                DF_TARGET_RUNTIME="${RUNTIME_GITBASH}"
            else
                log_trace "Unknown MinGW environment detected."
                DF_TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            fi
            ;;

        *)
            log_debug "Fallback environment detection for kernel '${kernel_name}'."
            if [[ ${OS:-} == "Windows_NT" ]]; then
                DF_TARGET_OS="${OS_WINDOWS}"
                DF_TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            else
                DF_TARGET_OS="${OS_UNKNOWN}"
                DF_TARGET_RUNTIME="${RUNTIME_UNKNOWN}"
            fi
            ;;
    esac

    DF_TARGET_ENV="${DF_TARGET_OS}-${DF_TARGET_RUNTIME}"
    log_debug "Detected environment: DF_TARGET_OS='${DF_TARGET_OS}', DF_TARGET_RUNTIME='${DF_TARGET_RUNTIME}', DF_TARGET_ENV='${DF_TARGET_ENV}'"

    if [[ ${DF_TARGET_OS} == "${OS_UNKNOWN}" || ${DF_TARGET_RUNTIME} == "${RUNTIME_UNKNOWN}" ]]; then
        log_error "Failed to fully detect target environment."
        log_trace "Exiting with status 1"
        return 1
    fi

    log_trace "Exiting successfully with status 0"
}

# detect if windows user has sudo enabled
_set_windows_sudo() {
    _enter
    if [[ -n ${WINDOWS_SUDO:-} ]]; then
        log_debug "WINDOWS_SUDO is already set to '${WINDOWS_SUDO}'. Skipping."
        _exit
        return 0
    fi

    WINDOWS_SUDO=0

    if ! command -v sudo > /dev/null 2>&1; then
        log_debug "'sudo' executable not found in PATH."
        readonly WINDOWS_SUDO
        _exit
        return 0
    fi

    if ! command -v reg.exe > /dev/null 2>&1; then
        log_debug "'reg.exe' executable not found in PATH."
        readonly WINDOWS_SUDO
        _exit
        return 0
    fi

    local sudo_reg
    log_trace "Querying Windows Registry: ${WINDOWS_SUDO_REG_LOCATION}"
    sudo_reg=$(MSYS_NO_PATHCONV=1 reg.exe query "${WINDOWS_SUDO_REG_LOCATION}" /v Enabled 2> /dev/null)

    if [[ ${sudo_reg} =~ 0x[1-3] ]]; then
        log_debug "Windows sudo detected as ENABLED in registry."
        WINDOWS_SUDO=1
    else
        log_debug "Windows sudo disabled or key not found."
    fi

    log_trace "Setting MSYS=winsymlinks:nativestrict"
    export MSYS=winsymlinks:nativestrict

    readonly WINDOWS_SUDO
    log_debug "WINDOWS_SUDO set to ${WINDOWS_SUDO}"
    _exit
}

_set_date_cmd() {
    _enter
    DF_DATE_CMD="date"
    DF_DATE_FMT="%Y-%m-%d %H:%M:%S.%3N"

    if ! [[ $(date +%3N 2> /dev/null) =~ ^[0-9]+$ ]]; then
        # Standard 'date' is BSD (macOS). Look for GNU date (gdate)
        if command -v gdate > /dev/null 2>&1; then
            DF_DATE_CMD="gdate"
        elif [[ -x "/opt/homebrew/bin/gdate" ]]; then
            DF_DATE_CMD="/opt/homebrew/bin/gdate"
        elif [[ -x "/usr/local/bin/gdate" ]]; then
            DF_DATE_CMD="/usr/local/bin/gdate"
        else
            # No GNU date capability found; fall back without subseconds to avoid literal '.3N'
            DF_DATE_FMT='%Y-%m-%d %H:%M:%S'
        fi
    fi
    log_debug "DF_DATE_CMD set to '${DF_DATE_CMD}'. DF_DATE_FMT set to ${DF_DATE_FMT}"

    _exit
}

# Detect if script was run as sudo or root.
_set_is_elevated() {
    _enter
    if [[ -n ${DF_IS_ELEVATED:-} ]]; then
        log_debug "DF_IS_ELEVATED is already set to '${DF_IS_ELEVATED}'. Skipping."
        log_trace "Exiting (already set)"
        return 0
    fi

    DF_IS_ELEVATED=0
    if [[ ${EUID} -eq 0 || -n ${SUDO_USER:-} ]]; then
        log_debug "Running as root/sudo user."
        DF_IS_ELEVATED=1
    elif [[ ${DF_TARGET_OS} == "${OS_WINDOWS}" ]] && net session > /dev/null 2>&1; then
        log_debug "Windows administrative session detected."
        DF_IS_ELEVATED=1
    else
        log_debug "Non-elevated execution context."
        DF_IS_ELEVATED=0
    fi

    log_debug "Privilege level DF_IS_ELEVATED=${DF_IS_ELEVATED}"
    _exit
}

_set_dotfiles_manifest() {
    _enter

    if [[ -n ${DF_MANIFEST+x} ]] && ((${#DF_MANIFEST[@]} > 0)); then
        log_debug "DF_MANIFEST already populated (${#DF_MANIFEST[@]} items). Skipping."
        log_trace "Exiting (already populated)"
        return 0
    fi

    local topgrade_dest
    if [[ ${DF_TARGET_OS} == "${OS_WINDOWS}" ]]; then
        topgrade_dest="${APPDATA}/topgrade/topgrade.toml"
    else
        topgrade_dest="${XDG_CONFIG_HOME:-${HOME}/.config}/topgrade.toml"
    fi
    log_trace "Resolved topgrade_dest='${topgrade_dest}'"

    # tag | src | dest | (post-install cmd)
    DF_MANIFEST=(
        "symlink|zsh/zshrc|${HOME}/.zshrc"
        "symlink|zsh/zsh_options|${HOME}/.zsh_options"
        "symlink|zsh/zstyles|${HOME}/.zstyles"
        "symlink|zsh/zimrc|${HOME}/.zimrc"
        "symlink|zsh/p10k.zsh|${HOME}/.p10k.zsh"
        "symlink|zsh/exports|${HOME}/.exports"
        "symlink|zsh/paths|${HOME}/.paths"
        "symlink|zsh/aliases|${HOME}/.aliases"
        "symlink|zsh/functions|${HOME}/.functions"
        "symlink|zsh/zshrc.toggles|${HOME}/.zshrc.toggles"

        "symlink|bash/bashrc|${HOME}/.bashrc"

        "symlink|git/gitconfig|${HOME}/.gitconfig"
        "copy|git/gitconfig.local.${DF_TARGET_OS}|${HOME}/.gitconfig.local"
        "symlink|git/gitignore|${HOME}/.gitignore"
        "symlink|git/gitattributes|${HOME}/.gitattributes"
        "symlink|git/diff-so-fancy|${HOME}/.local/bin/diff-so-fancy|chmod +x ${HOME}/.local/bin/diff-so-fancy"

        "symlink|ssh/config|${HOME}/.ssh/config|chmod 600 ${HOME}/.ssh/config"
        "generate|ssh/allowed_signers.gen|${HOME}/.ssh/allowed_signers|chmod 600 ${HOME}/.ssh/allowed_signers"

        "symlink|dev/cmakepreset.py|${HOME}/.local/bin/cmakepreset.py|chmod 600 ${HOME}/.local/bin/cmakepreset.py"
        "symlink|dev/internal-flags.cmake|${HOME}/dev/internal-flags.cmake"
        "symlink|dev/cmake-format.py|${HOME}/dev/.cmake-format.py"
        "symlink|dev/clang-format|${HOME}/dev/.clang-format"
        "symlink|dev/clang-tidy|${HOME}/dev/.clang-tidy"
        "symlink|dev/editorconfig|${HOME}/dev/.editorconfig"

        "symlink|topgrade/topgrade.toml|${topgrade_dest}"
        "symlink|fastfetch/config.jsonc.${DF_TARGET_OS}|${HOME}/.config/fastfetch/config.jsonc"
        "symlink|tmux/tmux.conf.${DF_TARGET_OS}|${HOME}/.tmux.conf"
        "symlink|curl/curlrc|${HOME}/.curlrc"
        "symlink|wget/wgetrc|${HOME}/.wgetrc"
        "symlink|shellcheck/shellcheckrc|${HOME}/.shellcheckrc"

        "symlink|claude/settings.json|${HOME}/.claude/settings.json"
        "symlink|claude/plugin.json|${HOME}/.claude/plugin.json"

        "copy|pwsh.${DF_TARGET_OS}/Profile|${HOME}/Documents/Powershell/Microsoft.PowerShell_profile.ps1"
        "copy|pwsh.${DF_TARGET_OS}/Set-MSVC-Environment|${HOME}/Documents/Powershell/Scripts/Set-MSVC-Environment.ps1"
        "copy|pwsh.${DF_TARGET_OS}/Update-Modules|${HOME}/Documents/Powershell/Scripts/Update-Modules.ps1"
        "copy|pwsh.${DF_TARGET_OS}/Print-Env|${HOME}/Documents/Powershell/Scripts/Print-Env.ps1"
        "copy|pwsh.${DF_TARGET_OS}/nproc|${HOME}/Documents/Powershell/Scripts/nproc.ps1"
        "copy|pwsh.${DF_TARGET_OS}/sha256|${HOME}/Documents/Powershell/Scripts/sha256.ps1"
        "copy|pwsh.${DF_TARGET_OS}/sha1|${HOME}/Documents/Powershell/Scripts/sha1.ps1"
        "copy|pwsh.${DF_TARGET_OS}/md5|${HOME}/Documents/Powershell/Scripts/md5.ps1"

        "symlink|oh-my-posh.${DF_TARGET_OS}/themes/tiger.omp.json|${HOME}/.oh-my-posh/themes/tiger.omp.json"
        "symlink|oh-my-posh.${DF_TARGET_OS}/themes/agnoster.omp.json|${HOME}/.oh-my-posh/themes/agnoster.omp.json"
        "symlink|oh-my-posh.${DF_TARGET_OS}/themes/kushal.omp.json|${HOME}/.oh-my-posh/themes/kushal.omp.json"
        "symlink|oh-my-posh.${DF_TARGET_OS}/themes/powerlevel10k_classic.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_classic.omp.json"
        "symlink|oh-my-posh.${DF_TARGET_OS}/themes/powerlevel10k_lean.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_lean.omp.json"
        "symlink|oh-my-posh.${DF_TARGET_OS}/themes/powerlevel10k_modern.omp.json|${HOME}/.oh-my-posh/themes/powerlevel10k_modern.omp.json"

    )

    # verification
    _exit
}

_populate_arrays() {
    _enter

    if [[ -n ${DF_AVAILABLE_MODULES+x} ]] && ((${#DF_AVAILABLE_MODULES[@]} > 0)) \
        && [[ -n ${DF_MODULE_ACTION+x} ]] && ((${#DF_MODULE_ACTION[@]} > 0)) \
        && [[ -n ${DF_MODULE_DEST+x}  ]] && ((${#DF_MODULE_DEST[@]} > 0)) \
        && [[ -n ${DF_CATEGORY_MAP+x}  ]] && ((${#DF_CATEGORY_MAP[@]} > 0)) \
        && [[ -n ${DF_MODULE_CMD+x}   ]] && ((${#DF_MODULE_CMD[@]} > 0)); then
        log_debug "Module arrays are already populated. Skipping."
        log_trace "Exiting (all arrays already set)"
        return 0
    fi

    local -a active_modules=()
    local item action src dest post_cmd

    for item in "${DF_MANIFEST[@]}"; do
        IFS='|' read -r action src dest post_cmd <<< "${item}"

        # skip if not available on os/runtime
        if [[ ! -e "${DF_MODULE_DIR}/${src}" ]]; then
            log_trace "Skipping module '${src}': source does not exist at '${DF_MODULE_DIR}/${src}'"
            continue
        fi

        # skip specific combos
        if [[ ${src} == "topgrade/topgrade.toml" && ${DF_TARGET_OS} == "${OS_WINDOWS}" ]]; then
            log_trace "Skipping '${src}' for OS '${DF_TARGET_OS}'"
            continue
        fi

        log_debug "Module available: '${src}'"
        active_modules+=("${src}")

        DF_MODULE_ACTION["${src}"]="${action}"
        DF_MODULE_DEST["${src}"]="${dest}"
        DF_MODULE_CMD["${src}"]="${post_cmd:-}"

        local raw_cat="${src%%/*}"
        local display_cat="${raw_cat}"
        if [[ ${display_cat} == *".${DF_TARGET_ENV}" ]]; then
            display_cat="${display_cat%".${DF_TARGET_ENV}"}"
        elif [[ ${display_cat} == *".${DF_TARGET_OS}" ]]; then
            display_cat="${display_cat%".${DF_TARGET_OS}"}"
        fi
        DF_CATEGORY_MAP["${display_cat}"]="${raw_cat}"
    done

    DF_AVAILABLE_MODULES=("${active_modules[@]}")
    log_debug "Resolved ${#DF_AVAILABLE_MODULES[@]} available modules."
    _exit
}

check_exists() {
    log_trace "Entering"

    local -r -a paths=("$@")
    local -a missing_paths=()
    local -r prefix="${DF_SRC_PATH}/"

    for path in "${paths[@]}"; do
        local target_path="$path"

        if [[ $path != /* ]] && [[ $path != ~* ]]; then
            target_path="${prefix}${path}"
        fi

        log_trace "Testing existence of '${target_path}'"
        if [[ ! -e $target_path ]]; then
            log_error "Missing path: '${target_path}'"
            missing_paths+=("${target_path#"$prefix"}")
        fi
    done

    if [[ ${#missing_paths[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_paths[@]} required path(s)."
        printf "Missing %d path(s):\n" "${#missing_paths[@]}" >&2

        for missing in "${missing_paths[@]}"; do
            printf "✗ %s\n" "${missing}" >&2
        done

        log_trace "Exiting with status 1"
        return 1
    fi

    log_debug "All path checks passed successfully."
    log_trace "Exiting successfully with status 0"
    return 0
}

source_files() {
    log_trace "Entering (SOURCE_FILES count: ${#SOURCE_FILES[@]})"

    for file in "${SOURCE_FILES[@]}"; do
        log_trace "Processing source file: '${file}'"

        if [[ -z ${file} ]]; then
            log_error "Called without a file path argument."
            # printf 'Error: source_file called without a file path argument.\n' >&2
            return 1
        fi

        if [[ ! -f ${file} ]]; then
            log_error "File '${file}' does not exist or is a directory."
            # printf 'Error: cannot source "%s": File does not exist or is a directory.\n' "${file}" >&2
            return 1
        fi

        if [[ ! -r ${file} ]]; then
            log_error "Read permission denied for '${file}'."
            # printf 'Error: cannot source "%s": Read permission denied.\n' "${file}" >&2
            return 1
        fi

        log_trace "Sourcing '${file}'..."
        source "${file}" || {
            local ec=$?
            log_error "Failed to source '${file}' (exit code: ${ec})."
            # printf 'Error: file "%s" was read, but execution failed with exit code %d.\n' "${file}" "${ec}" >&2
            return 1
        }
    done

    log_debug "Successfully sourced ${#SOURCE_FILES[@]} file(s)."
    log_trace "Exiting successfully with status 0"
}

# NOTE: no _enter _exit
timer_start() {
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        _TIMER_START="${EPOCHREALTIME}"
    else
        # Bash 4.x: no EPOCHREALTIME. Use date (GNU or BSD both support %s and %N or fallback)
        _TIMER_START=$(date +%s%N 2> /dev/null || date +%s)000000000
        # if %N isn't supported (BSD), %s%N gives "1234567890N" — guard:
        [[ ${_TIMER_START} =~ ^[0-9]+$ ]] || _TIMER_START="$(date +%s)000000000"
    fi
}

# NOTE: no _enter _exit
timer_elapsed() {
    local end
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        end="${EPOCHREALTIME}"
    else
        end=$(date +%s%N 2> /dev/null || date +%s)000000000
        [[ ${end} =~ ^[0-9]+$ ]] || end="$(date +%s)000000000"
    fi

    # Both are nanosecond-precision integers (or "sec.nsec" from EPOCHREALTIME)
    awk -v s="${_TIMER_START}" -v e="${end}" 'BEGIN {
        # Handle "sec.nsec" format (EPOCHREALTIME)
        if (s ~ /\./) { s = s + 0 }
        if (e ~ /\./) { e = e + 0 }
        # Handle pure integer (nanoseconds) format
        else { s = s / 1000000000; e = e / 1000000000 }
        printf "%.2fs", e - s
    }'
}

is_true() {
    case "${1,,}" in
        1 | true) return 0 ;;
        *) return 1 ;;
    esac
}

set_pwsh_cmd() {
    [[ -n ${PWSH_CMD:-}  ]] && return 0

    if [[ ${DF_TARGET_OS} == "${OS_WINDOWS}"  ]]; then
        if PWSH_CMD=$(command -v pwsh.exe 2> /dev/null); then
            :
        elif PWSH_CMD=$(command -v powershell.exe 2> /dev/null); then
            :
        fi
    else # linux
        if PWSH_CMD=$(command -v pwsh 2> /dev/null); then
            :
        fi
    fi

    readonly PWSH_CMD
}

prompt_windows_handoff() {
    _enter
    printf '\n' >&2
    if [[ ${DF_TARGET_RUNTIME} == "${RUNTIME_GITBASH}"  ]]; then
        printf 'Windows Git Bash runtime detected\n' >&2
        printf 'If you are not actually running Git Bash, something went wrong.\n' >&2
    else # unknown
        printf 'Unknown Windows Bash runtime detected.\n' >&2
        printf 'Bash scripts may fail to configure native Windows settings properly.\n' >&2
    fi

    printf 'Certain functionality may be missing or altered (e.g. instead of symlinking, files get copied).\n' >&2
    if is_true "${WINDOWS_SUDO}"; then
        printf '   Tip: Re-run this script using `sudo` to enable native symlinks.\n' >&2
    else
        printf '   Tip: Enable Windows Developer Mode or Windows Sudo to allow native symlinks.\n' >&2
    fi

    printf '\n' >&2

    local choice
    while true; do
        if ! read -r -p $'Switch to the native PowerShell installer (dotfiles.ps1)? [Y/n/(q)]: ' choice; then
            printf 'Error: No input available for prompt.\n' >&2
            exit 1
        fi

        case "$choice" in
            [yY])
                set_pwsh_cmd  # verify powershell available
                if [[ -z ${PWSH_CMD} ]]; then
                    printf 'Error: Cannot locate pwsh.exe or powershell.exe.\n' >&2
                    _exit 1
                    exit 1
                fi
                return 0
                ;;
            [nN])
                printf 'Continuing with Bash installer on Windows...\n' >&2
                _exit 1
                return 1
                ;;
            [qQ])
                printf 'Aborting installation!\n' >&2
                _exit 130
                exit 130
                ;;
            *)
                printf 'Error: Invalid input. Please enter y, n, or q.\n' >&2
                ;;
        esac
    done

    _exit
}

windows_handoff() {
    local ps_script="${DF_SRC_PATH}/dotfiles.ps1"
    if [[ ! -f ${ps_script}  ]]; then
        printf 'Error: unable to find "dotfiles.ps1".\n' >&2
        exit 1
    fi

    # convert unix paths to windows
    if [[ ${DF_TARGET_RUNTIME} == "${RUNTIME_WSL}"  ]]; then
        ps_script=$(wslpath -w "$ps_script")
    fi

    local -a ps_args=("-NoProfile" "-ExecutionPolicy" "Bypass" "-File" "$ps_script")

    #if [[ ${DF_IS_ELEVATED} -eq 1 ]]; then
    #	ps_args+=("-IsElevated")
    #fi

    local pwsh_name="${PWSH_CMD##*/}"
    pwsh_name="${pwsh_name%.exe}"

    echo
    printf 'Handing off execution to %s...\n' "${pwsh_name}"
    echo

    # NOTE: adding exec makes it auto close
    local ec=0
    "${PWSH_CMD}" "${ps_args[@]}" || ec=$?

    echo
    read -rn 1 -p "Press any key to exit..."
    exit "${ec}"
}

initialise() {
    source "src/logging.sh" || {
        exit 1
    }

    if ! init_logger --log "${INIT_LOG_FILE}" --level TRACE --quiet --no-init-message --format "[%l] %d %z [%s] %m"; then
        die 1 'failed to initialise logger.\nCheck that log directory exists and is writable.'
    fi

    log_trace "Entering initialisation sequence..."

    bash_version_check || die 1 'Bash version validation failed.'

    # DF_SRC_PATH
    _set_src_path || die 1 'Failed to determine script source path.'

    if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
        log_error "SOURCE_FILES array is empty."
        die 1 "No source files defined."
    fi

    # check src/
    check_exists "${SOURCE_FILES[@]}" || {
         printf "One or more required source files are missing." >&2
         exit 1
    }
    source_files "${SOURCE_FILES[@]}" || {
        printf "Failed to source framework files." >&2
        exit 1
    }

    _set_date_cmd # DF_DATE_CMD DF_DATE_FMT
    _set_module_dir || die 1 "Failed to establish module directory."
    _set_target_env || {      # DF_TARGET_ENV DF_TARGET_OS DF_TARGET_RUNTIME
        log_warn "Target environment detection failed. Prompting user to proceed."
        printf 'Warning: unable to determine $DF_TARGET_OS or $DF_TARGET_RUNTIME.\n' >&2
        prompt_continue 'Some functionality may be limited.'
    }

    _set_is_elevated      # DF_IS_ELEVATED
    if [[ ${DF_TARGET_OS} == "${OS_WINDOWS}"   ]]; then
        _set_windows_sudo # WINDOWS_SUDO
    fi

    _set_dotfiles_manifest # DF_MANIFEST
    _populate_arrays # DF_AVAILABLE_MODULES DF_MODULE_ACTION DF_MODULE_DEST DF_MODULE_CMD
    # TODO: unset DF_MANIFEST SOURCE_FILES

    log_trace "Initialisation complete."
}

main() {
    timer_start

    initialise

    if ! is_true "${DOTFILES_IGNORE_HANDOFF:-}"; then
        if [[ ${DF_IS_ELEVATED} -eq 0 && ${DF_TARGET_OS} == "${OS_WINDOWS}"    ]]; then
            case "${DF_TARGET_RUNTIME}" in
                "${RUNTIME_GITBASH}" | "${RUNTIME_UNKNOWN}")
                    if prompt_windows_handoff; then
                        windows_handoff
                    fi
                    ;;
                *) ;;
            esac
        fi
    fi

    argparse "$@"

    # init logger
    local log_cmd=(
        "--level" "${DF_LOG_LEVEL}"
        "--format" "[%l] %d %z [%s] %m"
    )
    if is_true "${DOTFILES_LOG}"; then
        log_cmd+=("--log" "${DOTFILES_LOG_DIR}/main.log")
    fi
    if ((DF_NO_LOG)); then
        log_cmd+=("--quiet")
    fi

    case "${DOTFILES_ENV}" in
        development)
            log_cmd+=("--verbose" "--colour")
            ;;
        testing)
            log_cmd+=("--no-colour")
            ;;
        production) ;;

    esac

    if ! init_logger "${log_cmd[@]}"; then
        die 1 'failed to initialise logger.\nCheck that log directory exists and is writable.'
    fi
    unset -v log_cmd

    print_banner

    local ec=0
    case "$DF_MAIN_ACTION" in
        install)
            do_install || ec=1
            ;;
        remove)
            do_remove || {
                printf 'Error: remove finished with %d failure(s).\n' "${DF_REMOVE_ERRORS}" >&2
                ec=1
            }
            ;;
        uninstall)
            do_uninstall || {
                printf 'Error: uninstall finished with %d failure(s).\n' "${DF_UNINSTALL_ERRORS}" >&2
                printf '\n  You may need to manually remove:\n' >&2
                printf '    %s\n'  "${DOTFILES_LOG_DIR}"    >&2
                printf '    %s\n'  "${DOTFILES_CACHE_DIR}"  >&2
                printf '    %s\n'  "${DF_SRC_PATH}"            >&2
                printf '\n' >&2
                ec=1

            }
            ;;

        update)
            do_update || ec=1
            do_install || ec=1
            ;;
        repair)
            do_repair || {
                printf 'Error: repair finished with %d failure(s).\n' "${DF_REPAIR_ERRORS}" >&2
                ec=1
            }
            ;;
        reset)
            do_reset || {
                printf 'Error: reset finished with %d failure(s).\n' "${DF_RESET_ERRORS}" >&2
                ec=1
            }
            ;;
        clean)
            if ((DF_DRY_RUN)); then
                LOG_FILE=""
            fi
            if ((DF_CLEAN_LOGS)); then
                do_clean_logs || {
                    printf 'Error: clean finished with %d failure(s).\n' "${DF_CLEAN_ERRORS}" >&2
                    ec=1
                }
            fi
            if ((DF_CLEAN_BACKUPS)); then
                do_clean_backups || {
                    printf 'Error: clean-backups finished with %d failure(s).\n' "${DF_CLEAN_ERRORS}" >&2
                    ec=1
                }
            fi
            ;;
    esac

    print_end

    local elapsed
    elapsed="$(    timer_elapsed)"
    if ((DF_PRINT_TIME)); then
        printf '\n  ⏱  Total: %s\n\n' "${elapsed}"
    fi

    log_trace "Total execution time: ${elapsed}"

    if ! ((DF_DRY_RUN)) && is_true "${DOTFILES_AUTORESTART}"; then
        if ! is_windows_bash; then
            exec "${SHELL:-/bin/zsh}" -l
        fi
    fi

    exit "${ec}"
}

main "$@"
