# logging.ps1

if ($script:__LOGGING_PS1_INCLUDED__) {
    return
}
$script:__LOGGING_PS1_INCLUDED__ = $true

$script:BASH_LOGGER_VERSION = "2.5.6"

$script:LOG_LEVEL_EMERGENCY = 0
$script:LOG_LEVEL_ALERT     = 1
$script:LOG_LEVEL_CRITICAL  = 2
$script:LOG_LEVEL_ERROR     = 3
$script:LOG_LEVEL_WARN      = 4
$script:LOG_LEVEL_NOTICE    = 5
$script:LOG_LEVEL_INFO      = 6
$script:LOG_LEVEL_DEBUG     = 7
$script:LOG_LEVEL_TRACE     = 8
$script:LOG_LEVEL_INIT      = 6
$script:LOG_LEVEL_FATAL     = $script:LOG_LEVEL_EMERGENCY

$script:COLOR_RESET             = "`e[0m"
$script:COLOR_BLUE              = "`e[34m"
$script:COLOR_GREEN             = "`e[32m"
$script:COLOR_YELLOW            = "`e[33m"
$script:COLOR_RED               = "`e[31m"
$script:COLOR_RED_BOLD          = "`e[31;1m"
$script:COLOR_WHITE_ON_RED      = "`e[37;41m"
$script:COLOR_BOLD_WHITE_ON_RED = "`e[1;37;41m"
$script:COLOR_PURPLE            = "`e[35m"
$script:COLOR_CYAN              = "`e[36m"

function default_values {
    if ([string]::IsNullOrEmpty($script:SILENCE_INIT_LOG_MSG)) {
        $script:SILENCE_INIT_LOG_MSG = "true"
    }
    $script:CONSOLE_LOG = "true"
    $script:LOG_FILE = ""
    $script:VERBOSE = "false"
    $script:CURRENT_LOG_LEVEL = $script:LOG_LEVEL_INFO
    $script:USE_UTC = "false"
    $script:LOG_INIT_MESSAGE = "false"
    $script:USE_COLORS = "auto"
    $script:LOG_STDERR_LEVEL = $script:LOG_LEVEL_ERROR
    $script:LOG_FORMAT = "%d [%l] [%s] %m"
    $script:LOG_UNSAFE_ALLOW_NEWLINES = "false"
    $script:LOG_UNSAFE_ALLOW_ANSI_CODES = "false"
    $script:LOG_MAX_LINE_LENGTH = 4096
    $script:SCRIPT_NAME = "dotfiles.ps1"
}

default_values

function _detect_color_support {
    if (-not [string]::IsNullOrEmpty($env:NO_COLOR) -or $env:CLICOLOR -eq "0") {
        return $false
    }
    if ($env:CLICOLOR_FORCE -eq "1") {
        return $true
    }
    if ([Console]::IsOutputRedirected) {
        return $false
    }
    return $true
}

function _should_use_colors {
    switch ($script:USE_COLORS) {
        "always" { return $true }
        "never"  { return $false }
        default  { return (_detect_color_support) }
    }
}

function _should_use_stderr {
    param([int]$level_value)
    return ($level_value -le $script:LOG_STDERR_LEVEL)
}

function _get_log_level_value {
    param([string]$level_name)
    switch ($level_name.ToUpperInvariant()) {
        "TRACE"     { return $script:LOG_LEVEL_TRACE }
        "DEBUG"     { return $script:LOG_LEVEL_DEBUG }
        "INFO"      { return $script:LOG_LEVEL_INFO }
        "NOTICE"    { return $script:LOG_LEVEL_NOTICE }
        "WARN"      { return $script:LOG_LEVEL_WARN }
        "WARNING"   { return $script:LOG_LEVEL_WARN }
        "ERROR"     { return $script:LOG_LEVEL_ERROR }
        "ERR"       { return $script:LOG_LEVEL_ERROR }
        "CRITICAL"  { return $script:LOG_LEVEL_CRITICAL }
        "CRIT"      { return $script:LOG_LEVEL_CRITICAL }
        "ALERT"     { return $script:LOG_LEVEL_ALERT }
        "EMERGENCY" { return $script:LOG_LEVEL_EMERGENCY }
        "EMERG"     { return $script:LOG_LEVEL_EMERGENCY }
        "FATAL"     { return $script:LOG_LEVEL_EMERGENCY }
        default {
            if ($level_name -match '^[0-8]$') {
                return [int]$level_name
            }
            return $script:LOG_LEVEL_INFO
        }
    }
}

