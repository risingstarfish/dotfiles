#!/usr/bin/env bash
# argparse.sh

if [[ -n ${__ARGPARSE_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __ARGPARSE_SH_INCLUDED__=1

argparse() {
    UNINSTALL=0
    # setup
    DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-${HOME}/dotfiles}"
    DOTFILES_REF="$(dotfiles::default_ref)"
    # behaviour
    DOTFILES_AUTORESTART="${DOTFILES_AUTORESTART:-0}"
    DOTFILES_LOG="${DOTFILES_LOG:-1}"

    DRY_RUN=0
    FORCE=0
    UPDATE=0
    UPDATE_ONLY=0
    INTERACTIVE=0
    NO_BACKUP=0
    NO_DEPS=0
    NO_HOOKS=0
    NOCONFIRM=0
    VERBOSE=0
    QUIET=0
    MODE=""
    REPAIR_SYMLINKS=0
    CLEAN_BACKUPS_DAYS=""
    CLEAN_LOGS_DAYS=""
    LOG_LEVEL="info"
    INCLUDE_MODULES=()
    EXCLUDE_MODULES=()
    # restore
    RESTORE_FILES=()
    RESTORE_ALL=0
    RESTORE_FROM=""
    # backup
    BACKUP_FILES=()
    DO_BACKUP=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            # information
            -h | --help)
                dotfiles::print_help
                exit 0
                ;;
            --version)
                dotfiles::print_version
                exit 0
                ;;
            --examples)
                dotfiles::print_examples
                exit 0
                ;;
            --verify)
                local verify_rc=0
                dotfiles::print_verification || verify_rc=$?
                exit "${verify_rc}"
                ;;
            -d | --diff)
                dotfiles::assign_mode "--diff" "diff"
                shift
                ;;

            # actions
            -u | --update)
                UPDATE=1
                shift
                ;;
            # cleaning
            -r | --repair)
                REPAIR_SYMLINKS=1
                shift
                ;;
            --reset)
                dotfiles::assign_mode "--reset" "reset"
                shift
                ;;
            -b | --backup) # FIXME: delete
                DO_BACKUP=1
                shift
                if [[ -z ${2:-} || $2 == -* ]]; then
                    :
                else
                    shift
                    while [[ $# -gt 0 && $1 != -* ]]; do
                        BACKUP_FILES+=("$1")
                        shift
                    done
                    #dotfiles::check_exists "${BACKUP_FILES[@]}"
                fi
                ;;
            --clean-backups)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    CLEAN_BACKUPS_DAYS="7"
                    shift
                else
                    if ! [[ $2 =~ ^[0-9]+$ ]]; then
                        dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
                        exit 1
                    fi
                    CLEAN_BACKUPS_DAYS="$2"
                    shift 2
                fi
                ;;
            --clean-backups=*)
                if ! [[ ${1#*=} =~ ^[0-9]+$ ]]; then
                    dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "--clean-backups" "${1#*=}" >&2
                    exit 1
                fi
                CLEAN_BACKUPS_DAYS="${1#*=}"
                shift
                ;;
            --clean-logs)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    CLEAN_LOGS_DAYS="7"
                    shift
                else
                    if ! [[ $2 =~ ^[0-9]+$ ]]; then
                        dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
                        exit 1
                    fi
                    CLEAN_LOGS_DAYS="$2"
                    shift 2
                fi
                ;;
            --clean-logs=*)
                if ! [[ ${1#*=} =~ ^[0-9]+$ ]]; then
                    dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "--clean-logs" "${1#*=}" >&2
                    exit 1
                fi
                CLEAN_LOGS_DAYS="${1#*=}"
                shift
                ;;
            --clean-all)
                CLEAN_BACKUPS_DAYS="0"
                CLEAN_LOGS_DAYS="0"
                shift
                ;;
            --uninstall)
                UNINSTALL=1
                shift
                ;;

            # modules
            -i | --include)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
                    exit 1
                fi
                dotfiles::parse_module_list "$2" INCLUDE_MODULES
                shift 2
                ;;
            -i=* | --include=*)
                dotfiles::parse_module_list "${1#*=}" INCLUDE_MODULES
                shift
                ;;
            -x | --exclude)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
                    exit 1
                fi
                dotfiles::parse_module_list "$2" EXCLUDE_MODULES
                shift 2
                ;;
            -x=* | --exclude=*)
                dotfiles::parse_module_list "${1#*=}" EXCLUDE_MODULES
                shift
                ;;
            -l | --list)
                dotfiles::print_modules
                exit 0
                ;;

            # git
            -p | --pull)
                UPDATE_ONLY=1
                shift
                ;;
            --ref)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
                    exit 1
                fi
                DOTFILES_REF="$2"
                shift 2
                ;;
            --ref=*)
                DOTFILES_REF="${1#*=}"
                shift
                ;;

            # restore
            --restore)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
                    exit 2
                else
                    shift
                    while [[ $# -gt 0 && $1 != -* ]]; do
                        RESTORE_FILES+=("$1")
                        shift
                    done
                    #dotfiles::check_exists "${RESTORE_FILES[@]}"
                fi
                ;;
            --restore-all)
                RESTORE_ALL=1
                shift
                ;;
            --from)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
                    exit 1
                fi
                RESTORE_FROM="$2"
                shift 2
                ;;
            --from=*)
                RESTORE_FROM="${1#*=}"
                shift
                ;;
            --backup-list)
                if [[ -z ${2:-} || $2 == -* ]]; then
                    :
                else
                    if ! [[ $2 =~ ^[0-9]+$ ]]; then
                        dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "$1" "$2" >&2
                        exit 1
                    fi
                fi
                dotfiles::print_backups "${2:-${DEFAULT_NUM_BACKUP_PRINT}}"
                exit 0
                ;;
            --backup-list=*)
                if ! [[ ${1#*=} =~ ^[0-9]+$ ]]; then
                    dotfiles::println 'Error: Argument for %s must be a non-negative integer (days). Got "%s".' "--backup-list" "${1#*=}" >&2
                    exit 1
                fi
                dotfiles::print_backups "$1"
                exit 0
                ;;

            # behaviour
            -n | --dry-run)
                DRY_RUN=1
                shift
                ;;
            -I | --interactive)
                if [[ ${NOCONFIRM} -eq 1 ]]; then
                    dotfiles::println 'Error: %s conflicts with --noconfirm.' "$1" >&2
                    exit 1
                fi
                INTERACTIVE=1
                shift
                ;;
            --noconfirm | -y | --yes)
                if [[ ${INTERACTIVE} -eq 1 ]]; then
                    dotfiles::println 'Error: %s conflicts with --interactive.' "$1" >&2
                    exit 1
                fi
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

            # logging
            -v | --verbose)
                VERBOSE=1
                LOG_LEVEL="debug"
                shift
                ;;
            -q | --quiet)
                QUIET=1
                LOG_LEVEL="error"
                shift
                ;;
            --log-level)
                if [[ -n ${2:-} && $2 != -* ]]; then
                    case "$2" in
                        debug | info | warn | error)
                            LOG_LEVEL="$2"
                            shift 2
                            ;;
                        *)
                            dotfiles::println 'Error: Invalid log level "%s". Use: debug, info, warn, error.' "$2" >&2
                            exit 1
                            ;;
                    esac
                else
                    dotfiles::println 'Error: Missing argument for %s.' "$1" >&2
                    exit 1
                fi
                ;;
            --log-level=*)
                case "${1#*=}" in
                    debug | info | warn | error)
                        LOG_LEVEL="${1#*=}"
                        shift
                        ;;
                    *)
                        dotfiles::println 'Error: Invalid log level "%s". Use: debug, info, warn, error.' "${1#*=}" >&2
                        exit 1
                        ;;
                esac
                ;;
            --no-log)
                DOTFILES_LOG=0
                shift
                ;;

            # packages
            --no-deps)
                NO_DEPS=1
                shift
                ;;
            --no-hooks)
                NO_HOOKS=1
                shift
                ;;

            *)
                dotfiles::println 'Error: Invalid parameter "%s"' "$1" >&2
                dotfiles::println 'Run `bash %s --help` for valid options.' "$(basename "$0")" >&2
                exit 1
                ;;
        esac
    done

    if ((UNINSTALL)); then
        dotfiles::uninstall || {
            cat << EOF
  You can attempt to run the uninstallation again. If it continues to fail, you may need to
  manually delete all relevant directories:
    Install   |  \""${SRC_PATH}"\"
	Log       |  \""${DOTFILES_LOG_DIR}"\"
	Cache     |  \""${DOTFILES_CACHE_DIR}"\"

EOF
            exit 1
        }
        exit 0

    fi

    # post validation
    local has_maintenance=0
    [[ -n ${CLEAN_BACKUPS_DAYS} || -n ${CLEAN_LOGS_DAYS}   ]] && has_maintenance=1

    # repair and reset are mutually exclusive
    if [[ ${REPAIR_SYMLINKS} -eq 1 && ${MODE} == "reset"   ]]; then
        dotfiles::println 'Error: --repair conflicts with --reset.' >&2
        exit 1
    fi

    # maintenance cannot combine with explicit install/exclude
    if [[ ${has_maintenance} -eq 1 ]]; then
        if [[ ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
            dotfiles::println 'Error: --clean-* is not valid with --include.' >&2
            exit 1
        fi
        if [[ ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
            dotfiles::println 'Error: --clean-* is not valid with --exclude.' >&2
            exit 1
        fi
    fi

    # restore conflicts with install/exclude
    local has_restore=0
    [[ ${#RESTORE_FILES[@]} -gt 0 || ${RESTORE_ALL} -eq 1 ]] && has_restore=1

    if [[ ${has_restore} -eq 1 ]]; then
        if [[ ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
            dotfiles::println 'Error: --restore is not valid with --include.' >&2
            exit 1
        fi
        if [[ ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
            dotfiles::println 'Error: --restore is not valid with --exclude.' >&2
            exit 1
        fi
        if [[ ${MODE} == "reset" ]]; then
            dotfiles::println 'Error: --restore conflicts with --reset.' >&2
            exit 1
        fi
    fi

    # --from requires --restore or --restore-all
    if [[ -n ${RESTORE_FROM} && ${has_restore} -eq 0 ]]; then
        dotfiles::println 'Error: --from requires --restore or --restore-all.' >&2
        exit 1
    fi

    if [[ -z $MODE ]]; then
        MODE="install"
    fi

    if [[ $MODE != "install" && ${#INCLUDE_MODULES[@]} -gt 0 ]]; then
        dotfiles::println 'Error: --include is not valid with --%s.' "$MODE" >&2
        exit 1
    fi
    if [[ $MODE != "install" && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
        dotfiles::println 'Error: --exclude is not valid with --%s.' "$MODE" >&2
        exit 1
    fi
    if [[ ${#INCLUDE_MODULES[@]} -gt 0 && ${#EXCLUDE_MODULES[@]} -gt 0 ]]; then
        dotfiles::println 'Error: --include and --exclude are mutually exclusive.' >&2
        exit 1
    fi
}
