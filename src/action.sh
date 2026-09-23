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
        log_info "[dry-run] mv ${dest} ${DOTFILES_BACKUP_DIR}/${DOTFILES_START_TIME}/${dry_base}.bak"
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

    local affected=0
    local i
    for ((i = 0; i < total; i++)); do
        case "${m_types[$i]}" in
            symlink | generate) ((++affected)) ;;
        esac
    done

    log_debug "Reset will affect ${affected} of ${total} manifest entries."

    if ((INTERACTIVE)); then
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

do_remove() {
    _enter
    local ec=0
    local -a failed=()
    local removed=0

    log_info "Beginning remove."

    local -a target_modules=()
    local mod entry

    for entry in "${REMOVE_SET[@]}"; do
        for mod in "${AVAILABLE_MODULES[@]}"; do
            if [[ ${mod} == "${entry}" || ${mod} == "${entry}/"* ]]; then
                target_modules+=("${mod}")
            fi
        done
    done

    if [[ ${#target_modules[@]} -eq 0 ]]; then
        log_warn "No modules matched REMOVE_SET. Nothing to remove."
        _exit
        return 0
    fi

    local -a to_remove=()
    local action dest

    for mod in "${target_modules[@]}"; do
        action="${MODULE_ACTION["${mod}"]:-}"
        case "${action}" in
            symlink | generate)
                to_remove+=("${mod}")
                ;;
            copy)
                log_trace "Skipping copy module '${mod}' (copies are preserved)."
                ;;
        esac
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log_info "All matched modules are copies. Nothing to remove."
        _exit
        return 0
    fi

    if ((INTERACTIVE)); then
        local reply
        printf '\n  This will remove %d file(s):\n' "${#to_remove[@]}" >&2
        for mod in "${to_remove[@]}"; do
            dest="${MODULE_DEST["${mod}"]:-}"
            printf '    - %s\n' "${dest}" >&2
        done
        printf '\n  Continue? [Y/n] ' >&2
        read -r reply || reply=""
        log_trace "User prompt reply: '${reply}'"
        case "${reply,,}" in
            y | yes | '')
                log_trace "User confirmed remove"
                ;;
            *)
                log_warn "Remove cancelled by user."
                _exit 130
                return 130
                ;;
        esac
        printf '\n' >&2
    fi

    for mod in "${to_remove[@]}"; do
        dest="${MODULE_DEST["${mod}"]:-}"
        log_trace "Removing: '${mod}' → '${dest}'"
        if ! remove_file "${dest}"; then
            ((++ec))
            failed+=("${dest}")
        else
            ((++removed))
        fi
    done

    if ((ec > 0)); then
        log_error "Remove finished with ${ec} error(s): ${removed} removed, ${#failed[@]} failed."
        if [[ ${#failed[@]} -gt 0 ]]; then
            printf '\n  Failed to remove:\n' >&2
            local f
            for f in "${failed[@]}"; do
                printf '    ✗ %s\n' "${f}" >&2
            done
            printf '\n' >&2
        fi
    else
        log_info "Remove complete: ${removed} file(s) removed."
    fi

    REMOVE_ERRORS="${ec}"
    _exit "${ec}"
    return "${ec}"
}
