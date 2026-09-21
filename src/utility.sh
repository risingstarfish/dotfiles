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
    local -r rc="${1:-2}"
    shift
    printf "Error: ${1}\n" "${@:2}" >&2
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
    log_trace "${FUNCNAME[0]}: Entering"

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
    log_trace "${FUNCNAME[0]}: Exiting"
}

is_windows_bash() {
    [[ -n ${MSYSTEM:-} || $(uname) == MINGW* || $(uname) == MSYS* ]]
}

parse_module_list()  {
    log_trace "${FUNCNAME[0]}: Entering"

    local -n arr="$2"
    local mod
    local valid
    local -a mods

    IFS=';' read -ra mods <<< "$1"
    for m in "${mods[@]}"; do
        # trim whitespace
        m="${m#"${m%%[![:space:]]*}"}"
        m="${m%"${m##*[![:space:]]}"}"
        [[ -z $m   ]] && continue

        valid=0
        if [[ $m == */*   ]]; then
            for mod in "${AVAILABLE_MODULES[@]}"; do
                if [[ $mod == "$m" || $mod == "$m/"*     ]]; then
                    valid=1
                    break
                fi
            done
        else
            for mod in "${AVAILABLE_MODULES[@]}"; do
                modname="${mod##*/}"
                if [[ ${mod%%/*} == "$m" || $modname == "$m"     ]]; then
                    valid=1
                    break
                fi
            done
        fi

        if [[ $valid -eq 0 ]]; then
            die 2 'unknown module "%s".\nRun with --list to see valid modules.' "$m"
        fi
        arr+=("$m")
    done
    log_trace "${FUNCNAME[0]}: Exiting"
}

_attempt_cmd() {
    log_trace "${FUNCNAME[0]}: Entering"

    local -r cmd="${1}"
    local -r msg="${2}"
    local -r err_msg="${3}"
    local -r suc_msg="${4:-}"

    if ((DRY_RUN)); then
        log_trace "${FUNCNAME[0]}: DRY_RUN is set (${DRY_RUN}); bypassing operation"
        log_info "[dry-run] ${cmd}"
        return 0
    fi

    if ((NOCONFIRM)); then
        log_trace "${FUNCNAME[0]}: NOCONFIRM is set (${NOCONFIRM}); bypassing interactive prompt"
    else
        log_info "About to run: ${cmd}"
        printf '\n  %s\n' "${msg}" >&2

        local reply
        read -r '  Continue? [Y/n] ' reply >&2
        log_trace "${FUNCNAME[0]}: User prompt reply: '${reply}'"
        case "${reply,,}" in
            y | yes | '')
                log_trace "${FUNCNAME[0]}: User confirmed"
                ;;
            *)
                log_trace "${FUNCNAME[0]}: User rejected prompt"
                log_warn "Operation cancelled by user."
                log_trace "${FUNCNAME[0]}: Exiting with status 130 (user cancelled)"
                return 130
                ;;
        esac
        printf '\n' >&2
    fi

    log_trace "${FUNCNAME[0]}: Executing: ${cmd}"
    local err_output
    if ! err_output=$(eval "${cmd}" 2>&1); then
        log_trace "${FUNCNAME[0]}: Operation failed"
        log_error "${err_msg}"
        log_debug "System error: ${err_output}"
        return 1
    fi

    if [[ -n ${suc_msg} ]]; then
        log_debug "${suc_msg}"
    fi

    log_trace "${FUNCNAME[0]}: Exiting"
}

timer_start() {
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        _TIMER_START="${EPOCHREALTIME}"
    else
        _TIMER_START=$("${_LOG_DATE_CMD:-date}" +%s.%N 2> /dev/null || date +%s)
    fi
}

timer_elapsed() {
    local end
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        end="${EPOCHREALTIME}"
    else
        end=$("${_LOG_DATE_CMD:-date}" +%s.%N 2> /dev/null || date +%s)
    fi

    # Calculate difference using awk (works cross-platform without 'bc')
    awk -v start="${_TIMER_START}" -v end="${end}" 'BEGIN { printf "%.3fs", end - start }'
}
