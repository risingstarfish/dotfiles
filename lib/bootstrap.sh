#!/usr/bin/env bash

if [[ -n "${__BOOTSTRAP_SH_INCLUDED__:-}" ]]; then
	return 0
fi
readonly __BOOTSTRAP_SH_INCLUDED__=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly _LIB_DIR

source_deps() {
	local -r -a required_libs=("$@")
	local -a missing_deps=()
	local lib

	for lib in "${required_libs[@]}"; do
		if [[ ! -f "${_LIB_DIR}/${lib}" ]]; then
			missing_deps+=("${lib}")
		fi
	done

	if ((${#missing_deps[@]} > 0)); then
		printf "\e[31m[ERROR]\e[0m Missing files: %d\n" "${#missing_deps[@]}" >&2
		for missing in "${missing_deps[@]}"; do
			printf "  >> %s\n" "$missing" >&2
		done
		return 1
	fi

	for lib in "${required_libs[@]}"; do
		source "${_LIB_DIR}/${lib}"
	done
}
