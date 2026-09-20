#!/usr/bin/env bash
# argparse.sh

if [[ -n ${__ARGPARSE_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __ARGPARSE_SH_INCLUDED__=1

parse_module_list()  {
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
                [[ ${mod%%/*} == "$m"   ]] && valid=1 && break
            done
        fi

        if [[ $valid -eq 0 ]]; then
            printf 'Error: unknown module "%s".\n' "$m" >&2
            printf 'Run with --list to see valid modules.\n' >&2
            exit 2
        fi
        arr+=("$m")
    done
}

# $1 = value to test
# $2 = full message
# $3 = new flag
_assert_string_unset() {
    if [[ -n ${1}   ]]; then
        printf 'Error: %s. Conflicting flag: "%s"\n' "${2}" "${3}" >&2
        exit 2
    fi
}

# $1 = sentinel value (0 = unset, 1 = set)
# $2 = message
# $3 = flag name
_assert_flag_unset() {
    if [[ $1 -eq 1     ]]; then
        printf 'Error: %s. Conflicting flag: "%s"\n' "${2}" "${3}" >&2
        exit 2
    fi
}

assert_main_action_unset() {
    _assert_string_unset "${MAIN_ACTION}" "action already set to \"${MAIN_ACTION}\"" "${1}"
}

assert_log_level_unset() {
    _assert_string_unset "${LOG_LEVEL}" "log level already set to \"${LOG_LEVEL}\"" "${1}"
    _assert_flag_unset "${NO_LOG}" "logging is disabled via --no-log" "${1}"
}

assert_exclude_modules_unset() {
    _assert_flag_unset "${EXCLUDE_SET}" "excluded modules is already set" "${1}"
}
assert_include_modules_unset() {
    _assert_flag_unset "${INCLUDE_SET}" "included modules is already set" "${1}"
}

assert_interactive_unset() {
    _assert_flag_unset "${INTERACTIVE}" "interactive mode is already set" "$1"
}
assert_noconfirm_unset() {
    _assert_flag_unset "${NOCONFIRM}" "noconfirm is already set" "$1"
}
assert_force_unset() {
    _assert_flag_unset "${FORCE}" "force mode is already set" "$1"
}

# $1 = flag name (for error message)
# $2 = value to validate
require_arg() {
    if [[ -z ${2:-} || ${2} == -* ]]; then
        printf 'Error: missing argument for %s.\n' "$1" >&2
        exit 2
    fi
}

argparse() {
    MAIN_ACTION=""

    REMOVE_SET=()

    INCLUDE_SET=()
    EXCLUDE_SET=()

    DRY_RUN=0
    INTERACTIVE=0
    NOCONFIRM=0
    FORCE=0
    DOTFILES_AUTORESTART=${DOTFILES_AUTORESTART:-0}
    NO_BACKUP=0
    NO_DEPS=0

    LOG_LEVEL=""
    NO_LOG=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            # information
            -h | --help)
                print_help
                exit 0
                ;;
            --version)
                print_version
                exit 0
                ;;
            --verify)
                local verify_rc=0
                print_verification || verify_rc=$?
                exit "${verify_rc}"
                ;;
            -l | --list)
                list_modules
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
                INTERACTIVE=1
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
            -v | --verbose)
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
                case "$2" in
                    debug | info | warn | error)
                        LOG_LEVEL="$2"
                        shift 2
                        ;;
                    *)
                        printf 'Error: invalid log level "%s". Use: debug, info, warn, or error\n' "$2" >&2
                        exit 2
                        ;;
                esac
                ;;
            --log-level=*)
                assert_log_level_unset "${1%%=*}"
                case "${1#*=}" in
                    debug | info | warn | error)
                        LOG_LEVEL="${1#*=}"
                        ;;
                    *)
                        printf 'Error: invalid log level "%s". Use: debug, info, warn, or error\n' "${1#*=}" >&2
                        exit 2
                        ;;
                esac
                shift
                ;;
            --no-log)
                if [[ -n $LOG_LEVEL   ]]; then
                    printf 'Error: log level already set to "%s". Cannot use %s.\n' "$LOG_LEVEL" "$1" >&2
                    exit 2
                fi
                NO_LOG=1
                shift
                ;;

            *)
                printf 'Error: invalid parameter "%s"\n' "$1" >&2
                print_help_error_msg
                exit 2
                ;;
        esac
    done

    # default values
    if [[ -z $LOG_LEVEL ]]; then
        LOG_LEVEL="info"
    fi

    # validation
    if [[ -z $MAIN_ACTION ]]; then
        printf 'Error: no action specified. Use --install, --update, --remove, --repair, --reset, or --uninstall.\n' >&2
        print_help_error_msg
        exit 2
    fi

    if [[ ${MAIN_ACTION} == "remove" ]]; then
        if [[ ${#INCLUDE_SET[@]} -gt 0 || ${#EXCLUDE_SET[@]} -gt 0 ]]; then
            printf 'Error: --include/--exclude is not supported with --remove\n' >&2
            exit 2
        fi
    fi

    if [[ ${MAIN_ACTION} == "update" ]]; then
        if [[ ${#INCLUDE_SET[@]} -gt 0 || ${#EXCLUDE_SET[@]} -gt 0 ]]; then
            printf 'Error: --include/--exclude is not supported with --update\n' >&2
            exit 2
        fi
    fi

    if [[ ${NO_BACKUP} -eq 1 && ${MAIN_ACTION} == "reset" ]]; then
        printf 'Error: --no-backup is not allowed with --reset\n' >&2
        exit 2
    fi

    if [[ ${#REMOVE_SET[@]} -eq 0 && ${MAIN_ACTION} == "remove" ]]; then
        printf 'Error: no modules specified for --remove\n' >&2
        exit 2
    fi

    case "$MAIN_ACTION" in
        install)
            #run_install
            ;;
        remove)
            #run_remove
            ;;
        uninstall)
            #run_uninstall
            ;;
        update)
            #run_update
            ;;
        repair)
            #run_repair
            ;;
        reset)
            #run_reset
            ;;
    esac
}
