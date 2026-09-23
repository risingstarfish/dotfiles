#!/usr/bin/env bash
# utility.sh

if [[ -n ${__UTILITY_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __UTILITY_SH_INCLUDED__=1

# $1 = exit code (default 2)
# $2 = printf format string
# $3.. = format args
die() {
    _enter
    local -r rc="${1:-2}"
    shift
    printf "Error: ${1}\n" "${@:2}" >&2

    _exit "${rc}"
    exit "${rc}"
}

# Prompts the user to continue.
# Exits the script if the user chooses No (n/N).
# Usage: prompt_continue
#
# Arguments:
#   $1 (format) : (Optional) The warning message, or a printf-style format string.
#   $@ (args)   : (Optional) Arguments to populate the format string.
prompt_continue() {
    _enter

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
            _exit 1
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
    _exit
}

is_windows_bash() {
    _enter
    # DF_TARGET_OS
    if [[ ${MSYSTEM:-} =~ ^(MINGW|MSYS|UCRT|UCRT64|MSYS2)$ ||
          $(uname) == MINGW* ||
          $(uname) == MSYS* ]]; then
          _exit 0
          return 0
    fi
    _exit 1
    return 1
}

# Parse a semicolon-separated module list and append canonical selectors
# to the caller-supplied array.
#
# Accepted forms (each resolved to what the include/exclude/remove matchers
# understand — a category prefix or a full module path):
#   "cat/file"    exact module path or prefix        (e.g. "zsh/zshrc", "zsh")
#   "cat"         category prefix                    (e.g. "zsh")
#   "file"        unique module basename -> full path (e.g. "zshrc" -> "zsh/zshrc")
#   "display"     display category -> raw category    (e.g. "pwsh" -> "pwsh.windows")
#
# $1 = semicolon-separated module list
# $2 = name of the destination array (nameref)
parse_module_list() {
    _enter

    local -n arr="$2"
    local m mod valid
    local -a mods matches

    IFS=';' read -ra mods <<< "$1"
    for m in "${mods[@]}"; do
        # trim whitespace
        m="${m#"${m%%[![:space:]]*}"}"
        m="${m%"${m##*[![:space:]]}"}"
        [[ -z $m ]] && continue

        valid=0

        if [[ $m == */* ]]; then
            # path: exact module path or category prefix
            for mod in "${DF_AVAILABLE_MODULES[@]}"; do
                if [[ $mod == "$m" || $mod == "$m/"* ]]; then
                    valid=1
                    break
                fi
            done
        else
            # bare name: resolve to a canonical selector
            matches=()
            for mod in "${DF_AVAILABLE_MODULES[@]}"; do
                if [[ ${mod##*/} == "$m" ]]; then
                    matches+=("$mod")
                elif [[ ${mod%%/*} == "$m" ]]; then
                    valid=1   # category prefix — usable as-is
                fi
            done

            if [[ ${#matches[@]} -eq 1 ]]; then
                valid=1
                log_debug "Resolved bare name '$m' to module '${matches[0]}'"
                m="${matches[0]}"
            elif [[ ${#matches[@]} -gt 1 ]]; then
                _exit 2
                die 2 'ambiguous module name "%s". Matches: %s' "$m" "${matches[*]}"
            elif [[ -n ${DF_CATEGORY_MAP["$m"]:-} ]]; then
                valid=1
                log_debug "Resolved display category '$m' to '${DF_CATEGORY_MAP["$m"]}'"
                m="${DF_CATEGORY_MAP["$m"]}"
            fi
        fi

        if [[ $valid -eq 0 ]]; then
            _exit 2
            die 2 'unknown module "%s".\nRun with --list to see valid modules.' "$m"
        fi

        arr+=("$m")
    done
    _exit
}

# Executes a command and handles success/failure logging.
# No prompting, no dry-run — call one of the _attempt_* wrappers instead.
#
# $1 = shell command string (eval'd)
# $2 = error message (printf format)
# $3 = success message (printf format)
_exec_cmd() {
    local -r cmd="${1}"
    local -r err_msg="${2}"
    local -r suc_msg="${3}"

    log_trace "Executing: ${cmd}"
    local err_output
    if ! err_output=$(eval "${cmd}" 2>&1); then
        log_trace "Operation failed"
        log_error "${err_msg}"
        log_debug "System error: ${err_output}"
        _exit 1
        return 1
    fi

    log_debug "${suc_msg}"
    _exit
    return 0
}

# Use for irreversible operations (rm, reset, uninstall, …).
# Prompts the user unless DF_NOCONFIRM=1.
#
# $1 = shell command string
# $2 = human-readable description (shown in prompt)
# $3 = error message
# $4 = success message
#
# Returns:
#   0    success (or dry-run)
#   1    command failed
#   130  user declined
attempt_cmd() {
    _enter
    local -r cmd="${1}"
    local -r msg="${2}"
    local -r err_msg="${3}"
    local -r suc_msg="${4}"

    if ((DF_DRY_RUN)); then
        log_trace "DF_DRY_RUN set; bypassing destructive operation"
        log_info "[dry-run] ${cmd}"
        _exit
        return 0
    fi

    if ((DF_NOCONFIRM)); then
        log_trace "DF_NOCONFIRM set; skipping prompt"
    else
        log_info "About to run: ${cmd}"
        printf '\n  %s\n' "${msg}" >&2

        local reply
        printf '  Continue? [Y/n] ' >&2
        read -r reply || reply=""
        log_trace "User prompt reply: '${reply}'"
        case "${reply,,}" in
            y | yes | '')
                log_trace "User confirmed"
                ;;
            *)
                log_trace "User rejected prompt"
                log_warn "Operation cancelled by user."
                _exit 130
                return 130
                ;;
        esac
        printf '\n' >&2
    fi

    _exec_cmd "${cmd}" "${err_msg}" "${suc_msg}"
}

# Use for idempotent operations (symlink, copy, generate, …).
# Does NOT prompt by default. Prompts only when DF_INTERACTIVE=1 (--interactive).
#
# $1 = shell command string
# $2 = human-readable description (shown in prompt, if interactive)
# $3 = error message
# $4 = success message
#
# Returns:
#   0    success (or dry-run)
#   1    command failed
#   130  user declined (interactive mode)
attempt_cmd_quiet() {
    _enter
    local -r cmd="${1}"
    local -r msg="${2}"
    local -r err_msg="${3}"
    local -r suc_msg="${4}"

    if ((DF_DRY_RUN)); then
        log_trace "DF_DRY_RUN set; bypassing operation"
        log_info "[dry-run] ${cmd}"
        _exit
        return 0
    fi

    if ((DF_INTERACTIVE)); then
        log_info "About to run: ${cmd}"
        printf '\n  %s\n' "${msg}" >&2

        local reply
        printf '  Continue? [Y/n] ' >&2
        read -r reply || reply=""
        log_trace "User prompt reply: '${reply}'"
        case "${reply,,}" in
            y | yes | '')
                log_trace "User confirmed"
                ;;
            *)
                log_trace "User rejected prompt"
                log_warn "Operation cancelled by user."
                _exit 130
                return 130
                ;;
        esac
        printf '\n' >&2
    else
        log_trace "Non-interactive mode; executing without prompt"
    fi

    _exec_cmd "${cmd}" "${err_msg}" "${suc_msg}"
}
