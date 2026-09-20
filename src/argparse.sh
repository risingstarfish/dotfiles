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
        [[ -z "$m" ]] && continue

        valid=0
        if [[ "$m" == */* ]]; then
            for mod in "${AVAILABLE_MODULES[@]}"; do
                if [[ "$mod" == "$m" || "$mod" == "$m/"* ]]; then
                    valid=1
                    break
                fi
            done
        else
            for mod in "${AVAILABLE_MODULES[@]}"; do
                [[ "${mod%%/*}" == "$m" ]] && valid=1 && break
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

assert_no_action() {
    if [[ -n "$ACTION" ]]; then
        printf 'Error: action already set to "%s". Conflicting flag: %s\n' "$ACTION" "$1" >&2
        exit 2
    fi
}

assert_log_level_unset() {
    if [[ -n "$LOG_LEVEL" ]]; then
        printf 'Error: log level already set to "%s". Conflicting flag: %s\n' "$LOG_LEVEL" "$1" >&2
        exit 2
    fi
    if [[ "$LOG_ENABLED" -eq 0 ]]; then
        printf 'Error: --no-log was specified. Conflicting flag: %s\n' "$1" >&2
        exit 2
    fi
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
    ACTION=""
    # INSTALL=0
    # UNINSTALL=0
    # UPDATE=0
    # REPAIR=0
    # RESET=0

    INCLUDE_MODULES=()
    EXCLUDE_MODULES=()

    DRY_RUN=0
    INTERACTIVE=0
    NOCONFIRM=0
    FORCE=0
    DOTFILES_AUTORESTART=0
    NO_BACKUP=0
    NO_DEPS=0

    LOG_LEVEL=''
    LOG_ENABLED=1

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
            --examples)
                print_examples
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
                assert_no_action "$1"
                ACTION="install"
                shift
                ;;
            --uninstall)
                assert_no_action "$1"
                ACTION="uninstall"
                shift
                ;;
            -u | --update)
                assert_no_action "$1"
                ACTION="update"
                shift
                ;;
            -r | --repair)
                assert_no_action "$1"
                ACTION="repair"
                shift
                ;;
            --reset)
                assert_no_action "$1"
                ACTION="reset"
                shift
                ;;

            # modules
            -i | --include)
                require_arg "$1" "${2:-}"
                parse_module_list "$2" INCLUDE_MODULES
                shift 2
                ;;
            -i=* | --include=*)
                parse_module_list "${1#*=}" INCLUDE_MODULES
                shift
                ;;
            -x | --exclude)
                require_arg "$1" "${2:-}"
                parse_module_list "$2" EXCLUDE_MODULES
                shift 2
                ;;
            -x=* | --exclude=*)
                parse_module_list "${1#*=}" EXCLUDE_MODULES
                shift
                ;;

            # behaviour
            -n | --dry-run)
                DRY_RUN=1
                shift
                ;;
            -I | --interactive)
                INTERACTIVE=1
                shift
                ;;
            --noconfirm | -y | --yes)
                NOCONFIRM=1
                shift
                ;;
            -f | --force)
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
                    debug |     info | warn | error)
                        LOG_LEVEL="$2"
                        shift     2
                        ;;
                    *)
                        printf     'Error: invalid log level "%s". Use: debug, info, warn, or error\n' "$2" >&2
                        exit     2
                        ;;
                esac
                ;;
            --log-level=*)
                assert_log_level_unset "$1"
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
                if [[ -n "$LOG_LEVEL" ]]; then
                    printf 'Error: log level already set to "%s". Cannot use %s.\n' "$LOG_LEVEL" "$1" >&2
                    exit 2
                fi
                LOG_ENABLED=0
                shift
                ;;

            *)
                printf 'Error: invalid parameter "%s"\n' "$1" >&2
                printf 'Run `bash %s --help` for valid options.\n' "$(basename "$0")" >&2
                exit 2
                ;;
        esac
    done

    # default values
    if [[ -z "$LOG_LEVEL" ]]; then
        LOG_LEVEL="info"
    fi

    if [[ -z "$ACTION" ]]; then
        printf 'Error: no action specified. Use --install, --update, --repair, --reset, or --uninstall.\n' >&2
        exit 2
    fi

    case "$ACTION" in
        install)
            #run_install
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
