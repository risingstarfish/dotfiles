#!/usr/bin/env zsh

# settings
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE="1000000"
export SAVEHIST="1000000"

setopt EXTENDED_HISTORY       # Write the history file in the ':start:elapsed;command' format.
setopt INC_APPEND_HISTORY     # Write to the history file immediately, not when the shell exits.
setopt SHARE_HISTORY          # Share history between all sessions.
setopt HIST_EXPIRE_DUPS_FIRST # Expire a duplicate event first when trimming history.
setopt HIST_IGNORE_DUPS       # Do not record an event that was just recorded again.
setopt HIST_IGNORE_ALL_DUPS   # Delete an old recorded event if a new event is a duplicate.
setopt HIST_FIND_NO_DUPS      # Do not display a previously found event.
setopt HIST_IGNORE_SPACE      # Do not record an event starting with a space.
setopt HIST_SAVE_NO_DUPS      # Do not write a duplicate event to the history file.
setopt HIST_VERIFY            # Do not execute immediately upon history expansion.
setopt APPEND_HISTORY         # append to history file
setopt HIST_NO_STORE          # Don't store history commands

# Enable zsh profiling for performance analysis
# This section needs to be at the top of the file
# to ensure profiling starts before any other commands are executed.
if [[ "$ENABLE_PROFILING" == true ]]; then
	zmodload zsh/zprof

	DATE_FORMAT="%Y-%m-%d_%H.%M.%S" # Date format for profiling logs
	DATE="$(date +$DATE_FORMAT)"    # Current date and time in the specified format
	NUM_PROFILE_TO_KEEP=10          # Number of profile files to keep
else
	ENABLE_PROFILING=false
fi

# These functions are used to print headers and log messages
# throughout the script.
# They help in organizing the output and making it more readable.
# Print a title header
print_title() {
	local title="$1"
	printf "\n\e[38;5;196m\t===== %s =====\e[0m\n\n" "$title" # Red title header
}

# Print a header between sections
print_header() {
	local header="$1"
	if [[ "$DEBUG_MODE" == true ]]; then
		printf "\n\e[38;5;12m=== %s ===\e[0m\n\n" "$header" # Blue header
	fi
}

# --- Centralized Logging Function ---
# log_message - Function to print colored log messages
# Usage: log_message <TYPE> "Your message here"
# <TYPE> can be ERROR, WARNING, SUCCESS, INFO, or any custom type
log_message() {
	local log_type="${1:-INFO}"
	local message="${2:-}"

	# Guard against empty messages
	[[ -z "$message" ]] && return 0

	# Zsh associative array for colors
	local -A colors=(
		[SUCCESS]="\e[38;5;10m" # Green
		[ERROR]="\e[38;5;9m"    # Red
		[WARNING]="\e[38;5;3m"  # Yellow/Orange
		[INFO]="\e[38;5;14m"    # Cyan
		[PROFILE]="\e[38;5;13m" # Magenta
	)
	local reset="\e[0m"

	case "$log_type" in
	ERROR | WARNING | PROFILE)
		# Always print
		;;
	SUCCESS | INFO)
		# Only print if DEBUG_MODE is explicitly "true"
		[[ "${DEBUG_MODE:-}" == "true" ]] || return 0
		;;
	*)
		# Unknown type defaults to WARNING
		log_type="WARNING"
		;;
	esac

	local color_code="${colors[$log_type]}"
	local prefix="[${log_type}]"

	printf '%b %s\n' "${color_code}${prefix}${reset}" "$message"
}

print_header "Local zshrc"
LOCAL_ZSH="$HOME/.zshrc.local"
if [[ -f "$LOCAL_ZSH" ]]; then
	source "$LOCAL_ZSH"

	if [[ "$DEBUG_MODE" == true ]]; then
		print_title "START DEBUG MODE"
	else
		DEBUG_MODE=false
	fi

	log_message SUCCESS "Found $LOCAL_ZSH"