function _get_log_level_name {
    param([int]$level_value)
    switch ($level_value) {
        $script:LOG_LEVEL_TRACE     { return "TRACE" }
        $script:LOG_LEVEL_DEBUG     { return "DEBUG" }
        $script:LOG_LEVEL_INFO      { return "INFO" }
        $script:LOG_LEVEL_NOTICE    { return "NOTICE" }
        $script:LOG_LEVEL_WARN      { return "WARN" }
        $script:LOG_LEVEL_ERROR     { return "ERROR" }
        $script:LOG_LEVEL_CRITICAL  { return "CRITICAL" }
        $script:LOG_LEVEL_ALERT     { return "ALERT" }
        $script:LOG_LEVEL_EMERGENCY { return "EMERGENCY" }
        default                     { return "UNKNOWN" }
    }
}

function _get_log_level_color {
    param([string]$level_name)
    switch ($level_name) {
        "DEBUG"     { return $script:COLOR_BLUE }
        "INFO"      { return "" }
        "NOTICE"    { return $script:COLOR_GREEN }
        "WARN"      { return $script:COLOR_YELLOW }
        "ERROR"     { return $script:COLOR_RED }
        "CRITICAL"  { return $script:COLOR_RED_BOLD }
        "ALERT"     { return $script:COLOR_WHITE_ON_RED }
        "EMERGENCY" { return $script:COLOR_BOLD_WHITE_ON_RED }
        "FATAL"     { return $script:COLOR_BOLD_WHITE_ON_RED }
        "INIT"      { return $script:COLOR_PURPLE }
        "SENSITIVE" { return $script:COLOR_CYAN }
        default     { return "" }
    }
}

function _strip_ansi_codes {
    param([string]$input_str)
    if ($script:LOG_UNSAFE_ALLOW_ANSI_CODES -eq "true" -or -not $input_str.Contains("`e")) {
        return $input_str
    }
    return ([regex]::Replace($input_str, '\x1B\[[0-9;<?>=!]*[a-zA-Z@]|\x1B\][^\a]*\a|\x1B[P^_].*?\x1B\\|\x1B[^[]', ''))
}

function _sanitize_log_message {
    param([string]$message)
    if ($null -eq $message) { return "" }
    if ($script:LOG_UNSAFE_ALLOW_NEWLINES -ne "true") {
        $message = $message.Replace("`n", " ").Replace("`r", " ").Replace("`t", " ")
    }
    return (_strip_ansi_codes $message)
}

function _truncate_log_message {
    param([string]$message, [int]$limit)
    $suffix = "...[truncated]"
    if ($limit -le 0 -or $message.Length -le $limit) {
        return $message
    }
    if ($limit -le $suffix.Length) {
        return $message.Substring(0, $limit)
    }
    $keep = $limit - $suffix.Length
    return ($message.Substring(0, $keep) + $suffix)
}

function _sanitize_script_name {
    param([string]$name)
    return ([regex]::Replace($name, '[^a-zA-Z0-9._-]', '_'))
}

