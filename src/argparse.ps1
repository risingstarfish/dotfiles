# argparse.ps1

if ($script:__ARGPARSE_PS1_INCLUDED__) {
    return
}
$script:__ARGPARSE_PS1_INCLUDED__ = $true

function _assert_string_unset {
    param([string]$val, [string]$msg, [string]$flag)
    _enter
    if (-not [string]::IsNullOrEmpty($val)) {
        _exit 2
        die 2 '%s. Conflicting flag: "%s"' $msg $flag
    }
    _exit
}

function _assert_flag_unset {
    param([int]$val, [string]$msg, [string]$flag)
    _enter
    if ($val -eq 1) {
        _exit 2
        die 2 '%s. Conflicting flag: "%s"' $msg $flag
    }
    _exit
}

function assert_main_action_unset {
    param([string]$flag)
    _enter
    _assert_string_unset $script:DF_MAIN_ACTION "action already set to `"$($script:DF_MAIN_ACTION)`"" $flag
    _exit
}

function assert_log_level_unset {
    param([string]$flag)
    _enter
    _assert_string_unset $script:DF_LOG_LEVEL "log level already set to `"$($script:DF_LOG_LEVEL)`"" $flag
    _assert_flag_unset $script:DF_NO_LOG "logging is disabled via --no-log" $flag
    _exit
}

function assert_exclude_modules_unset {
    param([string]$flag)
    _enter
    if ($script:DF_EXCLUDE_SET.Count -gt 0) {
        _exit 2
        die 2 'excluded modules already set. Conflicting flag: "%s"' $flag
    }
    _exit
}

function assert_include_modules_unset {
    param([string]$flag)
    _enter
    if ($script:DF_INCLUDE_SET.Count -gt 0) {
        _exit 2
        die 2 'included modules already set. Conflicting flag: "%s"' $flag
    }
    _exit
}

function assert_interactive_unset {
    param([string]$flag)
    _enter
    _assert_flag_unset $script:DF_INTERACTIVE "interactive mode is already set" $flag
    _exit
}

function assert_noconfirm_unset {
    param([string]$flag)
    _enter
    _assert_flag_unset $script:DF_NOCONFIRM "noconfirm is already set" $flag
    _exit
}

function assert_force_unset {
    param([string]$flag)
    _enter
    _assert_flag_unset $script:DF_FORCE "force mode is already set" $flag
    _exit
}

function assert_days {
    param([string]$flag, [string]$val)
    _enter
    if ($val -notmatch '^[0-9]+$') {
        _exit 2
        die 2 '%s requires a number of days (0 or more). Got: "%s"' $flag $val
    }
    _exit
}

function require_arg {
    param([string]$flag, [string]$val)
    _enter
    if ([string]::IsNullOrEmpty($val) -or $val.StartsWith("-")) {
        _exit 2
        die 2 'missing argument for %s.' $flag
    }
    _exit
}

