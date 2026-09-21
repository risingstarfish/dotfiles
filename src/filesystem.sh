#!/usr/bin/env bash
# filesystem.sh

if [[ -n ${__FILESYSTEM_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __FILESYSTEM_SH_INCLUDED__=1

symlink_all() {
    local -n err_ref="${1}"

}

copy_all() {
    local -n err_ref="${1}"

}

generate_all() {
    local -n err_ref="${1}"

}
