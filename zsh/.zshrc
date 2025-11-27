# -----------> macOS <-------------
# .zshrc

#################################
# Constants for debugging and profiling
#################################
#ENABLE_PROFILING=true  # Enable profiling to analyze performance
#DEBUG_MODE=true        # Only prints PROFILE, ERROR, and WARNING messages if not set, otherwise all messages are printed

######################################
# Enable zsh profiling for performance analysis
# This section needs to be at the top of the file
# to ensure profiling starts before any other commands are executed.
######################################
if [[ "$ENABLE_PROFILING" == true ]]; then
  zmodload zsh/zprof

  DATE_FORMAT="%Y-%m-%d_%H.%M.%S"   # Date format for profiling logs
  DATE="$(date +$DATE_FORMAT)"      # Current date and time in the specified format
  NUM_PROFILE_TO_KEEP=10            # Number of profile files to keep
else
  ENABLE_PROFILING=false
fi

##################################
# Settings
##################################
HISTSIZE=5000
HISTFILESIZE=5000
HISTCONTROL=ignoredups
SAVEHIST=1000
HISTFILE=~/.zsh_history
HIST_STAMPS="yyyy.mm.dd"

##################################
# Printing functions
# These functions are used to print headers and log messages
# throughout the script.
# They help in organizing the output and making it more readable.
##################################
# Print a title header
print_title() {
  local header="$1"
  echo -e "\n\033[38;5;196m\t===== $header =====\033[0m\n" # Red title header
}

# Print a header between sections
print_header() {
  local header="$1"
  if [[ "$DEBUG_MODE" == true ]]; then
    echo -e "\n\033[38;5;12m=== $header ===\033[0m\n" # Blue header
  fi
}

# --- Centralized Logging Function ---
# log_message - Function to print colored log messages
# Usage: log_message <TYPE> "Your message here"
# <TYPE> can be ERROR, WARNING, SUCCESS, INFO, or any custom type
log_message() {
  local log_type="$1"
  local message="$2"
  local csi="\033["
  local reset="\033[0m"
  local color_code=""
  local prefix=""

  # Define colors
  local -A colors=(
    [SUCCESS]="38;5;10m" # Green
    [ERROR]="38;5;9m"    # Red
    [WARNING]="38;5;3m"  # Yellow/Orange
    [INFO]="38;5;14m"    # Cyan
    [PROFILE]="38;5;13m" # Magenta
  )

  # ERROR and WARNING messages will always be printed.
  # Output from ENABLE_PROFILING will be printed regardless of DEBUG_MODE
  case "$log_type" in
    ERROR|WARNING|PROFILE)
      # ERROR, WARNING, and PROFILE messages always print.
      ;;
    SUCCESS|INFO)
      # SUCCESS and INFO messages print if DEBUG_MODE is true,
      if [[ "$DEBUG_MODE" == false ]]; then
        return # Do not print
      fi
      ;;
    *)
      # Unknown log type, print as WARNING
      # and issue warning
      log_type="WARNING"
      echo -e "${csi}${colors[${log_type}]}[UNKNOWN]${reset} ${message}"
      return
      ;;
  esac

  color_code="${colors[$log_type]}"
  prefix="[${log_type}]"

  # Print the colored message
  echo -e "${csi}${color_code}${prefix}${reset} ${message}"
}

##################################
# Check if DEBUG_MODE is set, if not, set it to false
##################################
if [[ "$DEBUG_MODE" == true ]]; then
  print_title "START DEBUG MODE"
else
  DEBUG_MODE=false
fi

##################################
# Source environment variables
##################################
print_header "Source Environment Variables"
##################################

local sourcedEnv=0 # Initialize flag

