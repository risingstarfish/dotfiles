#!/usr/bin/env bash
# action.sh

if [[ -n ${__ACTION_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __ACTION_SH_INCLUDED__=1

set_user_modules() {
    _enter

    if [[ -n ${USER_MODULES:-}  ]]; then
        log_debug "USER_MODULES is already populated. Skipping."
        log_trace "Exiting (already populated)"
        _exit
        return 0
    fi

    local num_inc=${#INCLUDE_SET[@]}
    local num_exc=${#EXCLUDE_SET[@]}
    local num_total=${#AVAILABLE_MODULES[@]}
    local num_target

    log_trace "Set counts -> num_inc=${num_inc}, num_exc=${num_exc}, num_total=${num_total}"

    if ((num_inc > 0)); then
        num_target=${num_inc}
    elif ((num_exc > 0)); then
        num_target=$((num_total > num_exc ? num_total - num_exc : 0))
    else
        num_target=${num_total}
    fi

    log_debug "Processing ${num_target}/${num_total} modules."

    local mod inc exc included excluded
    local mod_slash

    for mod in "${AVAILABLE_MODULES[@]}"; do
        mod_slash="${mod}/"
        log_trace "Evaluating module '${mod}' (mod_slash='${mod_slash}')"

        if ((num_inc > 0)); then
            included=0
            for inc in "${INCLUDE_SET[@]}"; do
                log_trace "Testing include filter '${inc}/'* against '${mod_slash}'"
                if [[ ${mod_slash} == "${inc}/"*     ]]; then
                    included=1
                    log_trace "Match found for include filter '${inc}'"
                    break
                fi
            done
            if ! ((included)); then
                log_debug "Skipped '${mod}' (not in INCLUDE_SET)"
                log_trace "Module '${mod}' skipped because it did not match INCLUDE_SET"
                continue
            fi
        fi

        if ((num_exc > 0)); then
            excluded=0
            for exc in "${EXCLUDE_SET[@]}"; do
                log_trace "Testing exclude filter '${exc}/'* against '${mod_slash}'"
                if [[ ${mod_slash} == "${exc}/"* ]]; then
                    excluded=1
                    log_trace "Match found for exclude filter '${exc}'"
                    break
                fi
            done
            if ((excluded)); then
                log_debug "Skipped '${mod}' (matched EXCLUDE_SET)"
                log_trace "Module '${mod}' skipped because it matched EXCLUDE_SET"
                continue
            fi
        fi
        log_debug "Added '${mod}'"
        log_trace "Appending '${mod}' to USER_MODULES"
        USER_MODULES+=("${mod}")
    done

    log_info "Selected ${#USER_MODULES[@]} total modules for processing."

    _exit
    readonly USER_MODULES
}

set_file_types() {
    _enter
    if [[ -n ${SYMLINK_FILES:-} || -n ${COPY_FILES:-} || -n ${GENERATE_FILES:-} ]]; then
        log_debug "SYMLINK_FILES, COPY_FILES, and GENERATE_FILES are already populated. Skipping categorisation."
        log_trace "Exiting (already populated)"
        _exit
        return 0
    fi

    log_debug "Categorising ${#USER_MODULES[@]} files..."

    local file
    local base
    for file in "${USER_MODULES[@]}"; do
        base="${file##*/}"
        if [[ ${base} == *.local || ${base} == *.local.* ]]; then
            log_debug "[COPY] ${base}"
            log_trace "Matched COPY pattern (*.local / *.local.*) -> adding to COPY_FILES"
            COPY_FILES+=("${file}")
        elif [[ ${base} == *.gen ]]; then
            log_debug "[GENERATE] ${base}"
            log_trace "Matched GENERATE pattern (*.gen) -> adding to GENERATE_FILES"
            GENERATE_FILES+=("${file}")
        else
            log_debug "[SYMLINK] ${base}"
            log_trace "Default match -> adding to SYMLINK_FILES"
            SYMLINK_FILES+=("${file}")
        fi
    done

    log_info "Categorised ${#SYMLINK_FILES[@]} symlinks, ${#COPY_FILES[@]} copies, \
${#GENERATE_FILES[@]} generated."
    readonly SYMLINK_FILES COPY_FILES GENERATE_FILES
    _exit
}

set_dotfiles_ref() {
    _enter

    if [[ -n ${DOTFILES_REF:-} ]]; then
        log_debug "DOTFILES_REF already set to '${DOTFILES_REF}'. Skipping."
        log_trace "Exiting (DOTFILES_REF already set)"
        _exit
        return 0
    fi

    log_debug "Determining git ref for '${SRC_PATH}'..."

    log_trace "Executing: git -C '${SRC_PATH}' rev-parse --git-dir"
    if ! git -C "${SRC_PATH}" rev-parse --git-dir > /dev/null 2>&1; then
        log_trace "git rev-parse failed (not a git repository)"
        log_error "Unable to determine git ref. Make sure '${SRC_PATH}' is a git repo."
        log_trace "Exiting with status 1"
        _exit 1
        return 1
    fi

    local config_ref
    log_trace "Executing: git -C '${SRC_PATH}' config --local dotfiles.ref"
    config_ref="$(git -C "${SRC_PATH}" config --local dotfiles.ref 2> /dev/null || true)"
    log_trace "Retrieved config_ref='${config_ref}'"

    if [[ -n ${config_ref} ]]; then
        DOTFILES_REF="${config_ref}"
        log_debug "Found custom ref in git config."
        log_trace "Assigned DOTFILES_REF='${DOTFILES_REF}' from git config"
    else
        DOTFILES_REF="main"
        log_debug "No custom git config found. Falling back to default."
        log_trace "Assigned DOTFILES_REF='main' (default fallback)"
    fi

    _exit
    readonly DOTFILES_REF
}

do_install() {
    _enter

    local USER_MODULES=()
    local SYMLINK_FILES=()
    local COPY_FILES=()
    local GENERATE_FILES=()

    log_info "Beginning installation!"

    log_trace "Calling set_user_modules()"
    set_user_modules # USER_MODULES
    log_trace "Returned from set_user_modules() (USER_MODULES count: ${#USER_MODULES[@]})"

    log_trace "Calling set_file_types()"
    set_file_types   # SYMLINK_FILES COPY_FILES GENERATE_FILES
    log_trace "Returned from set_file_types() (SYMLINK: ${#SYMLINK_FILES[@]}, COPY: ${#COPY_FILES[@]}, GENERATE: ${#GENERATE_FILES[@]})"

    log_debug "Initialized local module and file arrays"

    local rc=0
    log_trace "Initialized status tracer rc=${rc}"

    install_all || rc=1

    log_trace "Evaluating final status code rc=${rc}"
    if ((rc)); then
        log_trace "Error state detected!"
        log_error 'Install finished with errors!' # TODO: print total number
        log_trace "Exiting with status 1"
        _exit 1
        return 1
    fi

    log_info 'Installation complete!'
    _exit
}

do_update() {
    _enter

    local DOTFILES_REF

    set_dotfiles_ref || { # DOTFILES_REF
        log_trace "set_dotfiles_ref failed with exit status $?, exiting"
        _exit 1
        exit 1
    }
    log_trace "Resolved DOTFILES_REF='${DOTFILES_REF}'"

    log_info "Beginning update!"

    log_trace "Checking for repository at '${SRC_PATH}/.git'"
    if [[ ! -d "${SRC_PATH}/.git" ]]; then
        log_trace "Directory '${SRC_PATH}/.git' does not exist"
        die 1 '%s is not a git clone. Run with --install first.' "${SRC_PATH}"
    fi

    local has_local_mods=0
    log_trace "Executing: git -C '${SRC_PATH}' diff --quiet HEAD"
    if ! command git -C "${SRC_PATH}" diff --quiet HEAD 2> /dev/null; then
        has_local_mods=1
    fi
    log_trace "Local modifications status: has_local_mods=${has_local_mods}"

    log_info "Updating dotfiles in ${SRC_PATH} (ref: ${DOTFILES_REF})"

    if  ((has_local_mods))  && ! is_true "${DOTFILES_LOCAL_MODS}"; then
        log_trace "Update blocked: has_local_mods=${has_local_mods}, DOTFILES_LOCAL_MODS=${DOTFILES_LOCAL_MODS}"
        log_warn "Uncommitted changes in ${SRC_PATH}. Update blocked."
        {
            printf '\n'
            printf '  This repo is publicly maintained. Do not edit tracked files directly.\n'
            printf '  Use .local override files for personal customisation:\n'
            printf '    e.g.  tmux.conf  ->  tmux.conf.local\n'
            printf '\n'
            printf '  Revert your changes or move them to .local file, then re-run.\n'
            printf '  (dev: set DOTFILES_LOCAL_MODS=1 to bypass this check)\n'
            printf '\n'
        } >&2
        log_trace "Executing: git -C '${SRC_PATH}' diff --stat HEAD"
        command git -C "${SRC_PATH}" diff --stat HEAD 2> /dev/null >&2
        _exit 1
        return 1
    fi

    log_trace "Executing: git -C '${SRC_PATH}' fetch origin --depth=1 '${DOTFILES_REF}'"
    if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "${DOTFILES_REF}" 2> /dev/null; then
        log_trace "git fetch command failed"
        log_error "Fetch failed (ref: ${DOTFILES_REF}). Check network or repo URL."
        _exit 1
        return 1
    fi

    if [[ -f ${DOTFILES_MANIFEST_FILE} ]]; then
        local tmp
        tmp="$(mktemp)"
        printf '# ref=%s timestamp=%s\n' "${DOTFILES_REF}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${tmp}"
        cat "${DOTFILES_MANIFEST_FILE}" >> "${tmp}"
        mv "${tmp}" "${DOTFILES_MANIFEST_FILE}"
    fi

    if  ((has_local_mods))  && is_true "${DOTFILES_LOCAL_MODS}"; then
        log_trace "Attempting rebase branch: has_local_mods=${has_local_mods}, DOTFILES_LOCAL_MODS=${DOTFILES_LOCAL_MODS}"
        log_warn "Local modifications present. Rebasing onto FETCH_HEAD."
        log_trace "Executing: git -C '${SRC_PATH}' rebase FETCH_HEAD"
        if ! command git -C "${SRC_PATH}" rebase FETCH_HEAD 2> /dev/null; then
            log_trace "git rebase failed"
            log_error "Rebase failed."
            printf '\n' >&2
            printf '  Resolve conflicts, then:\n' >&2
            printf '    git -C "%s" rebase --continue\n' "${SRC_PATH}" >&2
            printf '  Or abort with:\n' >&2
            printf '    git -C "%s" rebase --abort\n' "${SRC_PATH}" >&2
            _exit 1
            return 1
        fi
    else
        if ((has_local_mods)); then
            log_trace "Local mods present without override; checking user confirmation prompt"
            _attempt_cmd "git -C '\"${SRC_PATH}\"' reset --hard FETCH_HEAD" \
                "This discards ALL local changes in '${SRC_PATH}'" \
                "Reset to ${DOTFILES_REF} failed in '${SRC_PATH}'." \
                "Reset local repository." || return 1
            # if ((NOCONFIRM)); then
            #     log_trace "NOCONFIRM is set (${NOCONFIRM}); bypassing interactive prompt"
            # else
            #     log_info "About to run: git reset --hard FETCH_HEAD"
            #     printf '\n' >&2
            #     printf '  This discards ALL local changes in %s.\n' "${SRC_PATH}" >&2
            #     printf '  Continue? [Y/n] ' >&2
            #     local reply
            #     read -r reply
            #     log_trace "User prompt reply: '${reply}'"
            #     case "${reply,,}" in
            #         y | yes | '')
            #             log_trace "User confirmed reset"
            #             ;;
            #         *)
            #             log_trace "User rejected reset prompt"
            #             log_warn "Reset cancelled by user."
            #             log_trace "Exiting ${FUNCNAME[0]}() with status 1 (user cancelled)"
            #             return 1
            #             ;;
            #     esac
            #     printf '\n' >&2
            # fi

            # log_trace "Executing: git -C '${SRC_PATH}' reset --hard FETCH_HEAD"
            # if ! command git -C "${SRC_PATH}" reset --hard FETCH_HEAD 2> /dev/null; then
            #     log_trace "git reset failed"
            #     log_error "Reset to ${DOTFILES_REF} failed in ${SRC_PATH}."
            #     log_trace "Exiting ${FUNCNAME[0]}() with status 1 (reset failed)"
            #     return 1
            # fi
        fi

        log_trace "Checking branch existence: refs/heads/${DOTFILES_REF}"
        if command git -C "${SRC_PATH}" show-ref --verify --quiet "refs/heads/${DOTFILES_REF}" 2> /dev/null; then
            log_trace "Updating branch pointer: git -C '${SRC_PATH}' branch -f '${DOTFILES_REF}' FETCH_HEAD"
            command git -C "${SRC_PATH}" branch -f "${DOTFILES_REF}" FETCH_HEAD 2> /dev/null || true
        else
            log_trace "Branch 'refs/heads/${DOTFILES_REF}' not found locally; skipping branch update"
        fi
    fi

    _exit
    return 0
}

remove_file() {
    _enter
    local dest="${1:-}"

    if [[ -z ${dest} ]]; then
        log_error "remove_file: no destination provided."
        _exit 1
        return 1
    fi

    if [[ ! -e ${dest} && ! -L ${dest} ]]; then
        log_trace "remove_file: '${dest}' does not exist. Nothing to remove."
        _exit
        return 0
    fi

    if ((DRY_RUN)); then
        log_info "[dry-run] rm -f ${dest}"
        _exit
        return 0
    fi

    if ! rm -f "${dest}" 2> /dev/null; then
        log_error "Failed to remove '${dest}'"
        _exit 1
        return 1
    fi

    manifest_remove "${dest}"
    log_debug "Removed: ${dest}"
    _exit
    return 0
}

do_uninstall() {
    _enter

    local ec=0
    local -a failed_files=()

    log_info "Beginning uninstall."

    # ── 1. Remove every file recorded in the manifest ──────────────
    local -A installed_src=()
    manifest_read installed_src
    local entry_count=${#installed_src[@]}
    log_debug "Manifest holds ${entry_count} installed entr$( ((entry_count == 1)) && printf 'y' || printf 'ies' )."

    if ((entry_count > 0)); then
        local reply
        printf '\n  This will remove %d installed file(s):\n' "${entry_count}" >&2
        local dest
        for dest in "${!installed_src[@]}"; do
            printf '    - %s\n' "${dest}" >&2
        done
        printf '\n  Continue? [Y/n] ' >&2
        read -r reply || reply=""
        log_trace "User prompt reply: '${reply}'"
        case "${reply,,}" in
            y | yes | '')
                log_trace "User confirmed manifest removal"
                ;;
            *)
                log_warn "Uninstall cancelled by user."
                _exit 130
                exit 130
                ;;
        esac
        printf '\n' >&2

        local dest src
        for dest in "${!installed_src[@]}"; do
            src="${installed_src["${dest}"]}"
            log_trace "Removing manifest entry: '${dest}' (source: '${src}')"
            if ! remove_file "${dest}"; then
                ((++ec))
                failed_files+=("${dest}")
            fi
        done
    else
        log_warn "No modules found to uninstall."
        if ! ((NOCONFIRM)); then
            prompt_continue
        fi
    fi

    # NOTE: redundant with cache dir
    _attempt_cmd "rm -rf \"${DOTFILES_BACKUP_DIR}\"" \
        "Are you sure you want to completely remove dotfiles backup directory?" \
        "Failed to removed \"${DOTFILES_BACKUP_DIR}\"" \
        "Successfully removed backup directory!" || ((++ec))
    _attempt_cmd "rm -rf \"${DOTFILES_CACHE_DIR}\"" \
        "Are you sure you want to completely remove dotfiles cache directory?" \
        "Failed to removed \"${DOTFILES_CACHE_DIR}\"" \
        "Successfully removed cache directory!" || ((++ec))
    _attempt_cmd "rm -rf \"${SRC_PATH}\"" \
        "Are you sure you want to completely remove dotfiles?" \
        "Failed to removed \"${SRC_PATH}\"" \
        "Successfully removed repository!" || ((++ec))

    if [[ ${ec} -gt 0 ]]; then
        log_error "Uninstall finished with ${ec} error(s)!"
        if [[ ${#failed_files[@]} -gt 0 ]]; then
            printf '\n  Failed to remove the following file(s):\n' >&2
            local f
            for f in "${failed_files[@]}"; do
                printf '    ✗ %s\n' "${f}" >&2
            done
            printf '\n' >&2
        fi
    else
        log_info "Uninstall finished successfully!"
    fi

    local reply
    printf '\n  Remove log directory: %s ? [Y/n] ' "${DOTFILES_LOG_DIR}" >&2
    read -r reply || reply=""
    case "${reply,,}" in
        y | yes | '') ;;
        *)
            log_warn "Log directory removal cancelled by user."
            _exit
            return "${ec}"
            ;;
    esac

    LOG_FILE=""  # stop writing to file; console still works
    if ! ((DRY_RUN)); then
        if ! rm -rf "${DOTFILES_LOG_DIR}" 2> /dev/null; then
            log_info "Failed to remove ${DOTFILES_LOG_DIR}"
            ((++ec))
        else
            log_info "Successfully removed log directory!"
        fi
    else
        log_info "[dry-run] rm -rf ${DOTFILES_LOG_DIR}"
    fi

    UNINSTALL_ERRORS="${ec}"
    _exit "${ec}"
    return "${ec}"
}

# Populates three caller-supplied parallel arrays from the manifest.
#
# Usage:
#   local -a m_srcs=() m_dests=() m_types=()
#   _read_manifest_entries m_srcs m_dests m_types "reset" || return 0
#
# $1 = nameref → array of source paths
# $2 = nameref → array of dest paths
# $3 = nameref → array of types (symlink|copy|generate)
# $4 = context string for log messages (e.g. "reset", "repair")
#
# Returns:
#   0  arrays populated, caller may proceed
#   1  no manifest or empty — caller should return 0
_read_manifest_entries() {
    _enter
    local -n _m_srcs="$1"
    local -n _m_dests="$2"
    local -n _m_types="$3"
    local -r context="${4:-operation}"

    if [[ ! -f ${DOTFILES_MANIFEST_FILE} ]]; then
        log_warn "No manifest found. Nothing to ${context}."
        _exit 1
        return 1
    fi

    local src dest ftype
    while IFS=$'\t' read -r src dest ftype; do
        src="${src%$'\r'}"
        dest="${dest%$'\r'}"
        ftype="${ftype%$'\r'}"
        [[ -z ${src:-} || -z ${dest:-} ]] && continue
        [[ ${dest} == \#* ]] && continue
        _m_srcs+=("${src}")
        _m_dests+=("${dest}")
        _m_types+=("${ftype}")
    done < "${DOTFILES_MANIFEST_FILE}"

    if [[ ${#_m_dests[@]} -eq 0 ]]; then
        log_info "Manifest is empty. Nothing to ${context}."
        _exit 1
        return 1
    fi

    log_debug "Loaded ${#_m_dests[@]} manifest entries."
    _exit
    return 0
}

do_reset() {
    _enter
    local ec=0
    local -a failed=()
    local removed=0

    log_info "Beginning reset."

    local -a m_srcs=() m_dests=() m_types=()
    _read_manifest_entries m_srcs m_dests m_types "reset" || {
        _exit
        return 0
    }

    local total=${#m_dests[@]}

    # Count affected entries (symlinks + generated only; copies stay)
    local affected=0
    local i
    for ((i = 0; i < total; i++)); do
        case "${m_types[$i]}" in
            symlink | generate) ((++affected)) ;;
        esac
    done

    log_debug "Reset will affect ${affected} of ${total} manifest entries."

    # Single batch prompt
    if ((NOCONFIRM)); then
        log_trace "NOCONFIRM set; skipping reset prompt"
    else
        local reply
        printf '\n  This will remove %d symlink/generated file(s).\n' "${affected}" >&2
        printf '  Copied files will NOT be affected.\n' >&2
        printf '\n  Continue? [Y/n] ' >&2
        read -r reply || reply=""
        log_trace "User prompt reply: '${reply}'"
        case "${reply,,}" in
            y | yes | '')
                log_trace "User confirmed reset"
                ;;
            *)
                log_warn "Reset cancelled by user."
                _exit 130
                return 130
                ;;
        esac
        printf '\n' >&2
    fi

    for ((i = 0; i < total; i++)); do
        case "${m_types[$i]}" in
            symlink | generate)
                if ! remove_file "${m_dests[$i]}"; then
                    ((++ec))
                    failed+=("${m_dests[$i]}")
                else
                    ((++removed))
                fi
                ;;
        esac
    done

    if ((ec > 0)); then
        log_error "Reset finished with ${ec} error(s): ${removed} removed, ${#failed[@]} failed."
        if [[ ${#failed[@]} -gt 0 ]]; then
            printf '\n  Failed to remove:\n' >&2
            local f
            for f in "${failed[@]}"; do
                printf '    ✗ %s\n' "${f}" >&2
            done
            printf '\n' >&2
        fi
    else
        log_info "Reset complete: ${removed} file(s) removed."
    fi

    RESET_ERRORS="${ec}"
    _exit "${ec}"
    return "${ec}"
}

do_repair() {
    _enter
    local ec=0
    local -a failed=()
    local removed=0
    local repaired=0

    log_info "Beginning repair."

    local -a m_srcs=() m_dests=() m_types=()
    _read_manifest_entries m_srcs m_dests m_types "repair" || {
        _exit
        return 0
    }

    local total=${#m_dests[@]}

    local -a broken_idx=()
    local i dest src reason

    for ((i = 0; i < total; i++)); do
        case "${m_types[$i]}" in
            symlink)
                dest="${m_dests[$i]}"
                src="${m_srcs[$i]}"
                if [[ -L ${dest} && -e ${dest} && "$(readlink "${dest}")" == "${src}" ]]; then
                    log_trace "Healthy symlink: ${dest}"
                    continue
                fi
                if   [[ ! -e ${dest} && ! -L ${dest} ]]; then
                                                              reason="missing"
                elif [[ ! -L ${dest} ]]; then
                                                            reason="not a symlink"
                elif [[ ! -e ${dest} ]]; then
                                                            reason="dangling"
                else
                                                             reason="wrong target"
                fi
                log_warn "Broken symlink [${reason}]: ${dest} (expected → ${src})"
                broken_idx+=("${i}")
                ;;

            generate)
                dest="${m_dests[$i]}"
                if [[ -f ${dest} && -s ${dest} ]]; then
                    log_trace "Healthy generated file: ${dest}"
                    continue
                fi
                if [[ -f ${dest} && ! -s ${dest} ]]; then
                                                          reason="empty"
                else
                                                           reason="missing"
                fi
                log_warn "Broken generated file [${reason}]: ${dest}"
                broken_idx+=("${i}")
                ;;
        esac
    done

    local num_broken=${#broken_idx[@]}
    if ((num_broken == 0)); then
        log_info "All entries healthy. Nothing to repair."
        _exit
        return 0
    fi

    log_info "Found ${num_broken} broken entr$( ((num_broken == 1)) && printf 'y' || printf 'ies' ). Removing and re-installing…"

    local idx
    for idx in "${broken_idx[@]}"; do
        if ! remove_file "${m_dests[$idx]}"; then
            ((++ec))
            failed+=("${m_dests[$idx]}")
        else
            ((++removed))
        fi
    done

    for idx in "${broken_idx[@]}"; do
        # skip if removal already failed
        local skip=0
        if [[ ${#failed[@]} -gt 0 ]]; then
            local f
            for f in "${failed[@]}"; do
                [[ ${f} == "${m_dests[$idx]}" ]] && {
                                                      skip=1
                                                              break
                }
            done
        fi
        ((skip)) && continue

        src="${m_srcs[$idx]}"
        dest="${m_dests[$idx]}"
        local ftype="${m_types[$idx]}"
        local label="${src} → ${dest}"

        if ! _prepare_file "${src}" "${dest}"; then
            log_warn "Cannot re-install '${label}': parent directory failed."
            ((++ec))
            failed+=("${dest}")
            continue
        fi

        case "${ftype}" in
            symlink)
                log_debug "[repair:relink] ${label}"
                _attempt_cmd \
                    "ln -sfn \"${src}\" \"${dest}\"" \
                    "Re-linking ${label}" \
                    "Re-link failed: ${label}" \
                    "Re-linked ${label}"
                if (($? == 0)); then
                    manifest_write "${src}" "${dest}" "symlink"
                    ((++repaired))
                    log_debug "✓ ${label}"
                else
                    ((++ec))
                    failed+=("${dest}")
                    log_error "✗ ${label}"
                fi
                ;;

            generate)
                log_debug "[repair:regenerate] ${label}"
                _attempt_cmd \
                    "\"${src}\" \"${dest}\"" \
                    "Regenerating ${label}" \
                    "Regenerate failed: ${label}" \
                    "Regenerated ${label}"
                if (($? == 0)); then
                    manifest_write "${src}" "${dest}" "generate"
                    ((++repaired))
                    log_debug "✓ ${label}"
                else
                    ((++ec))
                    failed+=("${dest}")
                    log_error "✗ ${label}"
                fi
                ;;
        esac
    done

    log_info "Repair complete: ${removed} removed, ${repaired} re-installed, ${ec} error(s)."
    if ((ec > 0)) && [[ ${#failed[@]} -gt 0 ]]; then
        printf '\n  Failed:\n' >&2
        local f
        for f in "${failed[@]}"; do
            printf '    ✗ %s\n' "${f}" >&2
        done
        printf '\n' >&2
    fi

    REPAIR_ERRORS="${ec}"
    _exit "${ec}"
    return "${ec}"
}
