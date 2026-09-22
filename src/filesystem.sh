#!/usr/bin/env bash
# filesystem.sh

if [[ -n ${__FILESYSTEM_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

_prepare_file() {
    _enter

    local -r source="${1:-}"
    local -r dest="${2:-}"
    local -r caller="${FUNCNAME[1]}"

    if [[ -z ${source} || -z ${dest}     ]]; then
        log_error "${caller}: requires both source and destination paths."
        return 1
    fi

    if [[ ! -f ${source}   ]]; then
        log_error "${caller_name}: source file does not exist: '${source}'"
        return 1
    fi

    local dest_dir
    dest_dir="$(dirname "${dest}")"
    if [[ ! -d ${dest_dir}   ]]; then
        log_debug "${caller}: Destination directory does not exist."
        local -r cmd='mkdir -p %s' "${dest_dir}"

        _attempt_cmd \
            "mkdir -p \"${dest_dir}\"" \
            "This will recursively create missing directories if they do not exist." \
            "Cannot create target directory '${dest_dir}'" \
            "Created directory '${dest_dir}'" || return 1
    fi

    _exit
}

symlink_all() {
    _enter

    log_info "Symlinking ${#SYMLINK_FILES[@]} files..."
    for file in "${SYMLINK_FILES[@]}"; do
        :
    done

    _exit
}

copy_all() {
    _enter

    log_info "Copying ${#COPY_FILES[@]} files..."

    _exit

}

generate_all() {
    _enter
    log_info "Generating ${#GENERATE_FILES[@]} files..."

    _exit
}