else
	printf "Something went wrong!\n"
	printf "No %s file detected.\n" "$LOCAL_ZSH"
	printf "Make sure to run \033[36m'bash install.sh'\033[0m\n"
	# https://unix.stackexchange.com/questions/579104/start-interactive-zsh-without-running-any-configuration-files-like-zshrc
	zsh -d -f -i
	exit 0
fi

# NOTE: keep here
print_header "Exports"
if [[ -f "$HOME/.exports" ]]; then
	source "$HOME/.exports"
	log_message SUCCESS "Sourced $HOME/.exports"
else
	log_message ERROR "Unable to find $HOME/.exports.\nSome functionality may not work properly."
fi

print_header "Default paths"
if [[ -f "$HOME/.paths" ]]; then
	source "$HOME/.paths"
	log_message SUCCESS "Sourced $HOME/.paths"
else
	log_message ERROR "Unable to find $HOME/.paths.\nSome functionality may not work properly."
fi

print_header "Local gitconfig"
LOCAL_GIT="$HOME/.gitconfig.local"
if [[ ! -f "$LOCAL_GIT" ]]; then
	log_message ERROR "Unable to find $HOME/.gitconfig.local.\nEnsure you have ran 'bash install.sh'."
else
	log_message SUCCESS "~/.gitconfig.local already exists. Verifying..."
	if grep -q "FIXME:" "$LOCAL_GIT"; then
		log_message ERROR "Your ~/.gitconfig.local contains unresolved 'FIXME:' tags."
		log_message ERROR "You must configure your GPG key, program, and credential helper before committing."
		log_message ERROR "Run: \033[36m${EDITOR:-${VISUAL:-nano}} %s\033[0m to fix them.\n" "$LOCAL_GIT"
	fi
fi


print_header "Local paths"
if [[ -f "$HOME/.paths.local" ]]; then
	source "$HOME/.paths.local"
	log_message SUCCESS "Sourced $HOME/.paths.local"
else
	log_message ERROR "Unable to find $HOME/.paths.local.\nSome functionality may not work properly."
fi

# Colours
# Generate LS_COLORS for Zsh completion
# Tb populates the LS_COLORS variable that Zsh's completion system expects.
# Enables envVar LS_COLORS
print_header "LS_COLORS"
if [[ -z "$LS_COLORS" ]]; then
	if command -v gdircolors &>/dev/null; then
		eval "$(gdircolors -b)"
		log_message SUCCESS "LS_COLORS generated and set using gdircolors for completion."
	elif command -v dircolors &>/dev/null; then
		eval "$(dircolors -b)"
		log_message SUCCESS "LS_COLORS generated and set using dircolors for completion."
	else
		log_message WARNING "'gdircolors' and 'dircolors' commands not found. LS_COLORS is not set."
	fi
else
	log_message SUCCESS "LS_COLORS is already set."
	log_message INFO "Skipping generation..."
fi

# Source environment variables
print_header "Source Environment Variables"
if [[ -f "$HOME/.env" ]]; then
	log_message SUCCESS "Sourcing environment variables from: $HOME/.env"
	source "$HOME/.env"
else
	log_message WARNING "Environment variables file not found: $HOME/.env"
fi

# Source alias files/functions
print_header "Aliases"
if [[ -f "$HOME/.aliases" ]]; then
	log_message SUCCESS "Sourcing alias file: $HOME/.aliases"
	source "$HOME/.aliases"
else
	log_message WARNING "Alias file not found: $HOME/.aliases"
fi

print_header "Functions"
if [[ -f "$HOME/.functions" ]]; then
	log_message SUCCESS "Sourcing function file: $HOME/.functions"
	source "$HOME/.functions"
else
	log_message WARNING "Functions file not found: $HOME/.functions"
fi

print_header "Git Functions"
if [[ -f "$HOME/.git_functions" ]]; then
	log_message SUCCESS "Sourcing git functions file: $HOME/.git_functions"
	source "$HOME/.git_functions"
