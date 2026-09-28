# utility.ps1

if ($script:__UTILITY_PS1_INCLUDED__) {
    return
}
$script:__UTILITY_PS1_INCLUDED__ = $true

# Canonicalize a file path per D2:
# - Replaces backslashes with forward slashes
# - Converts Windows drive paths (C:/foo or C:\foo) to MSYS /c/foo
# - Collapses duplicate slashes and strips trailing slash (except /)
function _canonical_path {
    param([string]$p = "")
    if ([string]::IsNullOrEmpty($p)) { return "" }
    $p = $p.TrimEnd("`r").Replace('\', '/')
    if ($p -match '^([A-Za-z]):(/.*)?$') {
        $drv = $Matches[1].ToLowerInvariant()
        $rest = if ($Matches[2]) { $Matches[2] } else { "/" }
        $p = "/${drv}${rest}"
    }
    while ($p.Contains("//")) {
        $p = $p.Replace("//", "/")
    }
    if ($p.Length -gt 1 -and $p.EndsWith("/")) {
        $p = $p.TrimEnd("/")
    }
    return $p
}

# Convert canonical path (/c/Users/...) to native OS path (C:\Users\... on Windows, /... on POSIX)
function _native_path {
    param([string]$p = "")
    if ([string]::IsNullOrEmpty($p)) { return "" }
    $p = $p.TrimEnd("`r")
    if ($IsWindows) {
        if ($p -match '^/([A-Za-z])(/.*)?$') {
            $drv = $Matches[1].ToUpperInvariant()
            $rest = if ($Matches[2]) { $Matches[2].Replace('/', '\') } else { '\' }
            return "${drv}:${rest}"
        }
        return $p.Replace('/', '\')
    }
    return $p.Replace('\', '/')
}

function _format_printf {
    param([string]$fmt, [object[]]$fmtArgs)
    if ($null -eq $fmtArgs -or $fmtArgs.Count -eq 0) {
        return $fmt.Replace('\n', "`n")
    }
    $res = $fmt.Replace('\n', "`n")
    foreach ($a in $fmtArgs) {
        $idx = $res.IndexOf('%')
        if ($idx -ge 0 -and ($idx + 1) -lt $res.Length) {
            $spec = $res.Substring($idx, 2)
            if ($spec -eq '%s' -or $spec -eq '%d' -or $spec -eq '%b') {
                $res = $res.Substring(0, $idx) + [string]$a + $res.Substring($idx + 2)
            }
        }
    }
    return $res
}

function die {
    _enter
    $rc = if ($args.Count -ge 1 -and $null -ne $args[0]) { [int]$args[0] } else { 2 }
    $fmt = if ($args.Count -ge 2) { [string]$args[1] } else { "" }
    $rest = if ($args.Count -gt 2) { $args[2..($args.Count - 1)] } else { @() }
    $msg = _format_printf $fmt $rest
    [Console]::Error.WriteLine("Error: $msg")
    _exit $rc
    if (Get-Command release_lock -ErrorAction SilentlyContinue) {
        release_lock
    }
    exit $rc
}

function prompt_continue {
    _enter
    if ($args.Count -gt 0) {
        $fmt = [string]$args[0]
        $rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
        $msg = _format_printf $fmt $rest
        if (-not [string]::IsNullOrEmpty($msg)) {
            [Console]::Error.WriteLine($msg)
        }
    }

    while ($true) {
        [Console]::Out.WriteLine("")
        [Console]::Error.Write("Do you want to continue anyway? [y/N]: ")
        $choice = [Console]::In.ReadLine()
        if ($null -eq $choice) {
            [Console]::Error.WriteLine("Error: No input available for prompt.")
            _exit 1
            return 1
        }
        switch -Regex ($choice) {
            '^[yY]$' {
                _exit 0
                return 0
            }
            '^[nN]$' {
                [Console]::Error.WriteLine("Aborting installation!")
                _exit 130
                if (Get-Command release_lock -ErrorAction SilentlyContinue) {
                    release_lock
                }
                exit 130
            }
            default {
                [Console]::Error.WriteLine("Error: Invalid input. Please enter y or n.")
            }
        }
    }
}

function is_windows_bash {
    _enter
    if ($env:MSYSTEM -match '^(MINGW|MSYS|UCRT|UCRT64|MSYS2)$') {
        _exit 0
        return $true
    }
    _exit 1
    return $false
}

function parse_module_list {
    param(
        [string]$raw_list,
        [string]$target_var_name
    )
    _enter
    $mods = $raw_list -split ';'
    $arr = [System.Collections.Generic.List[string]]::new()
    $existing = Get-Variable -Name $target_var_name -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        foreach ($item in $existing) { [void]$arr.Add([string]$item) }
    }

    foreach ($raw_m in $mods) {
        $m = $raw_m.Trim()
        if ([string]::IsNullOrEmpty($m)) { continue }

        $valid = 0
        if ($m.Contains("/")) {
            foreach ($mod in $script:DF_AVAILABLE_MODULES) {
                if ($mod -eq $m -or $mod.StartsWith("$m/")) {
                    $valid = 1
                    break
                }
            }
        } else {
            $matches_list = [System.Collections.Generic.List[string]]::new()
            foreach ($mod in $script:DF_AVAILABLE_MODULES) {
                $leaf = $mod.Substring($mod.LastIndexOf('/') + 1)
                $cat = $mod.Substring(0, $mod.IndexOf('/'))
                if ($leaf -eq $m) {
                    [void]$matches_list.Add($mod)
                } elseif ($cat -eq $m) {
                    $valid = 1
                }
            }

            if ($matches_list.Count -eq 1) {
                $valid = 1
                log_debug "Resolved bare name '$m' to module '$($matches_list[0])'"
                $m = $matches_list[0]
            } elseif ($matches_list.Count -gt 1) {
                _exit 2
                die 2 'ambiguous module name "%s". Matches: %s' $m ($matches_list -join ' ')
            } elseif ($script:DF_CATEGORY_MAP.ContainsKey($m) -and -not [string]::IsNullOrEmpty($script:DF_CATEGORY_MAP[$m])) {
                $valid = 1
                log_debug "Resolved display category '$m' to '$($script:DF_CATEGORY_MAP[$m])'"
                $m = $script:DF_CATEGORY_MAP[$m]
            }
        }

        if ($valid -eq 0) {
            _exit 2
            die 2 'unknown module "%s".\nRun with --list to see valid modules.' $m
        }

        [void]$arr.Add($m)
    }

    Set-Variable -Name $target_var_name -Scope Script -Value ($arr.ToArray())
    _exit
}

function _exec_cmd {
    param(
        [string]$cmd,
        [string]$err_msg,
        [string]$suc_msg,
        [scriptblock]$action_block = $null
    )
    log_trace "Executing: $cmd"
    try {
        if ($null -ne $action_block) {
            & $action_block
        } else {
            $errOut = Invoke-Expression $cmd 2>&1
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                throw "Exit code $LASTEXITCODE : $errOut"
            }
        }
    } catch {
        log_trace "Operation failed"
        log_error $err_msg
        log_debug "System error: $($_.Exception.Message)"
        _exit 1
        return 1
    }

    log_debug $suc_msg
    _exit 0
    return 0
}

function attempt_cmd {
    param(
        [string]$cmd,
        [string]$msg,
        [string]$err_msg,
        [string]$suc_msg,
        [scriptblock]$action_block = $null
    )
    _enter
    if ($script:DF_DRY_RUN -eq 1) {
        log_trace "DF_DRY_RUN set; bypassing destructive operation"
        log_info "[dry-run] $cmd"
        _exit 0
        return 0
    }

    if ($script:DF_NOCONFIRM -eq 1) {
        log_trace "DF_NOCONFIRM set; skipping prompt"
    } else {
        log_info "About to run: $cmd"
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  $msg")
        [Console]::Error.Write("  Continue? [Y/n] ")
        $reply = [Console]::In.ReadLine()
        if ($null -eq $reply) { $reply = "" }
        log_trace "User prompt reply: '$reply'"
        switch ($reply.ToLowerInvariant()) {
            { $_ -in @('y', 'yes', '') } {
                log_trace "User confirmed"
            }
            default {
                log_trace "User rejected prompt"
                log_warn "Operation cancelled by user."
                _exit 130
                return 130
            }
        }
        [Console]::Error.WriteLine("")
    }

    return (_exec_cmd $cmd $err_msg $suc_msg $action_block)
}

function attempt_cmd_quiet {
    param(
        [string]$cmd,
        [string]$msg,
        [string]$err_msg,
        [string]$suc_msg,
        [scriptblock]$action_block = $null
    )
    _enter
    if ($script:DF_DRY_RUN -eq 1) {
        log_trace "DF_DRY_RUN set; bypassing operation"
        log_info "[dry-run] $cmd"
        _exit 0
        return 0
    }

    if ($script:DF_INTERACTIVE -eq 1) {
        log_info "About to run: $cmd"
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  $msg")
        [Console]::Error.Write("  Continue? [Y/n] ")
        $reply = [Console]::In.ReadLine()
        if ($null -eq $reply) { $reply = "" }
        log_trace "User prompt reply: '$reply'"
        switch ($reply.ToLowerInvariant()) {
            { $_ -in @('y', 'yes', '') } {
                log_trace "User confirmed"
            }
            default {
                log_trace "User rejected prompt"
                log_warn "Operation cancelled by user."
                _exit 130
                return 130
            }
        }
        [Console]::Error.WriteLine("")
    } else {
        log_trace "Non-interactive mode; executing without prompt"
    }

    return (_exec_cmd $cmd $err_msg $suc_msg $action_block)
}