function _format_log_message {
    param([string]$level_name, [string]$message)
    if ($script:USE_UTC -eq "true") {
        $current_date = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss.fff")
        $timezone_str = "UTC"
    } else {
        $current_date = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss.fff")
        $timezone_str = "LOCAL"
    }
    $sname = if ([string]::IsNullOrEmpty($script:SCRIPT_NAME)) { "dotfiles.ps1" } else { $script:SCRIPT_NAME }
    $formatted = $script:LOG_FORMAT
    $formatted = $formatted.Replace("%d", $current_date)
    $formatted = $formatted.Replace("%l", $level_name)
    $formatted = $formatted.Replace("%s", $sname)
    $formatted = $formatted.Replace("%m", $message)
    $formatted = $formatted.Replace("%z", $timezone_str)
    return $formatted
}

function init_logger {
    default_values
    $script:SCRIPT_NAME = "dotfiles.ps1"

    $i = 0
    while ($i -lt $args.Count) {
        $arg = [string]$args[$i]
        switch -Regex -CaseSensitive ($arg) {
            '^(--color|--colour)$' {
                $script:USE_COLORS = "always"
                $i++
            }
            '^(--no-color|--no-colour)$' {
                $script:USE_COLORS = "never"
                $i++
            }
            '^(-d|--level)$' {
                $script:CURRENT_LOG_LEVEL = _get_log_level_value ([string]$args[$i + 1])
                $i += 2
            }
            '^(-f|--format)$' {
                $script:LOG_FORMAT = [string]$args[$i + 1]
                $i += 2
            }
            '^(-l|--log|--logfile|--log-file|--file)$' {
                $script:LOG_FILE = [string]$args[$i + 1]
                $i += 2
            }
            '^(-n|--name|--script-name)$' {
                $script:SCRIPT_NAME = _sanitize_script_name ([string]$args[$i + 1])
                $i += 2
            }
            '^(-q|--quiet)$' {
                $script:CONSOLE_LOG = "false"
                $i++
            }
            '^(-u|--utc)$' {
                $script:USE_UTC = "true"
                $i++
            }
            '^(-v|--verbose|--debug)$' {
                $script:VERBOSE = "true"
                $script:CURRENT_LOG_LEVEL = $script:LOG_LEVEL_DEBUG
                $i++
            }
            '^(-e|--stderr-level)$' {
                $script:LOG_STDERR_LEVEL = _get_log_level_value ([string]$args[$i + 1])
                $i += 2
            }
            '^--no-init-message$' {
                $script:LOG_INIT_MESSAGE = "false"
                $i++
            }
            default {
                [Console]::Error.WriteLine("Unknown parameter for logger: $arg")
                return $false
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($script:LOG_FILE)) {
        $nativeLogFile = if (Get-Command _native_path -ErrorAction SilentlyContinue) { _native_path $script:LOG_FILE } else { $script:LOG_FILE }
        $logDir = [System.IO.Path]::GetDirectoryName($nativeLogFile)
        if (-not [string]::IsNullOrEmpty($logDir) -and -not [System.IO.Directory]::Exists($logDir)) {
            try {
                [void][System.IO.Directory]::CreateDirectory($logDir)
            } catch {
                [Console]::Error.WriteLine("Error: Cannot create log directory")
                return $false
            }
        }

        try {
            if (-not [System.IO.File]::Exists($nativeLogFile)) {
                [System.IO.File]::WriteAllText($nativeLogFile, "", [System.Text.UTF8Encoding]::new($false))
            }
            $item = Get-Item -LiteralPath $nativeLogFile -Force -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                [Console]::Error.WriteLine("Error: Log file path is a symbolic link")
                return $false
            }
        } catch {
            [Console]::Error.WriteLine("Error: Cannot create or access log file")
            return $false
        }
    }

    log_debug "Logger initialized with script_name='$($script:SCRIPT_NAME)': console=$($script:CONSOLE_LOG), file=$($script:LOG_FILE), colors=$($script:USE_COLORS), log level=$(_get_log_level_name $script:CURRENT_LOG_LEVEL)"
    return $true
}

function _log_to_console {
    param([string]$log_entry, [string]$level_name, [int]$level_value)
    $output = $log_entry
    if (_should_use_colors) {
        $color = _get_log_level_color $level_name
        if (-not [string]::IsNullOrEmpty($color)) {
            $output = "${color}${output}$($script:COLOR_RESET)"
        }
    }
    if (_should_use_stderr $level_value) {
        [Console]::Error.WriteLine($output)
    } else {
        [Console]::Out.WriteLine($output)
    }
}

function _log_message {
    param(
        [string]$level_name,
        [int]$level_value,
        [string]$message,
        [string]$skip_file = "false",
        [string]$force_show = "false"
    )
    if ($level_value -gt $script:CURRENT_LOG_LEVEL -and $force_show -ne "true") {
        return
    }
    $sanitized = _sanitize_log_message $message
    $truncated = _truncate_log_message $sanitized $script:LOG_MAX_LINE_LENGTH
    $log_entry = _format_log_message $level_name $truncated

    if ($script:CONSOLE_LOG -eq "true") {
        _log_to_console $log_entry $level_name $level_value
    }

    if (-not [string]::IsNullOrEmpty($script:LOG_FILE) -and $skip_file -ne "true") {
        try {
            $nativeLogFile = if (Get-Command _native_path -ErrorAction SilentlyContinue) { _native_path $script:LOG_FILE } else { $script:LOG_FILE }
            [System.IO.File]::AppendAllText($nativeLogFile, "$log_entry`n", [System.Text.UTF8Encoding]::new($false))
        } catch {
            if (-not $script:LOGGER_FILE_ERROR_REPORTED) {
                [Console]::Error.WriteLine("ERROR: Failed to write to log file")
                $script:LOGGER_FILE_ERROR_REPORTED = $true
            }
            [Console]::Error.WriteLine($log_entry)
        }
    }
}

function _caller_name {
    $stack = Get-PSCallStack
    if ($stack.Count -ge 3 -and -not [string]::IsNullOrEmpty($stack[2].FunctionName)) {
        return $stack[2].FunctionName
    }
    return "main"
}

function log_trace {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_TRACE) {
        $fn = _caller_name
        _log_message "TRACE" $script:LOG_LEVEL_TRACE "${fn}: ${msg}"
    }
}

