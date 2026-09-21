#!/usr/bin/env bash
# action.sh

if [[ -n ${__ACTION_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __ACTION_SH_INCLUDED__=1

do_update() {
    if [[ ! -d "${SRC_PATH}/.git" ]]; then
        die 1 '%s is not a git clone. Run with --install first.' "${SRC_PATH}"
    fi

    local has_local_mods=0
    if ! command git -C "${SRC_PATH}" diff --quiet HEAD 2> /dev/null; then
        has_local_mods=1
    fi

    log_info "Updating dotfiles in ${SRC_PATH} (ref: ${DOTFILES_REF})"

    if [[ has_local_mods -eq 1 && "${DOTFILES_LOCAL_MODS}" -eq 0 ]]; then
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
        command git -C "${SRC_PATH}" diff --stat HEAD 2> /dev/null >&2
        return 1
    fi

    if ! command git -C "${SRC_PATH}" fetch origin --depth=1 "${DOTFILES_REF}" 2> /dev/null; then
        log_error "Fetch failed (ref: ${DOTFILES_REF}). Check network or repo URL."
        return 1
    fi

    if [[ has_local_mods -eq 1 && "${DOTFILES_LOCAL_MODS}" -eq 1 ]]; then
        log_warn "Local modifications present. Rebasing onto FETCH_HEAD."
        if ! command git -C "${SRC_PATH}" rebase FETCH_HEAD 2> /dev/null; then
            log_error "Rebase failed."
            printf '\n' >&2
            printf '  Resolve conflicts, then:\n' >&2
            printf '    git -C "%s" rebase --continue\n' "${SRC_PATH}" >&2
            printf '  Or abort with:\n' >&2
            printf '    git -C "%s" rebase --abort\n' "${SRC_PATH}" >&2
            return 1
        fi
    else
        if [[ has_local_mods -eq 1 ]]; then
            if ((NOCONFIRM)); then
                :
            else
                log_info "About to run: git reset --hard FETCH_HEAD"
                printf '\n' >&2
                printf '  This discards ALL local changes in %s.\n' "${SRC_PATH}" >&2
                printf '  Continue? [Y/n] ' >&2
                local reply
                read -r reply
                case "${reply,,}" in
                    y | yes | '')
                        :
                        ;;
                    *)
                        log_warn "Reset cancelled by user."
                        return 1
                        ;;
                esac
                printf '\n' >&2
            fi

            if ! command git -C "${SRC_PATH}" reset --hard FETCH_HEAD 2> /dev/null; then
                log_error "Reset to ${DOTFILES_REF} failed in ${SRC_PATH}."
                return 1
            fi
        fi
        if command git -C "${SRC_PATH}" show-ref --verify --quiet "refs/heads/${DOTFILES_REF}" 2> /dev/null; then
            command git -C "${SRC_PATH}" branch -f "${DOTFILES_REF}" FETCH_HEAD 2> /dev/null || true
        fi
    fi

    return 0
}
