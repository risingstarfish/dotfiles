#!/usr/bin/env bash
# filesystem.sh

if [[ -n ${__FILESYSTEM_SH_INCLUDED__:-} ]]; then
    return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

_prepare_file() {
    _enter

    local source="${1:-}" dest="${2:-}"

    if [[ -z ${source} || -z ${dest} ]]; then
        log_error "requires both source and destination paths."
        _exit 1
        return 1
    fi

    if [[ ! -f ${source} ]]; then
        log_error "source file does not exist: '${source}'"
        _exit 1
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "${dest}")"
    if [[ ! -d ${dest_dir} ]]; then
        log_debug "Creating parent directory: '${dest_dir}'"
        _attempt_cmd \
            "mkdir -p \"${dest_dir}\"" \
            "Creating parent directory for ${dest}" \
            "Cannot create target directory '${dest_dir}'" \
            "Created directory '${dest_dir}'" || {
                _exit 1
                return 1
        }
    fi

    _exit
}

_wanted_module() {
    _enter

    local src="$1" module m
    module="${src%%/*}"
    for m in "${USER_MODULES[@]}"; do
        if [[ ${module} == ${m} ]]; then
            log_trace "Module match: '${module}'"
            _exit 0
            return 0
        fi
    done

    log_trace "No module match for '${module}'"
    _exit 1
    return 1
}

# Backs up a pre-existing dest into:
#   ${DOTFILES_BACKUP_DIR}/${DOTFILES_START_TIME}/<basename>.bak
#
# Flag behaviour:
#   DRY_RUN=1   – log the intended backup, skip the mv
#   FORCE=1     – skip backup entirely, remove dest so the new file lands cleanly
#   NOCONFIRM=1 – skip the interactive prompt before backing up
#
# Collision detection: if <basename>.bak already exists, appends
#   .1.bak, .2.bak, …
#
# Returns 1 only if the mv (or rm, for FORCE) itself fails.
_guard_dest() {
    _enter

    local dest="$1" src="$2"

    if [[ ! -e ${dest} && ! -L ${dest} ]]; then
        log_trace "No existing file at '${dest}'. Nothing to guard."
        _exit
        return 0
    fi

    if [[ -L ${dest} ]]; then
        local target
        target="$(readlink "${dest}")"
        if [[ ${target} == ${src}* ]]; then
            log_debug "'${dest}' is already a symlink into our repo (${target}). Skipping backup."
            _exit
            return 0
        fi
        log_debug "'${dest}' is a symlink pointing to '${target}' (not our repo). Will back up."
    fi

    if ((FORCE)); then
        log_warn "FORCE set. Removing '${dest}' without backup."
        if ((DRY_RUN)); then
            log_info "[dry-run] Would remove: ${dest}"
            _exit
            return 0
        fi
        rm -f "${dest}" || {
            log_error "Failed to remove '${dest}' (FORCE)"
            _exit 1
            return 1
        }
        _exit
        return 0
    fi

    if ((DRY_RUN)); then
        local dry_base
        dry_base="$(basename "${dest}")"
        log_info "[dry-run] Would back up: ${dest} → ${DOTFILES_BACKUP_DIR}/${DOTFILES_START_TIME}/${dry_base}.bak"
        _exit
        return 0
    fi

    if ! ((NOCONFIRM)); then
        local reply
        printf '\n  Existing file found: %s\n' "${dest}" >&2
        printf '  Back up and replace? [Y/n] ' >&2
        read -r reply || {
            log_warn "No input available for backup prompt. Skipping."
            _exit 1
            return 1
        }
        case "${reply,,}" in
            y | yes | '')
                log_debug "User confirmed backup."
                ;;
            *)
                log_warn "User declined backup. Skipping '${dest}'."
                _exit 1
                return 1
                ;;
        esac
        printf '\n' >&2
    fi

    local backup_dir="${DOTFILES_BACKUP_DIR}/${DOTFILES_START_TIME}"
    local base="$(basename "${dest}")"
    local backup_path="${backup_dir}/${base}.bak"

    local n=1
    while [[ -e ${backup_path} ]]; do
        backup_path="${backup_dir}/${base}.${n}.bak"
        log_debug "Collision at '${base}.bak'. Trying index ${n}."
        ((++n))
    done

    log_debug "Resolved backup path: '${backup_path}'"

    if ! mkdir -p "${backup_dir}"; then
        log_error "Cannot create backup dir '${backup_dir}'"
        _exit 1
        return 1
    fi

    log_warn "Backing up ${dest} → ${backup_path}"
    if ! mv "${dest}" "${backup_path}"; then
        log_error "Failed to back up '${dest}'"
        _exit 1
        return 1
    fi

    log_debug "Backup complete."
    _exit
    return 0
}