function _enter {
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_TRACE) {
        $fn = _caller_name
        _log_message "TRACE" $script:LOG_LEVEL_TRACE "${fn}: Entering"
    }
}

function _exit {
    param([int]$code = 0)
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_TRACE) {
        $fn = _caller_name
        _log_message "TRACE" $script:LOG_LEVEL_TRACE "${fn}: Exiting with code ${code}"
    }
}

function log_debug {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_DEBUG) {
        _log_message "DEBUG" $script:LOG_LEVEL_DEBUG $msg
    }
}

function log_info {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_INFO) {
        _log_message "INFO" $script:LOG_LEVEL_INFO $msg
    }
}

function log_notice {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_NOTICE) {
        _log_message "NOTICE" $script:LOG_LEVEL_NOTICE $msg
    }
}

function log_warn {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_WARN) {
        _log_message "WARN" $script:LOG_LEVEL_WARN $msg
    }
}

function log_error {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_ERROR) {
        _log_message "ERROR" $script:LOG_LEVEL_ERROR $msg
    }
}

function log_critical {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_CRITICAL) {
        _log_message "CRITICAL" $script:LOG_LEVEL_CRITICAL $msg
    }
}

function log_alert {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_ALERT) {
        _log_message "ALERT" $script:LOG_LEVEL_ALERT $msg
    }
}

function log_emergency {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_EMERGENCY) {
        _log_message "EMERGENCY" $script:LOG_LEVEL_EMERGENCY $msg
    }
}

function log_fatal {
    param([string]$msg = "")
    if ($script:CURRENT_LOG_LEVEL -ge $script:LOG_LEVEL_EMERGENCY) {
        _log_message "FATAL" $script:LOG_LEVEL_EMERGENCY $msg
    }
}