if [[ -f ~/.env ]]; then
  log_message SUCCESS "Sourcing environment variables from: ~/.env"
  source ~/.env

  # Generate LS_COLORS for Zsh completion
  # This populates the LS_COLORS variable that Zsh's completion system expects.
  # Enables envVar LS_COLORS
  if [[ -z "$LS_COLORS" ]]; then
    if command -v gdircolors &> /dev/null; then
      eval "$(gdircolors -b)"
      log_message SUCCESS "LS_COLORS generated and set using gdircolors for completion."
    else
      log_message WARNING "'gdircolors' command not found. LS_COLORS is not set."
    fi
  else
    log_message INFO "LS_COLORS is already set, skipping generation."
  fi

  #############################
  print_header "Custom Paths"
  #############################

  # Process custom paths defined in .env
  if [[ -n "${_custom_paths[@]}" ]]; then
    log_message INFO "Processing custom paths from ~/.env."
    for base_dir in "${_custom_paths[@]}"; do
      # Check for special character 'L' in base_dir
      # This indicates that there is no 'bin' subdirectory to append
      if [[ "$base_dir" == *L* ]]; then
        local_path="${base_dir//L/}" # Remove 'L' character
        log_message INFO "Detected 'L' in path, removing and not appending '/bin': ${local_path}"
      else
        local_path="${base_dir}/bin" # Append '/bin' here
      fi
      if [[ -d "$local_path" ]]; then
        export PATH="${local_path}:${PATH}"
        log_message SUCCESS "Added to PATH: ${local_path}"
      else
        log_message WARNING "Directory not found for PATH, skipping: ${local_path}"
      fi
    done
  else
    log_message INFO "No custom paths defined in ~/.env to process."
  fi

else
  sourcedEnv=1
  log_message ERROR "Environment variables file not found: ~/.env"
fi