else
	log_message WARNING "Functions file not found: $HOME/.git_functions"
fi

# Zsh options
print_header "Zsh Options"
if [[ -f "$HOME/.zsh_options" ]]; then
	log_message SUCCESS "Sourcing Zsh options from: $HOME/.zsh_options"
	source "$HOME/.zsh_options"
else
	log_message WARNING "Zsh options file not found: $HOME/.zsh_options"
fi

# fastfetch
print_header "fastfetch"
if ! command -v fastfetch &>/dev/null; then
	log_message WARNING "fastfetch command not found, skipping fastfetch."
else
	# check for custom fastfetch config
	if [[ -f "$HOME/.config/fastfetch/config.jsonc" ]]; then
		log_message INFO "Custom fastfetch config found at $HOME/.config/fastfetch/config.jsonc\n\n"

		echo "\n\n"
		fastfetch --config "$HOME/.config/fastfetch/config.jsonc"
		echo "\n\n"

		log_message SUCCESS "fastfetch executed with custom configuration."
	else
		log_message INFO "No custom fastfetch config found, using default settings."

		echo "\n\n"
		fastfetch
		echo "\n\n"
	fi
fi

# Powerlevel10k configuration
print_header "Powerlevel10k"

P10K_DIR="$HOME/powerlevel10k"
P10K_THEME="$P10K_DIR/powerlevel10k.zsh-theme"
P10K_CONFIG="$HOME/.p10k.zsh"

# Enable Powerlevel10k instant prompt
# check for p10k
if [[ ! -d $P10K_DIR/.git || ! -f "$P10K_THEME" ]]; then
	log_message WARNING "Powerlevel10k not found at $P10K_DIR. Cloning repository..."
	if git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"; then
		log_message SUCCESS "Successfully cloned Powerlevel10k."
	else
		log_message ERROR "Failed to clone Powerlevel10k."
	fi
else
	log_message SUCCESS "Powerlevel10k detected. Sourcing..."
fi

if [[ -d "$P10K_DIR/.git" && -f "$P10K_THEME" ]]; then

	source "$P10K_THEME"
	log_message SUCCESS "Powerlevel10k theme loaded from manual git directory."

	if [[ -f "$P10K_CONFIG" ]]; then
		log_message SUCCESS "Powerlevel10k configuration file found. Sourcing."
		source "$P10K_CONFIG"
	else
		log_message WARNING "Powerlevel10k config ($HOME/.p10k.zsh) not found. Run 'p10k configure'."
	fi

else
	# Fallback if the git clone failed
	PROMPT="%{%F{green}%}%n@%{%F{blue}%}%m %{%F{yellow}%}%~%{%F{white}%} %# %{%F{reset}%}"
	RPROMPT=""
	log_message WARNING "Powerlevel10k not loaded, using a basic prompt."
fi

# Zim configuration
print_header "Zim Configuration"
if [[ ! -d "$HOME/.zim" ]]; then
	log_message WARNING "Zim directory not found: $HOME/.zim"
	log_message WARNING "Attempting to create..."
	mkdir "$HOME/.zim"
fi

# Check if Zim is installed at usual location
if [[ -d "$HOME/.zim" ]]; then
	ZIM_HOME=${ZDOTDIR:-${HOME}}/.zim
	log_message SUCCESS "Zim directory found: $HOME/.zim"

	# Download zimfw plugin manager if missing.
	if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
		curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
			https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
		log_message SUCCESS "Zimfw plugin manager downloaded to ${ZIM_HOME}/zimfw.zsh"
	else
		log_message INFO "Zimfw plugin manager already exists at ${ZIM_HOME}/zimfw.zsh"
	fi

	# Install missing modules, and update ${ZIM_HOME}/init.zsh if missing or outdated.
	if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}}/.zimrc ]]; then
		source ${ZIM_HOME}/zimfw.zsh init -q
		log_message SUCCESS "Zim modules initialized and ${ZIM_HOME}/init.zsh updated."
	else
		log_message INFO "Zim modules already initialized and ${ZIM_HOME}/init.zsh is up to date."
	fi

	# Initialize modules
	if [[ -f ${ZIM_HOME}/init.zsh ]]; then
		log_message SUCCESS "Sourcing Zim initialization file: ${ZIM_HOME}/init.zsh"
		source ${ZIM_HOME}/init.zsh
	else
		log_message WARNING "Zim initialization file not found: ${ZIM_HOME}/init.zsh"
	fi
