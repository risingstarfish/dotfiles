#!/usr/bin/env bash
# action.sh

if [[ -n ${__ACTION_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __ACTION_SH_INCLUDED__=1

set_user_modules() {
    log_trace "${FUNCNAME[0]}: Entering (USER_MODULES count: ${#USER_MODULES[@]})"

    if [[ -n ${USER_MODULES:-}  ]]; then
        log_debug "${FUNCNAME[0]}: USER_MODULES is already populated. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (already populated)"
        return 0
    fi

    local num_inc=${#INCLUDE_SET[@]}
    local num_exc=${#EXCLUDE_SET[@]}
    local num_total=${#AVAILABLE_MODULES[@]}
    local num_target

    log_trace "${FUNCNAME[0]}: Set counts -> num_inc=${num_inc}, num_exc=${num_exc}, num_total=${num_total}"

    if ((num_inc > 0)); then
        num_target=${num_inc}
    elif ((num_exc > 0)); then
        num_target=$((num_total > num_exc ? num_total - num_exc : 0))
    else
        num_target=${num_total}
    fi

    log_debug "${FUNCNAME[0]}: Processing ${num_target}/${num_total} modules."

    local mod inc exc included excluded
    local mod_slash

    for mod in "${AVAILABLE_MODULES[@]}"; do
        mod_slash="${mod}/"
        log_trace "${FUNCNAME[0]}: Evaluating module '${mod}' (mod_slash='${mod_slash}')"

        if ((num_inc > 0)); then
            included=0
            for inc in "${INCLUDE_SET[@]}"; do
                log_trace "${FUNCNAME[0]}: Testing include filter '${inc}/'* against '${mod_slash}'"
                if [[ ${mod_slash} == "${inc}/"*     ]]; then
                    included=1
                    log_trace "${FUNCNAME[0]}: Match found for include filter '${inc}'"
                    break
                fi
            done
            if ! ((included)); then
                log_debug "${FUNCNAME[0]}: Skipped '${mod}' (not in INCLUDE_SET)"
                log_trace "${FUNCNAME[0]}: Module '${mod}' skipped because it did not match INCLUDE_SET"
                continue
            fi
        fi

        if ((num_exc > 0)); then
            excluded=0
            for exc in "${EXCLUDE_SET[@]}"; do
                log_trace "${FUNCNAME[0]}: Testing exclude filter '${exc}/'* against '${mod_slash}'"
                if [[ ${mod_slash} == "${exc}/"* ]]; then
                    excluded=1
                    log_trace "${FUNCNAME[0]}: Match found for exclude filter '${exc}'"
                    break
                fi
            done
            if ((excluded)); then
                log_debug "${FUNCNAME[0]}: Skipped '${mod}' (matched EXCLUDE_SET)"
                log_trace "${FUNCNAME[0]}: Module '${mod}' skipped because it matched EXCLUDE_SET"
                continue
            fi
        fi
        log_debug "${FUNCNAME[0]}: Added '${mod}'"
        log_trace "${FUNCNAME[0]}: Appending '${mod}' to USER_MODULES"
        USER_MODULES+=("${mod}")
    done

    log_info "${FUNCNAME[0]}: Selected ${#USER_MODULES[@]} total modules for processing."
    log_trace "${FUNCNAME[0]}: Setting USER_MODULES as readonly and exiting successfully"
    readonly USER_MODULES
}

set_file_types() {
    log_trace "${FUNCNAME[0]}: Entering (SYMLINK_FILES=${#SYMLINK_FILES[@]}, COPY_FILES=${#COPY_FILES[@]}, GENERATE_FILES=${#GENERATE_FILES[@]})"

    if [[ -n ${SYMLINK_FILES:-} || -n ${COPY_FILES:-} || -n ${GENERATE_FILES:-} ]]; then
        log_debug "${FUNCNAME[0]}: SYMLINK_FILES, COPY_FILES, and GENERATE_FILES are already populated. Skipping categorisation."
        log_trace "${FUNCNAME[0]}: Exiting (already populated)"
        return 0
    fi

    log_debug "${FUNCNAME[0]}: Categorising ${#USER_MODULES[@]} files..."

    local file
    local base
    for file in "${USER_MODULES[@]}"; do
        base="${file##*/}"
        if [[ ${base} == *.local || ${base} == *.local.* ]]; then
            log_debug "${FUNCNAME[0]}: [COPY] ${base}"
            log_trace "${FUNCNAME[0]}: Matched COPY pattern (*.local / *.local.*) -> adding to COPY_FILES"
            COPY_FILES+=("${file}")
        elif [[ ${base} == *.gen ]]; then
            log_debug "${FUNCNAME[0]}: [GENERATE] ${base}"
            log_trace "${FUNCNAME[0]}: Matched GENERATE pattern (*.gen) -> adding to GENERATE_FILES"
            GENERATE_FILES+=("${file}")
        else
            log_debug "${FUNCNAME[0]}: [SYMLINK] ${base}"
            log_trace "${FUNCNAME[0]}: Default match -> adding to SYMLINK_FILES"
            SYMLINK_FILES+=("${file}")
        fi
    done

    log_info "${FUNCNAME[0]}: Categorised ${#SYMLINK_FILES[@]} symlinks, ${#COPY_FILES[@]} copies, \
${#GENERATE_FILES[@]} generated."
    log_trace "${FUNCNAME[0]}: Marking file type arrays as readonly and exiting successfully"
    readonly SYMLINK_FILES COPY_FILES GENERATE_FILES
}

set_dotfiles_ref() {
    log_trace "${FUNCNAME[0]}: Entering (DOTFILES_REF='${DOTFILES_REF:-}', SRC_PATH='${SRC_PATH:-}')"

    if [[ -n ${DOTFILES_REF:-} ]]; then
        log_debug "${FUNCNAME[0]}: DOTFILES_REF already set to '${DOTFILES_REF}'. Skipping."
        log_trace "${FUNCNAME[0]}: Exiting (DOTFILES_REF already set)"
        return 0
    fi

    log_debug "${FUNCNAME[0]}: Determining git ref for '${SRC_PATH}'..."

    log_trace "${FUNCNAME[0]}: Executing: git -C '${SRC_PATH}' rev-parse --git-dir"
    if ! git -C "${SRC_PATH}" rev-parse --git-dir > /dev/null 2>&1; then
        log_trace "${FUNCNAME[0]}: git rev-parse failed (not a git repository)"
        log_error "${FUNCNAME[0]}: Unable to determine git ref. Make sure '${SRC_PATH}' is a git repo."
        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    local config_ref
    log_trace "${FUNCNAME[0]}: Executing: git -C '${SRC_PATH}' config --local dotfiles.ref"
    config_ref="$(git -C "${SRC_PATH}" config --local dotfiles.ref 2> /dev/null || true)"
    log_trace "${FUNCNAME[0]}: Retrieved config_ref='${config_ref}'"

    if [[ -n ${config_ref} ]]; then
        DOTFILES_REF="${config_ref}"
        log_debug "${FUNCNAME[0]}: Found custom ref in git config."
        log_trace "${FUNCNAME[0]}: Assigned DOTFILES_REF='${DOTFILES_REF}' from git config"
    else
        DOTFILES_REF="main"
        log_debug "${FUNCNAME[0]}: No custom git config found. Falling back to default."
        log_trace "${FUNCNAME[0]}: Assigned DOTFILES_REF='main' (default fallback)"
    fi

    log_trace "${FUNCNAME[0]}: Marking DOTFILES_REF as readonly and exiting successfully"
    readonly DOTFILES_REF
}

do_install() {
    log_trace "${FUNCNAME[0]}: Entering"

    local USER_MODULES=()
    local SYMLINK_FILES=()
    local COPY_FILES=()
    local GENERATE_FILES=()

    log_info "Beginning installation!"

    log_trace "${FUNCNAME[0]}: Calling set_user_modules()"
    set_user_modules # USER_MODULES
    log_trace "${FUNCNAME[0]}: Returned from set_user_modules() (USER_MODULES count: ${#USER_MODULES[@]})"

    log_trace "${FUNCNAME[0]}: Calling set_file_types()"
    set_file_types   # SYMLINK_FILES COPY_FILES GENERATE_FILES
    log_trace "${FUNCNAME[0]}: Returned from set_file_types() (SYMLINK: ${#SYMLINK_FILES[@]}, COPY: ${#COPY_FILES[@]}, GENERATE: ${#GENERATE_FILES[@]})"

    log_debug "${FUNCNAME[0]}: Initialized local module and file arrays"

    local rc=0
    local num_err=0
    log_trace "${FUNCNAME[0]}: Initialized status tracer rc=${rc}"

    symlink_all "${num_err}" || rc=1
    copy_all "${num_err}" || rc=1
    generate_all "${num_err}" || rc=1

    log_trace "${FUNCNAME[0]}: Evaluating final status code rc=${rc}"
    if ((rc)); then
        log_trace "${FUNCNAME[0]}: Error state detected (rc != 0)"
        log_error 'Install finished with errors!' # TODO: print total number
        log_trace "${FUNCNAME[0]}: Exiting with status 1"
        return 1
    fi

    log_info 'Installation complete!'
    log_trace "${FUNCNAME[0]}: Exiting successfully with status 0"
}

do_update() {
    local DOTFILES_REF

    log_trace "Entering ${FUNCNAME[0]}() [SRC_PATH='${SRC_PATH}', DOTFILES_LOCAL_MODS='${DOTFILES_LOCAL_MODS}', NOCONFIRM='${NOCONFIRM}']"

    set_dotfiles_ref || { # DOTFILES_REF
        log_trace "set_dotfiles_ref failed with exit status $?, exiting ${FUNCNAME[0]}()"
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

    if [[ has_local_mods -eq 1 && ${DOTFILES_LOCAL_MODS} -eq 0   ]]; then
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
        log_trace "Exiting ${FUNCNAME[0]}() with status 1 (blocked)"
        return 1
    fi

    log_trace "Executing: git -C '${SRC_PATH}' fetch origin --depth=1 '${DOTFILES_REF}'"
    if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "${DOTFILES_REF}" 2> /dev/null; then
        log_trace "git fetch command failed"
        log_error "Fetch failed (ref: ${DOTFILES_REF}). Check network or repo URL."
        log_trace "Exiting ${FUNCNAME[0]}() with status 1 (fetch failed)"
        return 1
    fi

    if [[ ${has_local_mods} -eq 1 && ${DOTFILES_LOCAL_MODS} -eq 1 ]]; then
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
            log_trace "Exiting ${FUNCNAME[0]}() with status 1 (rebase failed)"
            return 1
        fi
    else
        if [[ ${has_local_mods} -eq 1 ]]; then
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

    log_trace "Exiting ${FUNCNAME[0]}() successfully with status 0"
    return 0
}