##################################
# Source alias files/functions
##################################
print_header "Alias Files"
##################################
if [[ -d ~/.alias ]]; then
  # issue warning if envVars file was not sourced
  if [[ sourcedEnv -eq 1 ]]; then
    log_message WARNING "Some aliases may not work as expected because ~/.env was not sourced."
  fi
  # Source all alias files in ~/.alias directory
  for f in ~/.alias/*; do
    if [[ -f "$f" ]]; then
      log_message SUCCESS "Sourcing alias file: $f"
      source "$f"
    fi
  done
  ##################################
  print_header "Alias Functions"
  ##################################

  # Source functions from ~/.alias/functions directory
  if [[ -d ~/.alias/functions ]]; then
    for f in ~/.alias/functions/*; do
      if [[ -f "$f" ]]; then
        log_message SUCCESS "Sourcing function file: $f"
        source "$f"
      fi
    done
  # No functions directory found
  else
    log_message ERROR "Functions directory not found: ~/.alias/functions"
  fi
# No alias directory found
else
  log_message ERROR "Alias directory not found: ~/.alias"
fi

####################################
# Zsh options
####################################
print_header "Zsh Options"
##################################

# source zsh options
if [[ -f ~/.zsh_options ]]; then
  log_message SUCCESS "Sourcing Zsh options from: ~/.zsh_options"
  source ~/.zsh_options
else
  log_message WARNING "Zsh options file not found: ~/.zsh_options"
fi



source ~/.dotfiles/zsh/.colours
source ~/.dotfiles/zsh/.commands

###################################
# fastfetch
###################################
print_header "fastfetch"
##################################

# Enable fastfetch if running in iTerm2
if ! command -v fastfetch &> /dev/null; then
  log_message WARNING "fastfetch command not found, skipping fastfetch."
  return
else
  if [[ $TERM_PROGRAM == "iTerm.app" ]]; then
    log_message INFO "Running fastfetch in iTerm2."
    # check for custom fastfetch config
    if [[ -f ~/.config/fastfetch/config.jsonc ]]; then
      log_message INFO "Custom fastfetch config found at ~/.config/fastfetch/config.jsonc\n\n"
      
      echo "\n\n"
      fastfetch --config ~/.config/fastfetch/config.jsonc
      echo "\n\n"

      log_message SUCCESS "fastfetch executed with custom configuration."

    else
      log_message INFO "No custom fastfetch config found, using default settings."
      
      echo "\n\n"
      fastfetch
      echo "\n\n"

    fi
  else
    log_message WARNING "Not running in iTerm2, skipping fastfetch."
  fi
fi

################################
# Powerlevel10k configuration
################################
print_header "Powerlevel10k"
##################################

# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" && -f ~/.p10k.zsh ]]; then
  log_message SUCCESS "Powerlevel10k instant prompt files found. Sourcing."
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"

  log_message SUCCESS "Powerlevel10k configuration file found. Sourcing."
  source ~/.p10k.zsh
else
  if [[ ! -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    log_message ERROR "Powerlevel10k instant prompt file not found: ${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
  fi
  
  if [[ ! -f ~/.p10k.zsh ]]; then
    PROMPT="%{%F{green}%}%n@%{%F{blue}%}%m %{%F{yellow}%}%~%{%F{white}%} %# %{%F{reset}%}"
    RPROMPT=""
    log_message WARNING "Powerlevel10k not loaded, using a basic prompt."
  fi
fi

##################################
# Zim configuration
##################################
print_header "Zim Configuration"
##################################

# Check if Zim is installed at usual location
if [[ -d ~/.zim ]]; then
  ZIM_HOME=~/.zim
  log_message SUCCESS "Zim directory found: ~/.zim"

  # Download zimfw plugin manager if missing.
  if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
    curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
    log_message SUCCESS "Zimfw plugin manager downloaded to ${ZIM_HOME}/zimfw.zsh"
  else
    log_message INFO "Zimfw plugin manager already exists at ${ZIM_HOME}/zimfw.zsh"
  fi

  # Install missing modules, and update ${ZIM_HOME}/init.zsh if missing or outdated.
  if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZDOTDIR:-${HOME}}/.zimrc ]]; then
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
    log_message ERROR "Zim initialization file not found: ${ZIM_HOME}/init.zsh"
  fi
else
  log_message ERROR "Zim directory not found: ~/.zim"
fi

##################################
# Enable zsh plugins
# keep these at the end of the file
##################################
print_header "Zsh Plugins"
##################################


# thefuck
if command -v thefuck &> /dev/null; then
  log_message SUCCESS "thefuck command found. Enabling plugin."
  eval $(thefuck --alias FUCK)
else
  log_message WARNING "thefuck is not installed, skipping plugin."
fi

# Enable zoxide
if command -v zoxide &> /dev/null; then
  log_message SUCCESS "zoxide command found. Enabling plugin."
  eval "$(zoxide init zsh)"
else
  log_message WARNING "zoxide is not installed, skipping plugin."
fi

# fzf
if command -v fzf &> /dev/null; then
  log_message SUCCESS "fzf command found. Enabling plugin."
  source <(fzf --zsh)
else
  log_message WARNING "fzf is not installed, skipping plugin."
fi

###############################
# Zstyles
###############################
print_header "Zstyles"
##################################

# Source zstyles
if [[ -f ~/.zstyles ]]; then
  log_message SUCCESS "Zstyles file found. Sourcing."
  source ~/.zstyles
else
  log_message WARNING "Zstyles file not found: ~/.zstyles"
fi

##################################
# iTerm2 shell integration
# this should be kept at the end of the file 
##################################
print_header "iTerm2 Shell Integration"
##################################

if [[ -f ~/.iterm2_shell_integration.zsh ]]; then
  log_message SUCCESS "iTerm2 shell integration file found. Sourcing."
  source ~/.iterm2_shell_integration.zsh
else
  log_message WARNING "iTerm2 shell integration file not found: ~/.iterm2_shell_integration.zsh"
fi

##################################
# Output debug mode status
# If DEBUG_MODE is true, print a message indicating the end of debug mode
##################################
if [[ "$DEBUG_MODE" == true ]]; then
  ##################################
  print_header "Debug Mode Status"
  ##################################

  if [[ "$ENABLE_PROFILING" == true ]]; then
    log_message INFO "Profiling is enabled. Profiling data will be saved."
  else
    log_message INFO "Profiling is disabled. No profiling data will be saved."
  fi
  print_title "END DEBUG MODE"
fi


##################################
# Enable profiling
# This should be kept at the end of the file
# It will profile the loading time of the shell and save it to a log file.
##################################
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
    mkdir "$ZPROF_LOG_DIR" # No -p option to avoid creating parent directories
    
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
  zprof > "$ZPROF_LOG_FILE"
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
    local files_to_delete=$(( ${#profile_files[@]} - NUM_PROFILE_TO_KEEP ))
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
    log_message WARNING "   No \$VISUAL environment variable set."
  fi

  # Check for 'bat' command
  if command -v bat &> /dev/null; then
    # check if bat alias is set
    if alias bat &> /dev/null; then
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