function argparse {
    param([string[]]$cli_args)
    _enter

    $script:DF_MAIN_ACTION   = ""
    $script:DF_REMOVE_SET    = @()
    $script:DF_INCLUDE_SET   = @()
    $script:DF_EXCLUDE_SET   = @()
    $script:DF_DRY_RUN       = 0
    $script:DF_NOCONFIRM     = 0
    $script:DF_NO_REGENERATE = 0
    $script:DF_INTERACTIVE   = 0
    $script:DF_FORCE         = 0
    $script:DF_NO_BACKUP     = 0
    $script:DF_CLEAN_DAYS    = ""
    $script:DF_CLEAN_KEEP    = ""
    $script:DF_CLEAN_LOGS    = 0
    $script:DF_CLEAN_BACKUPS = 0
    if ([string]::IsNullOrEmpty([string]$script:DOTFILES_AUTORESTART)) {
        $script:DOTFILES_AUTORESTART = 0
    } elseif (is_true ([string]$script:DOTFILES_AUTORESTART)) {
        $script:DOTFILES_AUTORESTART = 1
    } else {
        $script:DOTFILES_AUTORESTART = 0
    }
    $autorestart_flag = 0
    $script:DF_LOG_LEVEL  = ""
    $script:DF_NO_LOG     = 0
    $script:DF_PRINT_TIME = 0

    $i = 0
    $count = if ($null -ne $cli_args) { $cli_args.Count } else { 0 }
    while ($i -lt $count) {
        $arg = [string]$cli_args[$i]
        $next = if (($i + 1) -lt $count) { [string]$cli_args[$i + 1] } else { "" }

        switch -Regex -CaseSensitive ($arg) {
            '^(-h|--help)$' {
                print_help
                _exit
                exit 0
            }
            '^--version$' {
                print_version
                _exit
                exit 0
            }
            '^(-l|--list)$' {
                list_modules
                _exit
                exit 0
            }
            '^--install$' {
                assert_main_action_unset $arg
                $script:DF_MAIN_ACTION = "install"
                $i++
            }
            '^(-r|--remove)$' {
                assert_main_action_unset $arg
                assert_exclude_modules_unset $arg
                assert_include_modules_unset $arg
                require_arg $arg $next
                parse_module_list $next "DF_REMOVE_SET"
                $script:DF_MAIN_ACTION = "remove"
                $i += 2
            }
            '^--remove=(.*)$' {
                $flagPart = $arg.Substring(0, $arg.IndexOf('='))
                $valPart  = $arg.Substring($arg.IndexOf('=') + 1)
                assert_main_action_unset $flagPart
                assert_exclude_modules_unset $flagPart
                assert_include_modules_unset $flagPart
                require_arg $flagPart $valPart
                parse_module_list $valPart "DF_REMOVE_SET"
                $script:DF_MAIN_ACTION = "remove"
                $i++
            }
            '^--uninstall$' {
                assert_main_action_unset $arg
                $script:DF_MAIN_ACTION = "uninstall"
                $i++
            }
            '^(-u|--update)$' {
                assert_main_action_unset $arg
                $script:DF_MAIN_ACTION = "update"
                $i++
            }
            '^(-R|--repair)$' {
                assert_main_action_unset $arg
                $script:DF_MAIN_ACTION = "repair"
                $i++
            }
            '^--reset$' {
                assert_main_action_unset $arg
                $script:DF_MAIN_ACTION = "reset"
                $i++
            }
            '^--clean$' {
                assert_main_action_unset $arg
                if ((($i + 1) -lt $count) -and (-not $next.StartsWith("-"))) {
                    assert_days $arg $next
                    $script:DF_CLEAN_DAYS = $next
                    $i += 2
                } else {
                    assert_days $arg ([string]$script:DOTFILES_MAX_BACKUPS)
                    $script:DF_CLEAN_KEEP = [string]$script:DOTFILES_MAX_BACKUPS
                    $i++
                }
                $script:DF_MAIN_ACTION = "clean"
                $script:DF_CLEAN_LOGS = 1
                $script:DF_CLEAN_BACKUPS = 1
            }
            '^--clean-logs$' {
                assert_main_action_unset $arg
                $script:DF_MAIN_ACTION = "clean"
                $script:DF_CLEAN_LOGS = 1
                $i++
            }
            '^--clean-backups$' {
                assert_main_action_unset $arg
                if ((($i + 1) -lt $count) -and (-not $next.StartsWith("-"))) {
                    assert_days $arg $next
                    $script:DF_CLEAN_DAYS = $next
                    $i += 2
                } else {
                    assert_days $arg ([string]$script:DOTFILES_MAX_BACKUPS)
                    $script:DF_CLEAN_KEEP = [string]$script:DOTFILES_MAX_BACKUPS
                    $i++
                }
                $script:DF_CLEAN_BACKUPS = 1
                $script:DF_MAIN_ACTION = "clean"
            }
            '^(-i|--include)$' {
                assert_exclude_modules_unset $arg
                require_arg $arg $next
                parse_module_list $next "DF_INCLUDE_SET"
                $i += 2
            }
            '^(-i|--include)=(.*)$' {
                $flagPart = $arg.Substring(0, $arg.IndexOf('='))
                $valPart  = $arg.Substring($arg.IndexOf('=') + 1)
                assert_exclude_modules_unset $flagPart
                require_arg $flagPart $valPart
                parse_module_list $valPart "DF_INCLUDE_SET"
                $i++
            }
            '^(-x|--exclude)$' {
                assert_include_modules_unset $arg
                require_arg $arg $next
                parse_module_list $next "DF_EXCLUDE_SET"
                $i += 2
            }
            '^(-x|--exclude)=(.*)$' {
                $flagPart = $arg.Substring(0, $arg.IndexOf('='))
                $valPart  = $arg.Substring($arg.IndexOf('=') + 1)
                assert_include_modules_unset $flagPart
                require_arg $flagPart $valPart
                parse_module_list $valPart "DF_EXCLUDE_SET"
                $i++
            }
            '^(-n|--dry-run)$' {
                $script:DF_DRY_RUN = 1
                $i++
            }
            '^(-K|--autorestart)$' {
                $script:DOTFILES_AUTORESTART = 1
                $autorestart_flag = 1
                $i++
            }
            '^(-G|--no-regenerate)$' {
                $script:DF_NO_REGENERATE = 1
                $i++
            }
            '^--no-backup$' {
                $script:DF_NO_BACKUP = 1
                $i++
            }
            '^(-I|--interactive)$' {
                assert_force_unset $arg
                assert_noconfirm_unset $arg
                $script:DF_INTERACTIVE = 1
                $i++
            }
            '^(--noconfirm|-y|--yes)$' {
                assert_interactive_unset $arg
                $script:DF_NOCONFIRM = 1
                $i++
            }
            '^(-f|--force)$' {
                assert_interactive_unset $arg
                $script:DF_FORCE = 1
                $i++
            }
            '^(-d|--debug)$' {
                assert_log_level_unset $arg
                $script:DF_LOG_LEVEL = "debug"
                $i++
            }
            '^(-q|--quiet)$' {
                assert_log_level_unset $arg
                $script:DF_LOG_LEVEL = "error"
                $i++
            }
            '^--log-level$' {
                assert_log_level_unset $arg
                require_arg $arg $next
                $lvl = $next.ToUpperInvariant()
                if ($lvl -in @("TRACE", "DEBUG", "INFO", "NOTICE", "WARN", "ERROR")) {
                    $script:DF_LOG_LEVEL = $lvl
                    $i += 2
                } else {
                    die 2 'invalid log level "%s". Use: trace, debug, info, notice, warn, or error' $next
                }
            }
            '^--log-level=(.*)$' {
                $flagPart = $arg.Substring(0, $arg.IndexOf('='))
                $valPart  = $arg.Substring($arg.IndexOf('=') + 1)
                assert_log_level_unset $flagPart
                $lvl = $valPart.ToUpperInvariant()
                if ($lvl -in @("TRACE", "DEBUG", "INFO", "NOTICE", "WARN", "ERROR")) {
                    $script:DF_LOG_LEVEL = $lvl
                } else {
                    die 2 'invalid log level "%s". Use: trace, debug, info, notice, warn, or error' $valPart
                }
                $i++
            }
            '^--no-log$' {
                if (-not [string]::IsNullOrEmpty($script:DF_LOG_LEVEL)) {
                    die 2 'log level already set to "%s". Cannot use %s.' $script:DF_LOG_LEVEL $arg
                }
                $script:DF_NO_LOG = 1
                $i++
            }
            '^--time$' {
                $script:DF_PRINT_TIME = 1
                $i++
            }
            default {
                die 2 'invalid parameter "%s"\nRun `pwsh -NoProfile -File %s --help` for valid options.' $arg "dotfiles.ps1"
            }
        }
    }

    if ([string]::IsNullOrEmpty($script:DF_LOG_LEVEL)) {
        switch ($script:DOTFILES_ENV) {
            "development" { $script:DF_LOG_LEVEL = "DEBUG" }
            "testing"     { $script:DF_LOG_LEVEL = "TRACE" }
            default       { $script:DF_LOG_LEVEL = "INFO" }
        }
    }

    if ([string]::IsNullOrEmpty($script:DF_MAIN_ACTION)) {
        _exit 2
        die 2 'no action specified.\nRun `pwsh -NoProfile -File %s --help` for valid options.' "dotfiles.ps1"
    }

    if ($script:DF_MAIN_ACTION -in @("remove", "update", "uninstall", "reset", "repair", "clean")) {
        if ($script:DF_INCLUDE_SET.Count -gt 0 -or $script:DF_EXCLUDE_SET.Count -gt 0) {
            _exit 2
            die 2 "--include/--exclude not supported with --$($script:DF_MAIN_ACTION)"
        }
    }

    if ($script:DF_MAIN_ACTION -eq "remove" -and $script:DF_REMOVE_SET.Count -eq 0) {
        _exit 2
        die 2 "no modules for --remove"
    }

    if ($script:DF_NO_REGENERATE -eq 1 -and $script:DF_MAIN_ACTION -notin @("install", "update")) {
        _exit 2
        die 2 '--no-regenerate is only supported with --install and --update'
    }

    if ($script:DF_NO_BACKUP -eq 1 -and $script:DF_MAIN_ACTION -notin @("install", "update")) {
        _exit 2
        die 2 '--no-backup is only supported with --install and --update'
    }

    if ($script:DF_DRY_RUN -eq 1) {
        if ($script:DOTFILES_AUTORESTART -eq 1) {
            if ($autorestart_flag -eq 1) {
                _exit 2
                die 2 '--autorestart is not meaningful with --dry-run'
            }
            $script:DOTFILES_AUTORESTART = 0
        }
        if ($script:DF_INTERACTIVE -eq 1) {
            _exit 2
            die 2 '--interactive is meaningless with --dry-run'
        }
        if ($script:DF_FORCE -eq 1) {
            _exit 2
            die 2 '--force is meaningless with --dry-run'
        }
    }

    _exit
}