else
	log_message ERROR "Failed to create directory: $HOME/.zim"
	log_message ERROR "Manually create it then rerun this script."
fi

# ruby
print_header "rbenv"
log_message SUCCESS "# FIXME: git clone https://github.com/rbenv/rbenv.git $HOME/.rbenv"
eval "$(rbenv init - zsh)"

# TODO: archlinux libsecret
# print_header "Node Version Manager"
# source /usr/share/nvm/init-nvm.sh

# keep these at the end of the file
print_header "Zsh Plugins"
# Enable zoxide
if command -v zoxide &>/dev/null; then
	log_message SUCCESS "zoxide command found. Enabling plugin."
	eval "$(zoxide init zsh)"
else
	log_message WARNING "zoxide is not installed, skipping plugin."
fi

# fzf
if command -v fzf &>/dev/null; then
	log_message SUCCESS "fzf command found. Enabling plugin."
	source <(fzf --zsh)
else
	log_message WARNING "fzf is not installed, skipping plugin."
fi

# Zstyles
print_header "Zstyles"
# Source zstyles
if [[ -f "$HOME/.zstyles" ]]; then
	log_message SUCCESS "Zstyles file found. Sourcing."
	source "$HOME/.zstyles"
else
	log_message WARNING "Zstyles file not found: $HOME/.zstyles"
fi

# iTerm2 shell integration
# this should be kept at the end of the file
if [[ "$OSTYPE" == "darwin"* ]]; then
	log_message INFO "MacOS detected"
	print_header "iTerm2 Shell Integration"

	if [[ -f "$HOME/.iterm2_shell_integration.zsh" ]]; then
		log_message SUCCESS "iTerm2 shell integration file found. Sourcing."
		source "$HOME/.iterm2_shell_integration.zsh"
	else
		log_message WARNING "iTerm2 shell integration file not found: $HOME/.iterm2_shell_integration.zsh"
	fi
else
	log_message INFO "Non-MacOS detected. Skipping iTerm2 shell integration."
fi

# Output debug mode status
# If DEBUG_MODE is true, print a message indicating the end of debug mode
if [[ "$DEBUG_MODE" == true ]]; then
	print_header "Debug Mode Status"

	if [[ "$ENABLE_PROFILING" == true ]]; then
		log_message INFO "Profiling is enabled. Profiling data will be saved."
	else
		log_message INFO "Profiling is disabled. No profiling data will be saved."
	fi
	print_title "END DEBUG MODE"
fi

