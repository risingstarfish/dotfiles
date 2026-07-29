#!/usr/bin/env bash

# $1 = the first parameter passed to the main script (e.g., --help)
# $2 = the name of the calling script (e.g., install.sh or mode.sh)

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
	printf "Usage: ./%s [debug|profile]\n\n" "$2"
	printf "Options:\n"
	printf "  debug       Enable debug mode\n"
	printf "  profile     Enable profiling mode\n"
	printf "  -h, --help  Show this help message\n"
	
	# Exit with a success code so the rest of the script doesn't run
	exit 0 
fi