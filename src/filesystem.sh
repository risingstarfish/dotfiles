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
            _exit     1
            return     1
        }
    fi

    _exit
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

# ─────────────────────────────────────────────────────────────
# State-manifest helpers
# File: ${DOTFILES_MANIFEST_FILE}  (TAB-delimited: source  dest  type)
# Purpose: record what is currently installed so that
#          --remove / --uninstall / --repair can find targets,
#          and re-runs are idempotent.
# ─────────────────────────────────────────────────────────────

# Append (or update) a single entry.
# Idempotent: if the dest is already recorded, the row is
# replaced in-place (preserves file order for the first N entries).
#
# $1 = full source path   (e.g. /c/Users/tiger/dotfiles/modules/zsh/zshrc)
# $2 = full dest path     (e.g. /c/Users/tiger/.zshrc)
# $3 = type               (symlink | copy | generate)
manifest_write() {
    local source="$1" dest="$2" ftype="$3"

    local manifest_dir
    manifest_dir="$(dirname "${DOTFILES_MANIFEST_FILE}")"
    if [[ ! -d ${manifest_dir} ]]; then
        mkdir -p "${manifest_dir}" 2> /dev/null || {
            log_error "Cannot create manifest directory '${manifest_dir}'"
            return 1
        }
    fi

    # Check if dest already exists in the file
    if [[ -f ${DOTFILES_MANIFEST_FILE} ]] \
        && awk -F'\t' -v d="${dest}" '$2 == d { found=1; exit } END { exit found ? 0 : 1 }' "${DOTFILES_MANIFEST_FILE}"; then
        # Replace in-place (handles re-install with a different source or type)
        local tmp
        tmp="$(mktemp)"
        awk -F'\t' -v OFS='\t' -v d="${dest}" \
            -v s="${source}" -v t="${ftype}" \
            '$2 != d { print; next } { print s, d, t }' \
            "${DOTFILES_MANIFEST_FILE}" > "${tmp}" && mv "${tmp}" "${DOTFILES_MANIFEST_FILE}"
        log_trace "Manifest: updated '${dest}' → ${ftype}"
    else
        printf '%s\t%s\t%s\n' "${source}" "${dest}" "${ftype}" >> "${DOTFILES_MANIFEST_FILE}"
        log_trace "Manifest: added '${dest}' → ${ftype}"
    fi
}

# Remove an entry by dest path.
# $1 = dest path to remove
manifest_remove() {
    local dest="$1"
    [[ -f ${DOTFILES_MANIFEST_FILE} ]] || return 0

    local tmp
    tmp="$(mktemp)"
    awk -F'\t' -v d="${dest}" '$2 != d' "${DOTFILES_MANIFEST_FILE}" > "${tmp}" && mv "${tmp}" "${DOTFILES_MANIFEST_FILE}"
    log_trace "Manifest: removed entry for '${dest}'"
}

# Remove ALL entries whose source is under a given prefix
# (useful for --remove MODULE where you want to nuke everything under modules/<module>/)
# $1 = source path prefix (e.g. /c/Users/tiger/dotfiles/modules/zsh/)
manifest_remove_prefix() {
    local prefix="$1"
    [[ -f ${DOTFILES_MANIFEST_FILE} ]] || return 0

    local tmp
    tmp="$(mktemp)"
    awk -F'\t' -v p="${prefix}" 'index($1, p) != 1' "${DOTFILES_MANIFEST_FILE}" > "${tmp}" && mv "${tmp}" "${DOTFILES_MANIFEST_FILE}"
    log_trace "Manifest: removed all entries with source prefix '${prefix}'"
}

# Wipe the entire manifest (for --uninstall).
manifest_clear() {
    if [[ -f ${DOTFILES_MANIFEST_FILE} ]]; then
        : > "${DOTFILES_MANIFEST_FILE}"
        log_trace "Manifest: cleared (${DOTFILES_MANIFEST_FILE} removed)"
    fi
}

# Read the manifest into a caller-supplied associative array keyed by dest.
# Value is the source path.  Also populates two parallel arrays if you need type.
#
# Usage:
#   local -A installed_src   # dest → source
#   local -a installed_types  # parallel: type per entry (same order as iteration)
#   manifest_read installed_src
#
# Returns 0 even if file doesn't exist (nothing installed yet).
manifest_read() {
    local -n _map="$1"
    [[ -f ${DOTFILES_MANIFEST_FILE} ]] || return 0

    local src dest ftype
    while IFS=$'\t' read -r src dest ftype; do
        dest="${dest%$'\r'}"   # ← strip CR (Git Bash CRLF)
        src="${src%$'\r'}"
        [[ -z ${src:-} || -z ${dest:-} ]] && continue
        [[ ${dest} == \#* ]] && continue
        _map["${dest}"]="${src}"
    done < "${DOTFILES_MANIFEST_FILE}"

    log_debug "Manifest: loaded ${#_map[@]} installed entries."
}

install_all() {
    _enter
    local action src dest cmd full_src label
    local installed=0 skipped=0 failed=0

    log_info "Installing ${#USER_MODULES[@]} manifest entries (stamp: ${DOTFILES_START_TIME})"
    log_debug "Flags -> DRY_RUN=${DRY_RUN}, FORCE=${FORCE}, NOCONFIRM=${NOCONFIRM}, NO_BACKUP=${NO_BACKUP}"

    for src in "${USER_MODULES[@]}"; do
        log_trace "Processing: '${src}'"

        local action="${MODULE_ACTION["${src}"]:-}"
        local dest="${MODULE_DEST["${src}"]:-}"
        local cmd="${MODULE_CMD["${src}"]:-}"

        if [[ -z ${action} || -z ${dest} ]]; then
            log_warn "No manifest data for module '${src}'. Skipping."
            ((++skipped))
            continue
        fi

        full_src="${MODULE_DIR}/${src}"
        label="${src} → ${dest}"

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
                    manifest_write "${full_src}" "${dest}" "generate"
                    continue
                fi
                log_debug "[generate] ${label}"
                _attempt_cmd \
                    "\"${full_src}\" \"${dest}\"" \
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

        if ((ok == 0)) && [[ -n ${cmd} ]]; then
            log_debug "Post-install: '${cmd}'"
            _attempt_cmd "${cmd}" \
                "Post-install for ${label}" \
                "Post-install failed: ${label}" \
                "Post-install done: ${label}"
            ok=$?
        fi

        if ((ok == 0)); then
            ((++installed))
            manifest_write "${full_src}" "${dest}" "${action}"
            log_debug "✓ ${label}"
        else
            ((++failed))
            log_error "✗ ${label}"
        fi
    done

    log_info "Done: ${installed} installed, ${skipped} skipped, ${failed} failed."
    _exit
}
