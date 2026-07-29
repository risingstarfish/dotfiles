#!/usr/bin/env bash

# $1 = the first parameter passed to the main script (e.g., --help)
# $2 = the name of the calling script (e.g., install.sh or mode.sh)

for arg in "$@"; do
	if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
		printf "Usage: ./%s [debug|profile]\n\n" "$2"
		printf "Options:\n"
		printf "  -d, --enable-debug       Enable debug mode\n"
		printf "  -p, --enable-profiling   Enable profiling mode\n"
		printf "  -h, --help  			   Show this help message\n"

		exit 0
	fi
done
