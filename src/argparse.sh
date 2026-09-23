#!/usr/bin/env bash
# argparse.sh

if [[ -n ${__ARGPARSE_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __ARGPARSE_SH_INCLUDED__=1

# $1 = value to test
# $2 = full message
# $3 = new flag
_assert_string_unset() {
    _enter
    if [[ -n ${1}   ]]; then
        _exit 2
        die 2 '%s. Conflicting flag: "%s"' "${2}" "${3}"
    fi
    _exit
}

# $1 = sentinel value (0 = unset, 1 = set)
# $2 = message
# $3 = flag name
_assert_flag_unset() {
    _enter
    if [[ $1 -eq 1     ]]; then
        _exit 2
        die 2 '%s. Conflicting flag: "%s"' "${2}" "${3}"
    fi
    _exit
}

assert_main_action_unset() {
    _enter
    _assert_string_unset "${DF_MAIN_ACTION}" "action already set to \"${DF_MAIN_ACTION}\"" "${1}"
    _exit
}

assert_log_level_unset() {
    _enter
    _assert_string_unset "${DF_LOG_LEVEL}" "log level already set to \"${DF_LOG_LEVEL}\"" "${1}"
    _assert_flag_unset "${DF_NO_LOG}" "logging is disabled via --no-log" "${1}"
    _exit
}

assert_exclude_modules_unset() {
    _enter
    if [[ ${#DF_EXCLUDE_SET[@]} -gt 0 ]]; then
        _exit 2
        die 2 'excluded modules already set. Conflicting flag: "%s"' "${1}"
    fi
    _exit
}
assert_include_modules_unset() {
    _enter
    if [[ ${#DF_INCLUDE_SET[@]} -gt 0 ]]; then
        _exit 2
        die 2 'included modules already set. Conflicting flag: "%s"' "${1}"
    fi
    _exit
}

assert_interactive_unset() {
    _enter
    _assert_flag_unset "${DF_INTERACTIVE}" "interactive mode is already set" "$1"
    _exit
}
assert_noconfirm_unset() {
    _enter
    _assert_flag_unset "${DF_NOCONFIRM}" "noconfirm is already set" "$1"
    _exit
}
assert_force_unset() {
    _enter
    _assert_flag_unset "${DF_FORCE}" "force mode is already set" "$1"
    _exit
}

# $1 = flag name (for error message)
# $2 = value to validate as a non-negative integer (days)
assert_days() {
    _enter
    if [[ ! ${2} =~ ^[0-9]+$ ]]; then
        _exit 2
        die 2 '%s requires a number of days (0 or more). Got: "%s"' "${1}" "${2}"
    fi
    _exit
}

# $1 = flag name (for error message)
# $2 = value to validate
require_arg() {
    _enter
    if [[ -z ${2:-} || ${2} == -* ]]; then
        _exit 2
        die 2 'missing argument for %s.' "$1"
    fi
    _exit
}

argparse() {
    _enter

    DF_MAIN_ACTION=""
    DF_REMOVE_SET=()
    DF_INCLUDE_SET=()
    DF_EXCLUDE_SET=()
    DF_DRY_RUN=0
    DF_NOCONFIRM=0
    DF_NO_REGENERATE=0
    DF_INTERACTIVE=0
    DF_FORCE=0
    DF_NO_BACKUP=0
    DF_CLEAN_DAYS=""
    DF_CLEAN_KEEP=""
    DF_CLEAN_LOGS=0
    DF_CLEAN_BACKUPS=0
    DOTFILES_AUTORESTART=${DOTFILES_AUTORESTART:-0} # env
    local autorestart_flag
    DF_LOG_LEVEL=""
    DF_NO_LOG=0
    DF_PRINT_TIME=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            # information
            -h | --help)
                print_help
                _exit
                exit 0
                ;;
            --version)
                print_version
                _exit
                exit 0
                ;;
            -l | --list)
                list_modules
                _exit
                exit 0
                ;;

            # install
            --install)
                assert_main_action_unset "$1"
                DF_MAIN_ACTION="install"
                shift
                ;;
            -r | --remove)
                assert_main_action_unset "$1"
                assert_exclude_modules_unset "${1}"
                assert_include_modules_unset "${1}"
                require_arg "${1}" "${2:-}"
                parse_module_list "${2}" DF_REMOVE_SET
                DF_MAIN_ACTION="remove"
                shift 2
                ;;
            --remove=*)
                assert_main_action_unset "${1%%=*}"
                assert_exclude_modules_unset "${1%%=*}"
                assert_include_modules_unset "${1%%=*}"
                require_arg "${1%%=*}" "${1#*=}"
                parse_module_list "${1#*=}" DF_REMOVE_SET
                DF_MAIN_ACTION="remove"
                shift
                ;;
            --uninstall)
                assert_main_action_unset "$1"
                DF_MAIN_ACTION="uninstall"
                shift
                ;;
            -u | --update)
                assert_main_action_unset "$1"
                DF_MAIN_ACTION="update"
                shift
                ;;
            -R | --repair)
                assert_main_action_unset "$1"
                DF_MAIN_ACTION="repair"
                shift
                ;;
            --reset)
                assert_main_action_unset "$1"
                DF_MAIN_ACTION="reset"
                shift
                ;;

            # maintenance
            --clean)
                assert_main_action_unset "$1"
                if [[ $# -ge 2 && ${2} != -* ]]; then
                    assert_days "${1}" "${2}"
                    DF_CLEAN_DAYS="${2}"
                    shift 2
                else
                    # no <N> given: keep the latest DOTFILES_MAX_BACKUPS dirs
                    assert_days "${1}" "${DOTFILES_MAX_BACKUPS}"
                    DF_CLEAN_KEEP="${DOTFILES_MAX_BACKUPS}"
                    shift
                fi
                DF_MAIN_ACTION="clean"
                DF_CLEAN_LOGS=1
                DF_CLEAN_BACKUPS=1
                ;;
            --clean-logs)
                assert_main_action_unset "$1"
                DF_MAIN_ACTION="clean"
                DF_CLEAN_LOGS=1
                shift
                ;;
            --clean-backups)
                assert_main_action_unset "$1"
                if [[ $# -ge 2 && ${2} != -* ]]; then
                    assert_days "${1}" "${2}"
                    DF_CLEAN_DAYS="${2}"
                    shift 2
                else
                    # no <N> given: keep the latest DOTFILES_MAX_BACKUPS dirs
                    assert_days "${1}" "${DOTFILES_MAX_BACKUPS}"
                    DF_CLEAN_KEEP="${DOTFILES_MAX_BACKUPS}"
                    shift
                fi
                DF_CLEAN_BACKUPS=1
                DF_MAIN_ACTION="clean"
                ;;

            # modules
            -i | --include)
                assert_exclude_modules_unset "${1}"
                require_arg "$1" "${2:-}"
                parse_module_list "$2" DF_INCLUDE_SET
                shift 2
                ;;
            -i=* | --include=*)
                assert_exclude_modules_unset "${1%%=*}"
                require_arg "${1%%=*}" "${1#*=}"
                parse_module_list "${1#*=}" DF_INCLUDE_SET
                shift
                ;;
            -x | --exclude)
                assert_include_modules_unset "${1}"
                require_arg "$1" "${2:-}"
                parse_module_list "$2" DF_EXCLUDE_SET
                shift 2
                ;;
            -x=* | --exclude=*)
                assert_include_modules_unset "${1%%=*}"
                require_arg "${1%%=*}" "${1#*=}"
                parse_module_list "${1#*=}" DF_EXCLUDE_SET
                shift
                ;;

            # behaviour
            -n | --dry-run)
                DF_DRY_RUN=1
                shift
                ;;
            -K | --autorestart)
                DOTFILES_AUTORESTART=1
                autorestart_flag=1
                shift
                ;;
            -G | --no-regenerate)
                DF_NO_REGENERATE=1
                shift
                ;;
            --no-backup)
                DF_NO_BACKUP=1
                shift
                ;;
            -I | --interactive)
                assert_force_unset "${1}"
                assert_noconfirm_unset "${1}"
                DF_INTERACTIVE=1
                shift
                ;;
            --noconfirm | -y | --yes)
                assert_interactive_unset "${1}"
                DF_NOCONFIRM=1
                shift
                ;;
            -f | --force)
                assert_interactive_unset "${1}"
                DF_FORCE=1
                shift
                ;;

                # logging
            -d | --debug)
                assert_log_level_unset "$1"
                DF_LOG_LEVEL="debug"
                shift
                ;;
            -q | --quiet)
                assert_log_level_unset "$1"
                DF_LOG_LEVEL="error"
                shift
                ;;
            --log-level)
                assert_log_level_unset "$1"
                require_arg     "$1" "${2:-}"
                local level="${2^^}"
                case "${level}" in
                    TRACE | DEBUG | INFO | NOTICE | WARN | ERROR)
                        DF_LOG_LEVEL="${level}"
                        shift 2
                        ;;
                    *)
                        die 2 'invalid log level "%s". Use: trace, debug, info, notice, warn, or error' "$2"
                        ;;
                esac
                ;;
            --log-level=*)
                assert_log_level_unset "${1%%=*}"
                local level="${1#*=}"
                level="${level^^}"
                case "${level}" in
                    TRACE | DEBUG | INFO | NOTICE | WARN | ERROR)
                        DF_LOG_LEVEL="${level}"
                        ;;
                    *)
                        die 2 'invalid log level "%s". Use: trace, debug, info, notice, warn, or error' "${1#*=}"
                        ;;
                esac
                shift
                ;;
            --no-log)
                if [[ -n $DF_LOG_LEVEL   ]]; then
                    die 2 'log level already set to "%s". Cannot use %s.' "$DF_LOG_LEVEL" "$1"
                fi
                DF_NO_LOG=1
                shift
                ;;
            --time)
                DF_PRINT_TIME=1
                shift
                ;;
            *)
                die 2 'invalid parameter "%s"\nRun `bash %s --help` for valid options.' "$1" "$(basename "$0")"
                ;;
        esac
    done

    # default values
    if [[ -z $DF_LOG_LEVEL ]]; then
        case "${DOTFILES_ENV}" in
            development)
                DF_LOG_LEVEL="DEBUG"
                ;;
            testing)
                DF_LOG_LEVEL="TRACE"
                ;;
            production)
                DF_LOG_LEVEL="INFO"
                ;;
        esac
    fi

    # validation
    if [[ -z $DF_MAIN_ACTION ]]; then
        _exit 2
        die 2 'no action specified.\nRun `bash %s --help` for valid options.' "$(basename "$0")"
    fi
    case $DF_MAIN_ACTION in
        remove | update | uninstall | reset | repair | clean)
            [[ ${#DF_INCLUDE_SET[@]} -gt 0 || ${#DF_EXCLUDE_SET[@]} -gt 0 ]] \
                && _exit 2 && die 2 "--include/--exclude not supported with --$DF_MAIN_ACTION"
            ;;
    esac

    if [[ $DF_MAIN_ACTION == remove ]] && [[ ${#DF_REMOVE_SET[@]} -eq 0 ]]; then
        _exit 2
        die 2 "no modules for --remove"
    fi

    if [[ ${DF_NO_REGENERATE} -eq 1 ]] \
        && [[ ${DF_MAIN_ACTION} != install && ${DF_MAIN_ACTION} != update ]]; then
        _exit 2
        die 2 '--no-regenerate is only supported with --install and --update'
    fi

    if [[ ${DF_NO_BACKUP} -eq 1 ]] \
        && [[ ${DF_MAIN_ACTION} != install && ${DF_MAIN_ACTION} != update ]]; then
        _exit 2
        die 2 '--no-backup is only supported with --install and --update'
    fi

    if [[ ${DF_DRY_RUN} -eq 1 ]]; then
        if [[ ${DOTFILES_AUTORESTART} -eq 1 ]]; then
            if [[ ${autorestart_flag} -eq 1 ]]; then
                _exit 2
                die 2 '--autorestart is not meaningful with --dry-run'
            fi
            DOTFILES_AUTORESTART=0
        fi

        if [[ ${DF_INTERACTIVE} -eq 1 ]]; then
            _exit 2
            die 2 '--interactive is meaningless with --dry-run'
        fi
        if [[ ${DF_FORCE} -eq 1 ]]; then
            _exit 2
            die 2 '--force is meaningless with --dry-run'
        fi
    fi

    _exit
}
