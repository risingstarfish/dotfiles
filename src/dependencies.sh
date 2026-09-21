#!/usr/bin/env bash
# deps.sh

if [[ -n ${__DEPENDENCIES_SH_INCLUDED__:-}     ]]; then
    return 0
fi
readonly __DEPENDENCIES_SH_INCLUDED__=1

# TODO: git eza claude  clang-format/clang-tidy cmake python cmake-format
#       fastfetch ssh tmux topgrade wget zsh shellcheck clang gcc