# Enable profiling
# This should be kept at the end of the file
# It will profile the loading time of the shell and save it to a log file.
if [[ $ENABLE_PROFILING == true ]]; then
	print_title "START PROFILING"
	# Define the directory and filename for the zprof log
	local ZPROF_LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/profiling"
	local ZPROF_LOG_FILE="${ZPROF_LOG_DIR}/zprof_${DATE}.log"

	# Create the directory if it doesn't exist
	if [[ -d "$ZPROF_LOG_DIR" ]]; then
		log_message INFO "Profiling directory exists: $ZPROF_LOG_DIR"
	else
		log_message INFO "Creating profiling directory: $ZPROF_LOG_DIR"
		mkdir -p "$ZPROF_LOG_DIR"

		# Check if the directory was created successfully
		if [[ $? -ne 0 ]]; then
			# Print zprof data to console
			zprof

			log_message ERROR "Failed to create profiling log directory: $ZPROF_LOG_DIR. Profiling data will not be saved."
			log_message ERROR "Printed zprof data to console instead."

			print_title "END PROFILING"
			return
		fi
		log_message SUCCESS "Profiling directory created: $ZPROF_LOG_DIR"
	fi

	# Save profiling data to the log file
	zprof >"$ZPROF_LOG_FILE"
	log_message SUCCESS "Profiling data saved to: $ZPROF_LOG_FILE"
	log_message INFO "The file was saved with the following format: zprof_$DATE_FORMAT.log"

	# https://zsh.sourceforge.io/Doc/Release/Expansion.html#Glob-Qualifiers
	# (OmN) sorts files by modification time, oldest first
	# returns an empty list (N) if no files match the pattern
	local profile_files=("$ZPROF_LOG_DIR"/zprof_*.log(OmN))
	log_message INFO "Total profile files (including new one): ${#profile_files[@]} found in $ZPROF_LOG_DIR"
	for file in "${profile_files[@]}"; do
		log_message INFO "  Found profile file: ${file##*/}" # Show only filename
	done

	# Check if the number of profile files exceeds NUM_PROFILE_TO_KEEP
	if [[ ${#profile_files[@]} -gt $NUM_PROFILE_TO_KEEP ]]; then
		# Calculate how many files to delete
		local files_to_delete=$((${#profile_files[@]} - NUM_PROFILE_TO_KEEP))
		log_message INFO "More than $NUM_PROFILE_TO_KEEP profile files found. Deleting $files_to_delete file(s)."

		# Delete the oldest files, keeping only the most recent NUM_PROFILE_TO_KEEP files
		# NOTE: zsh arrays are 1-indexed (why???)
		for i in $(seq 1 $((files_to_delete))); do
			local file_to_remove="${profile_files[$i]}"
			if [[ -f "$file_to_remove" ]]; then
				log_message INFO "Deleting old profile file: ${file_to_remove}"
				rm "$file_to_remove"

				# Check if the file was deleted successfully
				if [[ $? -eq 0 ]]; then
					log_message SUCCESS "Deleted old profile file: ${file_to_remove##*/}" # Show only filename
				else
					log_message ERROR "Failed to delete file: ${file_to_remove}"
				fi
			fi
		done

		# Re-check the count after deletion attempt
		profile_files=("$ZPROF_LOG_DIR"/zprof_*.log(OmN))
		if [[ ${#profile_files[@]} -le $NUM_PROFILE_TO_KEEP ]]; then
			log_message SUCCESS "Old profile files cleaned up successfully. Current count: ${#profile_files[@]}"
		else
			log_message WARNING "Cleanup completed, but still more than $NUM_PROFILE_TO_KEEP files remain. Manual inspection may be needed."
		fi
	else
		log_message INFO "Number of profile files is within limit: ${#profile_files[@]} <= $NUM_PROFILE_TO_KEEP"
	fi

	log_message PROFILE "To view the profiling data, use one of the following commands:"

	# Check for 'VISUAL' environment variable
	if [[ -n "$VISUAL" ]]; then
		log_message PROFILE "  1. $VISUAL \"$ZPROF_LOG_FILE\""
	else
		log_message WARNING "  No '\$VISUAL' environment variable set."
	fi

	# Check for 'bat' command
	if command -v bat &>/dev/null; then
		# check if bat alias is set
		if alias bat &>/dev/null; then
			log_message PROFILE "  2. bat \"${ZPROF_LOG_FILE}\""
		else
			log_message PROFILE "  2. bat --paging=always --color=always \"${ZPROF_LOG_FILE}\""
		fi
	else
		log_message PROFILE "  2. cat \"${ZPROF_LOG_FILE}\""
	fi
	log_message PROFILE "  3. <app> \"${ZPROF_LOG_FILE}\""

	print_title "END PROFILING"
fi

unset DEBUG_MODE
unset ENABLE_PROFILING
