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
    _assert_string_unset "${MAIN_ACTION}" "action already set to \"${MAIN_ACTION}\"" "${1}"
    _exit
}

assert_log_level_unset() {
    _enter
    _assert_string_unset "${LOG_LEVEL}" "log level already set to \"${LOG_LEVEL}\"" "${1}"
    _assert_flag_unset "${NO_LOG}" "logging is disabled via --no-log" "${1}"
    _exit
}

assert_exclude_modules_unset() {
    _enter
    if [[ ${#EXCLUDE_SET[@]} -gt 0 ]]; then
        _exit 2
        die 2 'excluded modules already set. Conflicting flag: "%s"' "${1}"
    fi
        _exit
}
assert_include_modules_unset() {
    _enter
    if [[ ${#INCLUDE_SET[@]} -gt 0 ]]; then
        _exit 2
        die 2 'included modules already set. Conflicting flag: "%s"' "${1}"
    fi
    _exit
}

assert_interactive_unset() {
    _enter
    _assert_flag_unset "${interactive_flag}" "interactive mode is already set" "$1"
    _exit
}
assert_noconfirm_unset() {
    _enter
    _assert_flag_unset "${NOCONFIRM}" "noconfirm is already set" "$1"
    _exit
}
assert_force_unset() {
    _enter
    _assert_flag_unset "${FORCE}" "force mode is already set" "$1"
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

    MAIN_ACTION=""
    REMOVE_SET=()
    INCLUDE_SET=()
    EXCLUDE_SET=()
    DRY_RUN=0
    NOCONFIRM=0
    local interactive_flag=-1
    FORCE=0
    DOTFILES_AUTORESTART=${DOTFILES_AUTORESTART:-0} # env
    local autorestart_flag
    NO_BACKUP=0
    NO_DEPS=0
    LOG_LEVEL=""
    NO_LOG=0

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
            --verify)
                local verify_rc=0
                print_verification || verify_rc=$?
                _exit
                exit "${verify_rc}"
                ;;
            -l | --list)
                list_modules
                _exit
                exit 0
                ;;

            # install
            --install)
                assert_main_action_unset "$1"
                MAIN_ACTION="install"
                shift
                ;;
            -r | --remove)
                assert_main_action_unset "$1"
                assert_exclude_modules_unset "${1}"
                assert_include_modules_unset "${1}"
                require_arg "${1}" "${2:-}"
                parse_module_list "${2}" REMOVE_SET
                MAIN_ACTION="remove"
                shift 2
                ;;
            --remove=*)
                assert_main_action_unset "${1%%=*}"
                assert_exclude_modules_unset "${1%%=*}"
                assert_include_modules_unset "${1%%=*}"
                require_arg "${1%%=*}" "${1#*=}"
                parse_module_list "${1#*=}" REMOVE_SET
                MAIN_ACTION="remove"
                shift
                ;;
            --uninstall)
                assert_main_action_unset "$1"
                MAIN_ACTION="uninstall"
                shift
                ;;
            -u | --update)
                assert_main_action_unset "$1"
                MAIN_ACTION="update"
                shift
                ;;
            -R | --repair)
                assert_main_action_unset "$1"
                MAIN_ACTION="repair"
                shift
                ;;
            --reset)
                assert_main_action_unset "$1"
                MAIN_ACTION="reset"
                shift
                ;;

            # modules
            -i | --include)
                assert_exclude_modules_unset "${1}"
                require_arg "$1" "${2:-}"
                parse_module_list "$2" INCLUDE_SET
                shift 2
                ;;
            -i=* | --include=*)
                assert_exclude_modules_unset "${1%%=*}"
                require_arg "${1%%=*}" "${1#*=}"
                parse_module_list "${1#*=}" INCLUDE_SET
                shift
                ;;
            -x | --exclude)
                assert_include_modules_unset "${1}"
                require_arg "$1" "${2:-}"
                parse_module_list "$2" EXCLUDE_SET
                shift 2
                ;;
            -x=* | --exclude=*)
                assert_include_modules_unset "${1%%=*}"
                require_arg "${1%%=*}" "${1#*=}"
                parse_module_list "${1#*=}" EXCLUDE_SET
                shift
                ;;

            # behaviour
            -n | --dry-run)
                DRY_RUN=1
                shift
                ;;
            -I | --interactive)
                assert_force_unset "${1}"
                assert_noconfirm_unset "${1}"
                NOCONFIRM=0
                interactive_flag=1
                shift
                ;;
            --noconfirm | -y | --yes)
                assert_interactive_unset "${1}"
                NOCONFIRM=1
                shift
                ;;
            -f | --force)
                assert_interactive_unset "${1}"
                FORCE=1
                shift
                ;;
            -K | --autorestart)
                DOTFILES_AUTORESTART=1
                autorestart_flag=1
                shift
                ;;
            --no-backup)
                NO_BACKUP=1
                shift
                ;;
            --no-deps)
                NO_DEPS=1
                shift
                ;;

                # logging
            -d | --debug)
                assert_log_level_unset "$1"
                LOG_LEVEL="debug"
                shift
                ;;
            -q | --quiet)
                assert_log_level_unset "$1"
                LOG_LEVEL="error"
                shift
                ;;
            --log-level)
                assert_log_level_unset "$1"
                require_arg     "$1" "${2:-}"
                local level="${2^^}"
                case "${level}" in
                    DEBUG | INFO | NOTICE | WARN | ERROR)
                        LOG_LEVEL="${level}"
                        shift 2
                        ;;
                    *)
                        die 2 'invalid log level "%s". Use: debug, info, notice, warn, or error' "$2"
                        ;;
                esac
                ;;
            --log-level=*)
                assert_log_level_unset "${1%%=*}"
                local level="${1#*=}"
                level="${level^^}"
                case "${level}" in
                    DEBUG | INFO | NOTICE | WARN | ERROR)
                        LOG_LEVEL="${level}"
                        ;;
                    *)
                        die 2 'invalid log level "%s". Use: debug, info, notice, warn, or error' "${1#*=}"
                        ;;
                esac
                shift
                ;;
            --no-log)
                if [[ -n $LOG_LEVEL   ]]; then
                    die 2 'log level already set to "%s". Cannot use %s.' "$LOG_LEVEL" "$1"
                fi
                NO_LOG=1
                shift
                ;;

            *)
                die 2 'invalid parameter "%s"\nRun `bash %s --help` for valid options.' "$1" "$(basename "$0")"
                ;;
        esac
    done

    # default values
    if [[ -z $LOG_LEVEL ]]; then
        case "${DOTFILES_ENV}" in
            development)
                LOG_LEVEL="DEBUG"
                ;;
             testing)
                LOG_LEVEL="TRACE"
                ;;
            production)
                LOG_LEVEL="INFO"
                ;;
        esac
    fi

    # validation
    if [[ -z $MAIN_ACTION ]]; then
        _exit 2
        die 2 'no action specified.\nRun `bash %s --help` for valid options.' "$(basename "$0")"
    fi
    case $MAIN_ACTION in
        remove | update | uninstall | reset | repair)
            [[ ${#INCLUDE_SET[@]} -gt 0 || ${#EXCLUDE_SET[@]} -gt 0 ]] \
                && _exit 2 && die 2 "--include/--exclude not supported with --$MAIN_ACTION"
            ;;
    esac

    if [[ $MAIN_ACTION == remove ]] && [[ ${#REMOVE_SET[@]} -eq 0 ]]; then
        _exit 2
        die 2 "no modules for --remove"
    fi
    if [[ $MAIN_ACTION == reset && $NO_BACKUP -eq 1 ]]; then
        _exit 2
        die 2 "--no-backup not allowed with --reset"
    fi

    case "${MAIN_ACTION}" in
        reset | uninstall | remove)
            if [[ ${NO_DEPS} -eq 1 ]]; then
                die 2 '--no-deps has no effect with --%s' "${MAIN_ACTION}"
            fi
            ;;
    esac

    if [[ ${MAIN_ACTION} == uninstall && ${NO_BACKUP} -eq 1 ]]; then
        _exit 2
        die 2 '--no-backup is redundant with --uninstall (it deletes backups itself)'
    fi

    if [[ ${DRY_RUN} -eq 1 ]]; then
        if [[ ${DOTFILES_AUTORESTART} -eq 1 ]]; then
            if [[ ${autorestart_flag} -eq 1 ]]; then
                _exit 2
                die 2 '--autorestart is not meaningful with --dry-run'
            fi
            DOTFILES_AUTORESTART=0
        fi

        if [[ ${interactive_flag} -eq 1 ]]; then
            _exit 2
            die 2 '--interactive is meaningless with --dry-run'
        fi
        if [[ ${FORCE} -eq 1 ]]; then
            _exit 2
            die 2 '--force is meaningless with --dry-run'
        fi
        if [[ ${NO_BACKUP} -eq 1 ]]; then
            _exit 2
            die 2 '--no-backup is meaningless with --dry-run'
        fi
        if [[ ${NO_DEPS} -eq 1 ]]; then
            _exit 2
            die 2 '--no-deps is meaningless with --dry-run'
        fi
    fi

    readonly MAIN_ACTION \
        REMOVE_SET INCLUDE_SET EXCLUDE_SET \
        DRY_RUN NOCONFIRM FORCE DOTFILES_AUTORESTART \
        NO_BACKUP NO_DEPS \
        LOG_LEVEL NO_LOG

    _exit
}