install_all() {
    _enter
    local action src dest cmd full_src label
    local installed=0 skipped=0 failed=0

    log_info "Installing ${#DOTFILES_MANIFEST[@]} manifest entries (stamp: ${DOTFILES_START_TIME})"
    log_debug "Flags -> DRY_RUN=${DRY_RUN}, FORCE=${FORCE}, NOCONFIRM=${NOCONFIRM}, NO_BACKUP=${NO_BACKUP}"

    for entry in "${DOTFILES_MANIFEST[@]}"; do
        if [[ -z ${entry} || ${entry} == \#* ]]; then
            continue
        fi

        IFS='|' read -r action src dest cmd <<< "${entry}"
        log_trace "Entry: action='${action}' src='${src}' dest='${dest}' cmd='${cmd:-}'"

        if ! _wanted_module "${src}"; then
            log_debug "Skip (module not selected): '${src}'"
            ((++skipped))
            continue
        fi

        full_src="${SRC_PATH}/${src}"
        label="${src} → ${dest}"
        log_trace "Resolved full_src='${full_src}'"

        if ! _prepare_file "${full_src}" "${dest}"; then
            log_error "Pre-flight failed: '${label}'"
            ((++failed))
            continue
        fi

        if ! _guard_dest "${dest}" "${full_src}"; then
            ((++failed))
            continue
        fi

        local ok=0
        case "${action}" in
            symlink)
                log_debug "[symlink] ${label}"
                _attempt_cmd \
                    "ln -sfn \"${full_src}\" \"${dest}\"" \
                    "Symlinking ${label}" \
                    "Symlink failed: ${label}" \
                    "Symlinked ${label}"
                ok=$?
                ;;
            copy)
                log_debug "[copy] ${label}"
                _attempt_cmd \
                    "cp -f \"${full_src}\" \"${dest}\"" \
                    "Copying ${label}" \
                    "Copy failed: ${label}" \
                    "Copied ${label}"
                ok=$?
                ;;
            generate)
                if [[ -f ${dest} && -s ${dest} ]]; then
                    log_debug "[generate] '${dest}' already exists. Skipping."
                    ((++installed))
                    continue
                fi
                log_debug "[generate] ${label}"
                _attempt_cmd \
                    "python3 \"${full_src}\" \"${dest}\"" \
                    "Generating ${label}" \
                    "Generate failed: ${label}" \
                    "Generated ${label}"
                ok=$?
                ;;
            *)
                log_error "Unknown action '${action}' for '${src}'"
                ((++failed))
                continue
                ;;
        esac
        log_trace "Action '${action}' for '${label}' → ok=${ok}"

        if ((ok == 0)) && [[ -n ${cmd} ]]; then
            log_debug "Post-install: '${cmd}'"
            _attempt_cmd "${cmd}" \
                "Post-install for ${label}" \
                "Post-install failed: ${label}" \
                "Post-install done: ${label}"
            ok=$?
            log_trace "Post-install → ok=${ok}"
        fi

        if ((ok == 0)); then
            ((++installed))
            log_debug "✓ ${label}"
        else
            ((++failed))
            log_error "✗ ${label}"
        fi
    done

    log_info "Done: ${installed} installed, ${skipped} skipped, ${failed} failed."
    _exit
}
