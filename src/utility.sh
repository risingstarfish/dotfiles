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
    # TARGET_OS
    if [[ ${MSYSTEM:-} =~ ^(MINGW|MSYS|UCRT|UCRT64|MSYS2)$ ||
          $(uname) == MINGW* ||
          $(uname) == MSYS* ]]; then
          _exit 0
          return 0
    fi
    _exit 1
    return 1
}

parse_module_list() {
    _enter

    local -n arr="$2"
    local mod
    local valid
    local -a mods

    IFS=';' read -ra mods <<< "$1"
    for m in "${mods[@]}"; do
        # trim whitespace
        m="${m#"${m%%[![:space:]]*}"}"
        m="${m%"${m##*[![:space:]]}"}"
        [[ -z $m ]] && continue

        valid=0

        if [[ $m == */* ]]; then
            for mod in "${AVAILABLE_MODULES[@]}"; do
                if [[ $mod == "$m" || $mod == "$m/"* ]]; then
                    valid=1
                    break
                fi
            done
        else
            for mod in "${AVAILABLE_MODULES[@]}"; do
                local modname="${mod##*/}"
                local modcat="${mod%%/*}"
                if [[ ${modcat} == "$m" || $modname == "$m" ]]; then
                    valid=1
                    break
                fi
            done
        fi

        if [[ $valid -eq 0 && -n ${MODULE_CATEGORY_MAP["$m"]:-} ]]; then
            valid=1
            m="${MODULE_CATEGORY_MAP["$m"]}"   # resolve to actual prefix
            log_debug "Resolved display category '$m' from user input"
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
# Prompts the user unless NOCONFIRM=1.
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

    if ((DRY_RUN)); then
        log_trace "DRY_RUN set; bypassing destructive operation"
        log_info "[dry-run] ${cmd}"
        _exit
        return 0
    fi

    if ((NOCONFIRM)); then
        log_trace "NOCONFIRM set; skipping prompt"
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
# Does NOT prompt by default. Prompts only when INTERACTIVE=1 (--interactive).
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

    if ((DRY_RUN)); then
        log_trace "DRY_RUN set; bypassing operation"
        log_info "[dry-run] ${cmd}"
        _exit
        return 0
    fi

    if ((INTERACTIVE)); then
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
