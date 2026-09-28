# action.ps1

if ($script:__ACTION_PS1_INCLUDED__) {
    return
}
$script:__ACTION_PS1_INCLUDED__ = $true

function set_user_modules {
    _enter
    if ($null -ne $script:DF_USER_MODULES -and $script:DF_USER_MODULES.Count -gt 0) {
        log_debug "DF_USER_MODULES is already populated. Skipping."
        log_trace "Exiting (already populated)"
        _exit
        return 0
    }

    $num_inc   = $script:DF_INCLUDE_SET.Count
    $num_exc   = $script:DF_EXCLUDE_SET.Count
    $num_total = $script:DF_AVAILABLE_MODULES.Count
    $num_target = if ($num_inc -gt 0) {
        $num_inc
    } elseif ($num_exc -gt 0) {
        if ($num_total -gt $num_exc) { $num_total - $num_exc } else { 0 }
    } else {
        $num_total
    }

    log_trace "Set counts -> num_inc=${num_inc}, num_exc=${num_exc}, num_total=${num_total}"
    log_debug "Processing ${num_target}/${num_total} modules."

    $selected = [System.Collections.Generic.List[string]]::new()

    foreach ($mod in $script:DF_AVAILABLE_MODULES) {
        $mod_slash = "${mod}/"
        log_trace "Evaluating module '${mod}' (mod_slash='${mod_slash}')"

        if ($num_inc -gt 0) {
            $included = 0
            foreach ($inc in $script:DF_INCLUDE_SET) {
                log_trace "Testing include filter '${inc}/'* against '${mod_slash}'"
                if ($mod_slash.StartsWith("${inc}/")) {
                    $included = 1
                    log_trace "Match found for include filter '${inc}'"
                    break
                }
            }
            if ($included -eq 0) {
                log_debug "Skipped '${mod}' (not in DF_INCLUDE_SET)"
                log_trace "Module '${mod}' skipped because it did not match DF_INCLUDE_SET"
                continue
            }
        }

        if ($num_exc -gt 0) {
            $excluded = 0
            foreach ($exc in $script:DF_EXCLUDE_SET) {
                log_trace "Testing exclude filter '${exc}/'* against '${mod_slash}'"
                if ($mod_slash.StartsWith("${exc}/")) {
                    $excluded = 1
                    log_trace "Match found for exclude filter '${exc}'"
                    break
                }
            }
            if ($excluded -ne 0) {
                log_debug "Skipped '${mod}' (matched DF_EXCLUDE_SET)"
                log_trace "Module '${mod}' skipped because it matched DF_EXCLUDE_SET"
                continue
            }
        }

        log_debug "Added '${mod}'"
        log_trace "Appending '${mod}' to DF_USER_MODULES"
        [void]$selected.Add($mod)
    }

    $script:DF_USER_MODULES = $selected.ToArray()
    log_info "Selected $($script:DF_USER_MODULES.Count) total modules for processing."
    _exit
    return 0
}

function set_dotfiles_ref {
    _enter
    if (-not [string]::IsNullOrEmpty($script:DF_DOTFILES_REF)) {
        log_debug "DF_DOTFILES_REF already set to '$($script:DF_DOTFILES_REF)'. Skipping."
        log_trace "Exiting (DF_DOTFILES_REF already set)"
        _exit
        return 0
    }

    log_debug "Determining git ref for '$($script:DF_SRC_PATH)'..."
    $nativeSrc = _native_path $script:DF_SRC_PATH

    log_trace "Executing: git -C '$($script:DF_SRC_PATH)' rev-parse --git-dir"
    $null = & git -C $nativeSrc rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        log_trace "git rev-parse failed (not a git repository)"
        log_error "Unable to determine git ref. Make sure '$($script:DF_SRC_PATH)' is a git repo."
        _exit 1
        return 1
    }

    log_trace "Executing: git -C '$($script:DF_SRC_PATH)' config --local dotfiles.ref"
    $config_ref = (& git -C $nativeSrc config --local dotfiles.ref 2>$null | Out-String).Trim()
    log_trace "Retrieved config_ref='${config_ref}'"

    if (-not [string]::IsNullOrEmpty($config_ref)) {
        $script:DF_DOTFILES_REF = $config_ref
        log_debug "Found custom ref in git config."
    } else {
        $script:DF_DOTFILES_REF = "main"
        log_debug "No custom git config found. Falling back to default."
    }

    _exit
    return 0
}

function _prepare_file {
    param([string]$source, [string]$dest)
    _enter

    if ([string]::IsNullOrEmpty($source) -or [string]::IsNullOrEmpty($dest)) {
        log_error "requires both source and destination paths."
        _exit 1
        return 1
    }

    $nativeSource = _native_path $source
    if (-not [System.IO.File]::Exists($nativeSource)) {
        log_error "source file does not exist: '${source}'"
        _exit 1
        return 1
    }

    $nativeDest = _native_path $dest
    $dest_dir_native = [System.IO.Path]::GetDirectoryName($nativeDest)
    $dest_dir_display = if ($dest.Contains('/')) { $dest.Substring(0, $dest.LastIndexOf('/')) } else { $dest_dir_native }

    if (-not [System.IO.Directory]::Exists($dest_dir_native)) {
        log_debug "Creating parent directory: '${dest_dir_display}'"
        $rc = attempt_cmd_quiet `
            "mkdir -p `"${dest_dir_display}`"" `
            "Creating parent directory for ${dest}" `
            "Cannot create target directory '${dest_dir_display}'" `
            "Created directory '${dest_dir_display}'" `
            { [void][System.IO.Directory]::CreateDirectory($dest_dir_native) }
        if ($rc -ne 0) {
            _exit 1
            return 1
        }
    }

    _exit 0
    return 0
}

function _guard_dest {
    param([string]$dest, [string]$src)
    _enter

    $nativeDest = _native_path $dest
    $isLink = _test_is_symlink $nativeDest
    $exists = [System.IO.File]::Exists($nativeDest) -or [System.IO.Directory]::Exists($nativeDest)

    if (-not $exists -and -not $isLink) {
        log_trace "No existing file at '${dest}'. Nothing to guard."
        _exit 0
        return 0
    }

    if ($isLink) {
        $item = Get-Item -LiteralPath $nativeDest -Force -ErrorAction SilentlyContinue
        $target = if ($null -ne $item) {
            if ($item.LinkTarget) { $item.LinkTarget }
            elseif ($item.Target) { [string]($item.Target | Select-Object -First 1) }
            else { "" }
        } else { "" }

        if (-not [string]::IsNullOrEmpty($target) -and -not [System.IO.Path]::IsPathRooted($target) -and -not $target.StartsWith("/")) {
            $parentDir = [System.IO.Path]::GetDirectoryName($nativeDest)
            $target = [System.IO.Path]::Combine($parentDir, $target)
        }

        $canonTarget = _canonical_path $target
        $canonSrc    = _canonical_path $src
        if (-not [string]::IsNullOrEmpty($canonTarget) -and $canonTarget.StartsWith($canonSrc)) {
            log_debug "'${dest}' is already a symlink into our repo (${target}). Skipping backup."
            _exit 0
            return 0
        }
        log_debug "'${dest}' is a symlink pointing to '${target}' (not our repo). Will back up."
    }

    if ($script:DF_FORCE -eq 1) {
        log_warn "DF_FORCE set. Removing '${dest}' without backup."
        if ($script:DF_DRY_RUN -eq 1) {
            log_info "[dry-run] Would remove: ${dest}"
            _exit 0
            return 0
        }
        $rc = attempt_cmd_quiet `
            "rm -f `"${dest}`"" `
            "Attempting to remove destination" `
            "Failed to remove ${dest}" `
            "Successfully removed dest" `
            { Remove-Item -LiteralPath $nativeDest -Force -ErrorAction Stop }
        if ($rc -ne 0) {
            _exit 1
            return 1
        }
        _exit 0
        return 0
    }

    $base = [System.IO.Path]::GetFileName($nativeDest)
    if ($script:DF_DRY_RUN -eq 1) {
        log_info "[dry-run] mv ${dest} $($script:DOTFILES_BACKUP_DIR)/$($script:DOTFILES_START_TIME)/${base}.bak"
        _exit 0
        return 0
    }

    if ($script:DF_INTERACTIVE -eq 1) {
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  Existing file found: ${dest}")
        [Console]::Error.Write("  Back up and replace? [Y/n] ")
        $reply = [Console]::In.ReadLine()
        if ($null -eq $reply) {
            log_warn "No input available for backup prompt. Skipping."
            _exit 1
            return 1
        }
        switch ($reply.ToLowerInvariant()) {
            { $_ -in @('y', 'yes', '') } {
                log_debug "User confirmed backup."
            }
            default {
                log_warn "User declined backup. Skipping '${dest}'."
                _exit 1
                return 1
            }
        }
        [Console]::Error.WriteLine("")
    }

    $backup_dir = "$($script:DOTFILES_BACKUP_DIR)/$($script:DOTFILES_START_TIME)"
    $nativeBackupDir = _native_path $backup_dir
    $backup_path = "${backup_dir}/${base}.bak"
    $nativeBackupPath = _native_path $backup_path

    $n = 1
    while ([System.IO.File]::Exists($nativeBackupPath) -or [System.IO.Directory]::Exists($nativeBackupPath) -or (_test_is_symlink $nativeBackupPath)) {
        $backup_path = "${backup_dir}/${base}.${n}.bak"
        $nativeBackupPath = _native_path $backup_path
        log_debug "Collision at '${base}.bak'. Trying index ${n}."
        $n++
    }

    log_debug "Resolved backup path: '${backup_path}'"

    $rc = attempt_cmd_quiet `
        "mkdir -p `"${backup_dir}`"" `
        "Making backup directory" `
        "Cannot create backup directory '${backup_dir}'" `
        "Successfully created backup directory." `
        { [void][System.IO.Directory]::CreateDirectory($nativeBackupDir) }
    if ($rc -ne 0) {
        _exit 1
        return 1
    }

    log_notice "Backing up ${dest} → ${backup_path}"

    $rc = attempt_cmd_quiet `
        "mv `"${dest}`" `"${backup_path}`"" `
        "Attempting to create backup" `
        "Failed to back up '${dest}'" `
        "Successfully backed up destination" `
        { Move-Item -LiteralPath $nativeDest -Destination $nativeBackupPath -Force -ErrorAction Stop }
    if ($rc -ne 0) {
        _exit 1
        return 1
    }

    log_debug "Backup complete."
    _exit 0
    return 0
}

# ─────────────────────────────────────────────────────────────
# State-manifest helpers (D1 & D2 compliant)
# ─────────────────────────────────────────────────────────────

function manifest_write {
    param([string]$source, [string]$dest, [string]$ftype)
    if ($script:DF_DRY_RUN -eq 1) {
        return 0
    }

    $canonSource = _canonical_path $source
    $canonDest   = _canonical_path $dest
    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    $manifestDir = [System.IO.Path]::GetDirectoryName($nativeManifest)

    if (-not [System.IO.Directory]::Exists($manifestDir)) {
        try {
            [void][System.IO.Directory]::CreateDirectory($manifestDir)
        } catch {
            log_error "Cannot create manifest directory '${manifestDir}'"
            return 1
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ([System.IO.File]::Exists($nativeManifest)) {
        $rawContent = [System.IO.File]::ReadAllText($nativeManifest, $utf8NoBom)
        $lines = $rawContent -split "`n"
        $found = $false
        $outLines = [System.Collections.Generic.List[string]]::new()

        foreach ($rawLine in $lines) {
            $line = $rawLine.TrimEnd("`r")
            if ([string]::IsNullOrEmpty($line)) {
                continue
            }
            if ($line.StartsWith("#")) {
                [void]$outLines.Add($line)
                continue
            }
            $parts = $line -split "`t"
            if ($parts.Count -ge 2) {
                $rowDest = _canonical_path $parts[1]
                if ($rowDest -eq $canonDest) {
                    [void]$outLines.Add("${canonSource}`t${canonDest}`t${ftype}")
                    $found = $true
                } else {
                    $rowSrc = _canonical_path $parts[0]
                    $rowType = if ($parts.Count -ge 3) { $parts[2] } else { "" }
                    [void]$outLines.Add("${rowSrc}`t${rowDest}`t${rowType}")
                }
            }
        }

        if (-not $found) {
            [void]$outLines.Add("${canonSource}`t${canonDest}`t${ftype}")
            log_trace "Manifest: added '${canonDest}' → ${ftype}"
        } else {
            log_trace "Manifest: updated '${canonDest}' → ${ftype}"
        }

        $finalText = if ($outLines.Count -gt 0) { ($outLines -join "`n") + "`n" } else { "" }
        [System.IO.File]::WriteAllText($nativeManifest, $finalText, $utf8NoBom)
    } else {
        $entry = "${canonSource}`t${canonDest}`t${ftype}`n"
        [System.IO.File]::WriteAllText($nativeManifest, $entry, $utf8NoBom)
        log_trace "Manifest: added '${canonDest}' → ${ftype}"
    }
    return 0
}

function manifest_remove {
    param([string]$dest)
    if ($script:DF_DRY_RUN -eq 1) {
        return 0
    }
    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    if (-not [System.IO.File]::Exists($nativeManifest)) {
        return 0
    }

    $canonDest = _canonical_path $dest
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $rawContent = [System.IO.File]::ReadAllText($nativeManifest, $utf8NoBom)
    $lines = $rawContent -split "`n"
    $outLines = [System.Collections.Generic.List[string]]::new()

    foreach ($rawLine in $lines) {
        $line = $rawLine.TrimEnd("`r")
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line.StartsWith("#")) {
            [void]$outLines.Add($line)
            continue
        }
        $parts = $line -split "`t"
        if ($parts.Count -ge 2) {
            $rowDest = _canonical_path $parts[1]
            if ($rowDest -ne $canonDest) {
                [void]$outLines.Add($line)
            }
        }
    }

    $finalText = if ($outLines.Count -gt 0) { ($outLines -join "`n") + "`n" } else { "" }
    [System.IO.File]::WriteAllText($nativeManifest, $finalText, $utf8NoBom)
    log_trace "Manifest: removed entry for '${canonDest}'"
    return 0
}

function manifest_remove_prefix {
    param([string]$prefix)
    if ($script:DF_DRY_RUN -eq 1) {
        return 0
    }
    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    if (-not [System.IO.File]::Exists($nativeManifest)) {
        return 0
    }

    $canonPrefix = _canonical_path $prefix
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $rawContent = [System.IO.File]::ReadAllText($nativeManifest, $utf8NoBom)
    $lines = $rawContent -split "`n"
    $outLines = [System.Collections.Generic.List[string]]::new()

    foreach ($rawLine in $lines) {
        $line = $rawLine.TrimEnd("`r")
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line.StartsWith("#")) {
            [void]$outLines.Add($line)
            continue
        }
        $parts = $line -split "`t"
        if ($parts.Count -ge 1) {
            $rowSrc = _canonical_path $parts[0]
            if (-not $rowSrc.StartsWith($canonPrefix)) {
                [void]$outLines.Add($line)
            }
        }
    }

    $finalText = if ($outLines.Count -gt 0) { ($outLines -join "`n") + "`n" } else { "" }
    [System.IO.File]::WriteAllText($nativeManifest, $finalText, $utf8NoBom)
    log_trace "Manifest: removed all entries with source prefix '${canonPrefix}'"
    return 0
}

function manifest_clear {
    if ($script:DF_DRY_RUN -eq 1) {
        return 0
    }
    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    if ([System.IO.File]::Exists($nativeManifest)) {
        [System.IO.File]::WriteAllText($nativeManifest, "", [System.Text.UTF8Encoding]::new($false))
        log_trace "Manifest: cleared ($($script:DOTFILES_MANIFEST_FILE) removed)"
    }
    return 0
}

function manifest_read {
    param([ref]$map_ref)
    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    if (-not [System.IO.File]::Exists($nativeManifest)) {
        return 0
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $rawContent = [System.IO.File]::ReadAllText($nativeManifest, $utf8NoBom)
    $lines = $rawContent -split "`n"

    foreach ($rawLine in $lines) {
        $line = $rawLine.TrimEnd("`r")
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line.StartsWith("#")) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -lt 2) { continue }
        $src  = ($parts[0]).TrimEnd("`r")
        $dest = ($parts[1]).TrimEnd("`r")
        if ([string]::IsNullOrEmpty($src) -or [string]::IsNullOrEmpty($dest)) { continue }
        if ($src.StartsWith("#") -or $dest.StartsWith("#")) { continue }
        $canonSrc  = _canonical_path $src
        $canonDest = _canonical_path $dest
        $map_ref.Value[$canonDest] = $canonSrc
    }

    log_debug "Manifest: loaded $($map_ref.Value.Count) installed entries."
    return 0
}

function _read_manifest_entries {
    param(
        [ref]$srcs_ref,
        [ref]$dests_ref,
        [ref]$types_ref,
        [string]$context = "operation"
    )
    _enter
    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    if (-not [System.IO.File]::Exists($nativeManifest)) {
        log_warn "No manifest found. Nothing to ${context}."
        _exit 1
        return 1
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $rawContent = [System.IO.File]::ReadAllText($nativeManifest, $utf8NoBom)
    $lines = $rawContent -split "`n"

    $sList = [System.Collections.Generic.List[string]]::new()
    $dList = [System.Collections.Generic.List[string]]::new()
    $tList = [System.Collections.Generic.List[string]]::new()

    foreach ($rawLine in $lines) {
        $line = $rawLine.TrimEnd("`r")
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line.StartsWith("#")) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -lt 2) { continue }
        $src   = ($parts[0]).TrimEnd("`r")
        $dest  = ($parts[1]).TrimEnd("`r")
        $ftype = if ($parts.Count -ge 3) { ($parts[2]).TrimEnd("`r") } else { "" }
        if ([string]::IsNullOrEmpty($src) -or [string]::IsNullOrEmpty($dest)) { continue }
        if ($src.StartsWith("#") -or $dest.StartsWith("#")) { continue }
        [void]$sList.Add((_canonical_path $src))
        [void]$dList.Add((_canonical_path $dest))
        [void]$tList.Add($ftype)
    }

    $srcs_ref.Value  = $sList.ToArray()
    $dests_ref.Value = $dList.ToArray()
    $types_ref.Value = $tList.ToArray()

    if ($dList.Count -eq 0) {
        log_info "Manifest is empty. Nothing to ${context}."
        _exit 1
        return 1
    }

    log_debug "Loaded $($dList.Count) manifest entries."
    _exit 0
    return 0
}

# Execute post-install command per D6
function _exec_post_cmd {
    param([string]$cmd)
    if ($cmd -match '^chmod\s+(\+x|[0-7]{3,4})\s+(.+)$') {
        $mode = $Matches[1]
        $targetPath = _native_path ($Matches[2].Trim('"').Trim("'"))
        if ($IsWindows) {
            if ($mode -eq "600") {
                $user = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
                $null = & icacls.exe $targetPath /inheritance:r /grant:r "${user}:(R,W)" 2>$null
            } else {
                log_notice "Post-install '${cmd}': chmod ${mode} is a no-op on Windows filesystem; skipping."
            }
        } else {
            $null = & chmod $mode $targetPath 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "chmod $mode $targetPath failed"
            }
        }
        return
    }
    $null = Invoke-Expression $cmd
}

# Shared per-file install pipeline (D7 / 1-B.2):
#   prepare -> guard (if enabled) -> symlink/copy/generate -> post_cmd -> manifest_write
function _install_entry {
    param(
        [string]$full_src,
        [string]$dest,
        [string]$action,
        [string]$cmd = "",
        [int]$skip_guard = 0,
        [string]$label = ""
    )
    _enter
    if ([string]::IsNullOrEmpty($label)) {
        $label = "${full_src} → ${dest}"
    }

    if ((_prepare_file $full_src $dest) -ne 0) {
        log_error "Pre-flight failed: '${label}'"
        _exit 1
        return 1
    }

    if ($skip_guard -eq 0) {
        if ($script:DF_NO_BACKUP -eq 0) {
            if ((_guard_dest $dest $full_src) -ne 0) {
                _exit 1
                return 1
            }
        } else {
            log_trace "Backups are explicitly disabled via DF_NO_BACKUP."
        }
    }

    $nativeSrc  = _native_path $full_src
    $nativeDest = _native_path $dest
    $effectiveAction = $action
    $ok = 0

    switch ($action) {
        "symlink" {
            log_debug "[symlink] ${label}"
            $ok = attempt_cmd_quiet `
                "ln -sfn `"${full_src}`" `"${dest}`"" `
                "Symlinking ${label}" `
                "Symlink failed: ${label}" `
                "Symlinked ${label}" `
                {
                    if ([System.IO.File]::Exists($nativeDest) -or [System.IO.Directory]::Exists($nativeDest) -or (_test_is_symlink $nativeDest)) {
                        Remove-Item -LiteralPath $nativeDest -Force -ErrorAction Stop
                    }
                    try {
                        [void](New-Item -ItemType SymbolicLink -Path $nativeDest -Target $nativeSrc -Force -ErrorAction Stop)
                    } catch {
                        if ($IsWindows) {
                            log_warn "SymbolicLink creation failed on Windows (missing elevation/Developer Mode); falling back to copy for '${label}'."
                            Copy-Item -LiteralPath $nativeSrc -Destination $nativeDest -Force -ErrorAction Stop
                            $script:_LAST_FALLBACK_COPY = $true
                        } else {
                            throw
                        }
                    }
                }
            if ($script:_LAST_FALLBACK_COPY) {
                $effectiveAction = "copy"
                $script:_LAST_FALLBACK_COPY = $false
            }
        }
        "copy" {
            log_debug "[copy] ${label}"
            $ok = attempt_cmd_quiet `
                "cp -f `"${full_src}`" `"${dest}`"" `
                "Copying ${label}" `
                "Copy failed: ${label}" `
                "Copied ${label}" `
                {
                    if (_test_is_symlink $nativeDest) {
                        Remove-Item -LiteralPath $nativeDest -Force -ErrorAction Stop
                    }
                    Copy-Item -LiteralPath $nativeSrc -Destination $nativeDest -Force -ErrorAction Stop
                }
        }
        "generate" {
            $existsNonEmpty = [System.IO.File]::Exists($nativeDest) -and (([System.IO.FileInfo]::new($nativeDest)).Length -gt 0)
            if ($existsNonEmpty -and $script:DF_NO_REGENERATE -eq 1) {
                log_debug "[generate] '${dest}' already exists. Skipping."
                [void](manifest_write $full_src $dest "generate")
                _exit 0
                return 0
            }
            if ($script:DF_NO_REGENERATE -eq 0) {
                log_debug "[generate] regenerating '${dest}'."
            }
            $ok = attempt_cmd_quiet `
                "`"${full_src}`" `"${dest}`"" `
                "Generating ${label}" `
                "Generate failed: ${label}" `
                "Generated ${label}" `
                {
                    $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
                    if ($null -ne $bashCmd) {
                        & bash $nativeSrc $nativeDest
                        if ($LASTEXITCODE -ne 0) {
                            throw "Generator script failed with exit code $LASTEXITCODE"
                        }
                    } else {
                        throw "bash not found to run generator $nativeSrc"
                    }
                }
        }
        default {
            log_error "Unknown action '${action}' for '${label}'"
            _exit 1
            return 1
        }
    }

    if ($ok -eq 0 -and -not [string]::IsNullOrEmpty($cmd)) {
        log_debug "Post-install: '${cmd}'"
        $ok = attempt_cmd_quiet `
            $cmd `
            "Post-install for ${label}" `
            "Post-install failed: ${label}" `
            "Post-install done: ${label}" `
            { _exec_post_cmd $cmd }
    }

    if ($ok -eq 0) {
        [void](manifest_write $full_src $dest $effectiveAction)
        log_debug "✓ ${label}"
        _exit 0
        return 0
    } else {
        log_error "✗ ${label}"
        _exit 1
        return 1
    }
}

function install_all {
    _enter
    $installed = 0
    $skipped   = 0
    $failed    = 0

    log_info "Installing $($script:DF_USER_MODULES.Count) manifest entries (stamp: $($script:DOTFILES_START_TIME))"
    log_debug "Flags -> DF_DRY_RUN=$($script:DF_DRY_RUN), DF_FORCE=$($script:DF_FORCE), DF_NOCONFIRM=$($script:DF_NOCONFIRM)"

    foreach ($src in $script:DF_USER_MODULES) {
        log_trace "Processing: '${src}'"
        $action = if ($script:DF_MODULE_ACTION.ContainsKey($src)) { $script:DF_MODULE_ACTION[$src] } else { "" }
        $dest   = if ($script:DF_MODULE_DEST.ContainsKey($src))   { $script:DF_MODULE_DEST[$src] }   else { "" }
        $cmd    = if ($script:DF_MODULE_CMD.ContainsKey($src))    { $script:DF_MODULE_CMD[$src] }    else { "" }

        if ([string]::IsNullOrEmpty($action) -or [string]::IsNullOrEmpty($dest)) {
            log_warn "No manifest data for module '${src}'. Skipping."
            $skipped++
            continue
        }

        $full_src = "$($script:DF_MODULE_DIR)/${src}"
        $label    = "${src} → ${dest}"

        if ((_install_entry $full_src $dest $action $cmd 0 $label) -eq 0) {
            $installed++
        } else {
            $failed++
        }
    }

    log_info "Done: ${installed} installed, ${skipped} skipped, ${failed} failed."
    $script:DF_ERROR_COUNT = $failed
    _exit
    return 0
}

function do_install {
    _enter
    log_info "Beginning installation!"
    log_trace "Calling set_user_modules()"
    [void](set_user_modules)
    log_trace "Returned from set_user_modules() (DF_USER_MODULES count: $($script:DF_USER_MODULES.Count))"

    $rc = 0
    [void](install_all)
    if ($script:DF_ERROR_COUNT -gt 0) {
        $rc = 1
    }

    if ($rc -ne 0) {
        log_error "Install finished with $($script:DF_ERROR_COUNT) failure(s)!"
        _exit 1
        return 1
    }

    log_info "Installation complete!"
    _exit 0
    return 0
}

function do_update {
    _enter
    if ((set_dotfiles_ref) -ne 0) {
        _exit 1
        if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
        exit 1
    }
    log_trace "Resolved DF_DOTFILES_REF='$($script:DF_DOTFILES_REF)'"
    log_info "Beginning update!"

    $nativeSrc = _native_path $script:DF_SRC_PATH
    $gitDir = [System.IO.Path]::Combine($nativeSrc, ".git")
    if (-not [System.IO.Directory]::Exists($gitDir) -and -not [System.IO.File]::Exists($gitDir)) {
        die 1 '%s is not a git clone. Run with --install first.' $script:DF_SRC_PATH
    }

    $has_local_mods = 0
    $null = & git -C $nativeSrc diff --quiet HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        $has_local_mods = 1
    }
    log_trace "Local modifications status: has_local_mods=${has_local_mods}"
    log_info "Updating dotfiles in $($script:DF_SRC_PATH) (ref: $($script:DF_DOTFILES_REF))"

    if ($has_local_mods -eq 1 -and -not (is_true ([string]$script:DOTFILES_LOCAL_MODS))) {
        log_warn "Uncommitted changes in $($script:DF_SRC_PATH). Update blocked."
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  This repo is publicly maintained. Do not edit tracked files directly.")
        [Console]::Error.WriteLine("  Use .local override files for personal customisation:")
        [Console]::Error.WriteLine("    e.g.  tmux.conf  ->  tmux.conf.local")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  Revert your changes or move them to .local file, then re-run.")
        [Console]::Error.WriteLine("  (dev: set DOTFILES_LOCAL_MODS=1 to bypass this check)")
        [Console]::Error.WriteLine("")
        $diffStat = (& git -C $nativeSrc diff --stat HEAD 2>$null | Out-String)
        if (-not [string]::IsNullOrEmpty($diffStat)) {
            [Console]::Error.WriteLine($diffStat.TrimEnd())
        }
        _exit 1
        return 1
    }

    if ($script:DF_DRY_RUN -eq 1) {
        log_info "[dry-run] git -C `"$($script:DF_SRC_PATH)`" fetch origin --depth=2 `"$($script:DF_DOTFILES_REF)`""
        $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
        if ([System.IO.File]::Exists($nativeManifest)) {
            log_info "[dry-run] Prepend '# ref=$($script:DF_DOTFILES_REF) timestamp=<UTC>' to $($script:DOTFILES_MANIFEST_FILE)"
        }
        if ($has_local_mods -eq 1 -and (is_true ([string]$script:DOTFILES_LOCAL_MODS))) {
            log_info "[dry-run] git -C `"$($script:DF_SRC_PATH)`" rebase FETCH_HEAD"
        } else {
            $rc = attempt_cmd `
                "git -C '`"$($script:DF_SRC_PATH)`"' reset --hard FETCH_HEAD" `
                "This discards ALL local changes in '$($script:DF_SRC_PATH)'" `
                "Reset to $($script:DF_DOTFILES_REF) failed in '$($script:DF_SRC_PATH)'." `
                "Reset local repository."
            if ($rc -ne 0) { return $rc }
        }
        _exit 0
        return 0
    }

    log_trace "Executing: git -C '$($script:DF_SRC_PATH)' fetch origin --depth=2 '$($script:DF_DOTFILES_REF)'"
    $null = & git -C $nativeSrc fetch origin --depth=2 $script:DF_DOTFILES_REF 2>$null
    if ($LASTEXITCODE -ne 0) {
        log_error "Fetch failed (ref: $($script:DF_DOTFILES_REF)). Check network or repo URL."
        _exit 1
        return 1
    }

    $nativeManifest = _native_path $script:DOTFILES_MANIFEST_FILE
    if ([System.IO.File]::Exists($nativeManifest)) {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $existingContent = [System.IO.File]::ReadAllText($nativeManifest, $utf8NoBom).Replace("`r`n", "`n")
        $utcStamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $headerLine = "# ref=$($script:DF_DOTFILES_REF) timestamp=${utcStamp}`n"
        [System.IO.File]::WriteAllText($nativeManifest, ($headerLine + $existingContent), $utf8NoBom)
    }

    if ($has_local_mods -eq 1 -and (is_true ([string]$script:DOTFILES_LOCAL_MODS))) {
        log_warn "Local modifications present. Rebasing onto FETCH_HEAD."
        $null = & git -C $nativeSrc rebase FETCH_HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            log_error "Rebase failed."
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("  Resolve conflicts, then:")
            [Console]::Error.WriteLine("    git -C `"$($script:DF_SRC_PATH)`" rebase --continue")
            [Console]::Error.WriteLine("  Or abort with:")
            [Console]::Error.WriteLine("    git -C `"$($script:DF_SRC_PATH)`" rebase --abort")
            _exit 1
            return 1
        }
    } else {
        $rc = attempt_cmd `
            "git -C '`"$($script:DF_SRC_PATH)`"' reset --hard FETCH_HEAD" `
            "This discards ALL local changes in '$($script:DF_SRC_PATH)'" `
            "Reset to $($script:DF_DOTFILES_REF) failed in '$($script:DF_SRC_PATH)'." `
            "Reset local repository." `
            {
                $null = & git -C $nativeSrc reset --hard FETCH_HEAD 2>$null
                if ($LASTEXITCODE -ne 0) { throw "git reset --hard failed" }
            }
        if ($rc -ne 0) {
            return $rc
        }

        $null = & git -C $nativeSrc show-ref --verify --quiet "refs/heads/$($script:DF_DOTFILES_REF)" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $null = & git -C $nativeSrc branch -f $script:DF_DOTFILES_REF FETCH_HEAD 2>$null
        }
    }

    _exit 0
    return 0
}

function remove_file {
    param([string]$dest)
    _enter
    if ([string]::IsNullOrEmpty($dest)) {
        log_error "remove_file: no destination provided."
        _exit 1
        return 1
    }

    $nativeDest = _native_path $dest
    $exists = [System.IO.File]::Exists($nativeDest) -or [System.IO.Directory]::Exists($nativeDest) -or (_test_is_symlink $nativeDest)
    if (-not $exists) {
        log_trace "remove_file: '${dest}' does not exist. Nothing to remove."
        _exit 0
        return 0
    }

    if ($script:DF_DRY_RUN -eq 1) {
        log_info "[dry-run] rm -f ${dest}"
        _exit 0
        return 0
    }

    try {
        Remove-Item -LiteralPath $nativeDest -Force -ErrorAction Stop
    } catch {
        log_error "Failed to remove '${dest}'"
        _exit 1
        return 1
    }

    [void](manifest_remove $dest)
    log_debug "Removed: ${dest}"
    _exit 0
    return 0
}

function do_uninstall {
    _enter
    $ec = 0
    $failed_files = [System.Collections.Generic.List[string]]::new()

    log_info "Beginning uninstall."

    $installed_src = @{}
    [void](manifest_read ([ref]$installed_src))
    $entry_count = $installed_src.Count
    $plural = if ($entry_count -eq 1) { "y" } else { "ies" }
    log_debug "Manifest holds ${entry_count} installed entr${plural}."

    if ($entry_count -gt 0) {
        if ($script:DF_DRY_RUN -eq 0 -and $script:DF_NOCONFIRM -eq 0) {
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("  This will remove ${entry_count} installed file(s):")
            foreach ($dest in $installed_src.Keys) {
                [Console]::Error.WriteLine("    - ${dest}")
            }
            [Console]::Error.WriteLine("")
            [Console]::Error.Write("  Continue? [Y/n] ")
            $reply = [Console]::In.ReadLine()
            if ($null -eq $reply) { $reply = "" }
            switch ($reply.ToLowerInvariant()) {
                { $_ -in @('y', 'yes', '') } {
                    log_trace "User confirmed manifest removal"
                }
                default {
                    log_warn "Uninstall cancelled by user."
                    _exit 130
                    if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
                    exit 130
                }
            }
            [Console]::Error.WriteLine("")
        }

        foreach ($dest in @($installed_src.Keys)) {
            if ((remove_file $dest) -ne 0) {
                $ec++
                [void]$failed_files.Add($dest)
            }
        }
    } else {
        log_warn "No modules found to uninstall."
        if ($script:DF_DRY_RUN -eq 0 -and $script:DF_NOCONFIRM -eq 0) {
            [void](prompt_continue)
        }
    }

    $nativeBackupDir = _native_path $script:DOTFILES_BACKUP_DIR
    $rc = attempt_cmd `
        "rm -rf `"$($script:DOTFILES_BACKUP_DIR)`"" `
        "Are you sure you want to completely remove dotfiles backup directory?" `
        "Failed to removed `"$($script:DOTFILES_BACKUP_DIR)`"" `
        "Successfully removed backup directory!" `
        { if ([System.IO.Directory]::Exists($nativeBackupDir)) { Remove-Item -LiteralPath $nativeBackupDir -Recurse -Force -ErrorAction Stop } }
    if ($rc -eq 130) {
        if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
        exit 130
    } elseif ($rc -ne 0) { $ec++ }

    $nativeCacheDir = _native_path $script:DOTFILES_CACHE_DIR
    $rc = attempt_cmd `
        "rm -rf `"$($script:DOTFILES_CACHE_DIR)`"" `
        "Are you sure you want to completely remove dotfiles cache directory?" `
        "Failed to removed `"$($script:DOTFILES_CACHE_DIR)`"" `
        "Successfully removed cache directory!" `
        { if ([System.IO.Directory]::Exists($nativeCacheDir)) { Remove-Item -LiteralPath $nativeCacheDir -Recurse -Force -ErrorAction Stop } }
    if ($rc -eq 130) {
        if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
        exit 130
    } elseif ($rc -ne 0) { $ec++ }

    if ($script:DF_TARGET_OS -ne $script:OS_WINDOWS) {
        $nativeSrcDir = _native_path $script:DF_SRC_PATH
        $rc = attempt_cmd `
            "rm -rf `"$($script:DF_SRC_PATH)`"" `
            "Are you sure you want to completely remove dotfiles?" `
            "Failed to removed `"$($script:DF_SRC_PATH)`"" `
            "Successfully removed repository!" `
            { if ([System.IO.Directory]::Exists($nativeSrcDir)) { Remove-Item -LiteralPath $nativeSrcDir -Recurse -Force -ErrorAction Stop } }
        if ($rc -eq 130) {
            if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
            exit 130
        } elseif ($rc -ne 0) { $ec++ }
    } else {
        [Console]::Error.WriteLine("Warning: on windows, you will have to manually delete $($script:DF_SRC_PATH)")
    }

    if ($ec -gt 0) {
        log_error "Uninstall finished with ${ec} error(s)!"
        if ($failed_files.Count -gt 0) {
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("  Failed to remove the following file(s):")
            foreach ($f in $failed_files) {
                [Console]::Error.WriteLine("    ✗ ${f}")
            }
            [Console]::Error.WriteLine("")
        }
    } else {
        log_info "Uninstall finished successfully!"
    }

    if ($script:DF_DRY_RUN -eq 0 -and $script:DF_NOCONFIRM -eq 0) {
        [Console]::Error.WriteLine("")
        [Console]::Error.Write("  Remove log directory: $($script:DOTFILES_LOG_DIR) ? [Y/n] ")
        $reply = [Console]::In.ReadLine()
        if ($null -eq $reply) { $reply = "" }
        switch ($reply.ToLowerInvariant()) {
            { $_ -in @('y', 'yes', '') } {}
            default {
                log_warn "Log directory removal cancelled by user."
                _exit $ec
                return $ec
            }
        }
    }

    $script:LOG_FILE = ""
    if ($script:DF_DRY_RUN -eq 0) {
        $nativeLogDir = _native_path $script:DOTFILES_LOG_DIR
        try {
            if ([System.IO.Directory]::Exists($nativeLogDir)) {
                Remove-Item -LiteralPath $nativeLogDir -Recurse -Force -ErrorAction Stop
            }
            log_info "Successfully removed log directory!"
        } catch {
            log_info "Failed to remove $($script:DOTFILES_LOG_DIR)"
            $ec++
        }
    } else {
        log_info "[dry-run] rm -rf $($script:DOTFILES_LOG_DIR)"
    }

    $script:DF_UNINSTALL_ERRORS = $ec
    _exit $ec
    return $ec
}

function _maintenance_confirm {
    param([string]$msg)
    _enter
    if ($script:DF_DRY_RUN -eq 1 -or $script:DF_NOCONFIRM -eq 1) {
        _exit 0
        return 0
    }

    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("  $msg")
    [Console]::Error.Write("  Continue? [Y/n] ")
    $reply = [Console]::In.ReadLine()
    if ($null -eq $reply) { $reply = "" }
    switch ($reply.ToLowerInvariant()) {
        { $_ -in @('y', 'yes', '') } {
            [Console]::Error.WriteLine("")
            _exit 0
            return 0
        }
        default {
            log_warn "Clean cancelled by user."
            _exit 130
            return 130
        }
    }
}

function _clean_backups {
    _enter
    $ec = 0
    $nativeBackupDir = _native_path $script:DOTFILES_BACKUP_DIR

    if (-not [System.IO.Directory]::Exists($nativeBackupDir)) {
        log_info "No backup directory at '$($script:DOTFILES_BACKUP_DIR)'. Nothing to clean."
        _exit 0
        return 0
    }

    $dirs = @(Get-ChildItem -LiteralPath $nativeBackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $targets = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrEmpty($script:DF_CLEAN_DAYS)) {
        $days = [int]$script:DF_CLEAN_DAYS
        $cutoff = [DateTime]::Now.AddDays(-($days + 1))
        foreach ($d in $dirs) {
            if ($d.LastWriteTime -lt $cutoff) {
                [void]$targets.Add($d.FullName)
            }
        }
        if ($targets.Count -eq 0) {
            log_info "No backups older than $($script:DF_CLEAN_DAYS) day(s). Nothing to clean."
            _exit 0
            return 0
        }
        $msg = "This will remove $($targets.Count) backup dir(s) older than $($script:DF_CLEAN_DAYS) day(s):"
        foreach ($t in $targets) { $msg += "`n    - $t" }
    } else {
        $keep = [int]$script:DF_CLEAN_KEEP
        $total = $dirs.Count
        if ($keep -le 0 -or $total -le $keep) {
            log_info "Keeping all ${total} backup dir(s) (max: ${keep}). Nothing to clean."
            _exit 0
            return 0
        }
        for ($i = $keep; $i -lt $total; $i++) {
            [void]$targets.Add($dirs[$i].Name)
        }
        $msg = "This will remove $($targets.Count) backup dir(s), keeping the latest ${keep}:"
        foreach ($t in $targets) { $msg += "`n    - $t" }
    }

    $conf = _maintenance_confirm $msg
    if ($conf -ne 0) {
        _exit 130
        return 130
    }

    if ($script:DF_DRY_RUN -eq 1) {
        foreach ($t in $targets) {
            log_info "[dry-run] rm -rf ${t}"
        }
        _exit 0
        return 0
    }

    foreach ($t in $targets) {
        $destPath = if ([System.IO.Path]::IsPathRooted($t)) { $t } else { [System.IO.Path]::Combine($nativeBackupDir, $t) }
        try {
            Remove-Item -LiteralPath $destPath -Recurse -Force -ErrorAction Stop
            log_notice "Removed backup: ${destPath}"
        } catch {
            log_error "Failed to remove '${destPath}'"
            $ec++
        }
    }

    _exit $ec
    return $ec
}

function _clean_logs {
    _enter
    $ec = 0
    $log_files = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @($script:INIT_LOG_FILE, "$($script:DOTFILES_LOG_DIR)/main.log")) {
        $nf = _native_path $f
        if ([System.IO.File]::Exists($nf)) {
            [void]$log_files.Add($f)
        }
    }

    if ($log_files.Count -eq 0) {
        log_info "No log files found. Nothing to reset."
        _exit 0
        return 0
    }

    $msg = "This will reset (truncate) $($log_files.Count) log file(s):"
    foreach ($f in $log_files) { $msg += "`n    - $f" }

    $conf = _maintenance_confirm $msg
    if ($conf -ne 0) {
        _exit 130
        return 130
    }

    if ($script:DF_DRY_RUN -eq 1) {
        foreach ($f in $log_files) {
            log_info "[dry-run] : > ${f}"
        }
        _exit 0
        return 0
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    foreach ($f in $log_files) {
        $nf = _native_path $f
        try {
            [System.IO.File]::WriteAllText($nf, "", $utf8NoBom)
            log_notice "Reset log: ${f}"
        } catch {
            log_error "Failed to reset '${f}'"
            $ec++
        }
    }

    _exit $ec
    return $ec
}

function do_clean_backups {
    _enter
    log_info "Beginning backup cleanup."
    $ec = _clean_backups
    $script:DF_CLEAN_ERRORS = $ec
    if ($ec -eq 130) {
        if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
        exit 130
    }
    if ($ec -ne 0) {
        _exit $ec
        return $ec
    }
    log_info "Backup cleanup complete."
    _exit 0
    return 0
}

function do_clean_logs {
    _enter
    log_info "Beginning log reset."
    $ec = _clean_logs
    $script:DF_CLEAN_ERRORS = $ec
    if ($ec -eq 130) {
        if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
        exit 130
    }
    if ($ec -ne 0) {
        _exit $ec
        return $ec
    }
    log_info "Log reset complete."
    _exit 0
    return 0
}

function do_reset {
    _enter
    $ec = 0
    $failed = [System.Collections.Generic.List[string]]::new()
    $removed = 0

    log_info "Beginning reset."

    $m_srcs = @()
    $m_dests = @()
    $m_types = @()
    if ((_read_manifest_entries ([ref]$m_srcs) ([ref]$m_dests) ([ref]$m_types) "reset") -ne 0) {
        _exit 0
        return 0
    }

    $total = $m_dests.Count
    $affected = 0
    for ($i = 0; $i -lt $total; $i++) {
        if ($m_types[$i] -in @("symlink", "generate")) {
            $affected++
        }
    }

    if ($script:DF_INTERACTIVE -eq 1) {
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  This will remove ${affected} symlink/generated file(s).")
        [Console]::Error.WriteLine("  Copied files will NOT be affected.")
        [Console]::Error.WriteLine("")
        [Console]::Error.Write("  Continue? [Y/n] ")
        $reply = [Console]::In.ReadLine()
        if ($null -eq $reply) { $reply = "" }
        switch ($reply.ToLowerInvariant()) {
            { $_ -in @('y', 'yes', '') } {}
            default {
                log_warn "Reset cancelled by user."
                _exit 130
                if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
                exit 130
            }
        }
        [Console]::Error.WriteLine("")
    }

    for ($i = 0; $i -lt $total; $i++) {
        if ($m_types[$i] -in @("symlink", "generate")) {
            if ((remove_file $m_dests[$i]) -ne 0) {
                $ec++
                [void]$failed.Add($m_dests[$i])
            } else {
                $removed++
            }
        }
    }

    if ($ec -gt 0) {
        log_error "Reset finished with ${ec} error(s): ${removed} removed, $($failed.Count) failed."
        if ($failed.Count -gt 0) {
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("  Failed to remove:")
            foreach ($f in $failed) { [Console]::Error.WriteLine("    ✗ ${f}") }
            [Console]::Error.WriteLine("")
        }
    } else {
        log_info "Reset complete: ${removed} file(s) removed."
    }

    $script:DF_RESET_ERRORS = $ec
    _exit $ec
    return $ec
}

function do_repair {
    _enter
    $ec = 0
    $failed = [System.Collections.Generic.List[string]]::new()
    $removed = 0
    $repaired = 0

    log_info "Beginning repair."

    $m_srcs = @()
    $m_dests = @()
    $m_types = @()
    if ((_read_manifest_entries ([ref]$m_srcs) ([ref]$m_dests) ([ref]$m_types) "repair") -ne 0) {
        _exit 0
        return 0
    }

    $total = $m_dests.Count
    $broken_idx = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $total; $i++) {
        $dest = $m_dests[$i]
        $src  = $m_srcs[$i]
        $nativeDest = _native_path $dest
        switch ($m_types[$i]) {
            "symlink" {
                $isLink = _test_is_symlink $nativeDest
                $targetExists = if ($isLink) { _test_symlink_target_exists $nativeDest } else { $false }
                $linkTarget = ""
                if ($isLink) {
                    $item = Get-Item -LiteralPath $nativeDest -Force -ErrorAction SilentlyContinue
                    $rawT = if ($item.LinkTarget) { $item.LinkTarget } elseif ($item.Target) { [string]($item.Target | Select-Object -First 1) } else { "" }
                    if (-not [string]::IsNullOrEmpty($rawT) -and -not [System.IO.Path]::IsPathRooted($rawT) -and -not $rawT.StartsWith("/")) {
                        $rawT = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($nativeDest), $rawT)
                    }
                    $linkTarget = _canonical_path $rawT
                }
                if ($isLink -and $targetExists -and $linkTarget -eq (_canonical_path $src)) {
                    log_trace "Healthy symlink: ${dest}"
                    continue
                }
                $reason = if (-not $isLink -and -not [System.IO.File]::Exists($nativeDest) -and -not [System.IO.Directory]::Exists($nativeDest)) {
                    "missing"
                } elseif (-not $isLink) {
                    "not a symlink"
                } elseif (-not $targetExists) {
                    "dangling"
                } else {
                    "wrong target"
                }
                log_warn "Broken symlink [${reason}]: ${dest} (expected → ${src})"
                [void]$broken_idx.Add($i)
            }
            "generate" {
                $exists = [System.IO.File]::Exists($nativeDest)
                $nonEmpty = if ($exists) { ([System.IO.FileInfo]::new($nativeDest)).Length -gt 0 } else { $false }
                if ($exists -and $nonEmpty) {
                    log_trace "Healthy generated file: ${dest}"
                    continue
                }
                $reason = if ($exists) { "empty" } else { "missing" }
                log_warn "Broken generated file [${reason}]: ${dest}"
                [void]$broken_idx.Add($i)
            }
        }
    }

    $num_broken = $broken_idx.Count
    if ($num_broken -eq 0) {
        log_info "All entries healthy. Nothing to repair."
        _exit 0
        return 0
    }

    $plural = if ($num_broken -eq 1) { "y" } else { "ies" }
    log_info "Found ${num_broken} broken entr${plural}. Removing and re-installing…"

    foreach ($idx in $broken_idx) {
        if ((remove_file $m_dests[$idx]) -ne 0) {
            $ec++
            [void]$failed.Add($m_dests[$idx])
        } else {
            $removed++
        }
    }

    foreach ($idx in $broken_idx) {
        if ($failed.Contains($m_dests[$idx])) {
            continue
        }
        $src   = $m_srcs[$idx]
        $dest  = $m_dests[$idx]
        $ftype = $m_types[$idx]
        $label = "${src} → ${dest}"
        $canonModDir = (_canonical_path $script:DF_MODULE_DIR) + "/"
        $rel_src = if ($src.StartsWith($canonModDir)) { $src.Substring($canonModDir.Length) } else { $src }
        $cmd = if ($script:DF_MODULE_CMD.ContainsKey($rel_src)) { $script:DF_MODULE_CMD[$rel_src] } else { "" }

        if ((_install_entry $src $dest $ftype $cmd 1 $label) -eq 0) {
            $repaired++
        } else {
            $ec++
            [void]$failed.Add($dest)
        }
    }

    log_info "Repair complete: ${removed} removed, ${repaired} re-installed, ${ec} error(s)."
    if ($ec -gt 0 -and $failed.Count -gt 0) {
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  Failed:")
        foreach ($f in $failed) { [Console]::Error.WriteLine("    ✗ ${f}") }
        [Console]::Error.WriteLine("")
    }

    $script:DF_REPAIR_ERRORS = $ec
    _exit $ec
    return $ec
}

function do_remove {
    _enter
    $ec = 0
    $failed = [System.Collections.Generic.List[string]]::new()
    $removed = 0

    log_info "Beginning removal."

    $target_modules = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $script:DF_REMOVE_SET) {
        foreach ($mod in $script:DF_AVAILABLE_MODULES) {
            if ($mod -eq $entry -or $mod.StartsWith("${entry}/")) {
                [void]$target_modules.Add($mod)
            }
        }
    }

    if ($target_modules.Count -eq 0) {
        log_warn "No modules matched DF_REMOVE_SET. Nothing to remove."
        _exit 0
        return 0
    }

    $to_remove = [System.Collections.Generic.List[string]]::new()
    foreach ($mod in $target_modules) {
        $action = if ($script:DF_MODULE_ACTION.ContainsKey($mod)) { $script:DF_MODULE_ACTION[$mod] } else { "" }
        if ($action -in @("symlink", "generate")) {
            [void]$to_remove.Add($mod)
        } elseif ($action -eq "copy") {
            log_trace "Skipping copy module '${mod}' (copies are preserved)."
        }
    }

    if ($to_remove.Count -eq 0) {
        log_info "All matched modules are copies. Nothing to remove."
        _exit 0
        return 0
    }

    if ($script:DF_INTERACTIVE -eq 1) {
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("  This will remove $($to_remove.Count) file(s):")
        foreach ($mod in $to_remove) {
            $dest = if ($script:DF_MODULE_DEST.ContainsKey($mod)) { $script:DF_MODULE_DEST[$mod] } else { "" }
            [Console]::Error.WriteLine("    - ${dest}")
        }
        [Console]::Error.WriteLine("")
        [Console]::Error.Write("  Continue? [Y/n] ")
        $reply = [Console]::In.ReadLine()
        if ($null -eq $reply) { $reply = "" }
        switch ($reply.ToLowerInvariant()) {
            { $_ -in @('y', 'yes', '') } {}
            default {
                log_warn "Remove cancelled by user."
                _exit 130
                if (Get-Command release_lock -ErrorAction SilentlyContinue) { release_lock }
                exit 130
            }
        }
        [Console]::Error.WriteLine("")
    }

    foreach ($mod in $to_remove) {
        $dest = if ($script:DF_MODULE_DEST.ContainsKey($mod)) { $script:DF_MODULE_DEST[$mod] } else { "" }
        if ((remove_file $dest) -ne 0) {
            $ec++
            [void]$failed.Add($dest)
        } else {
            $removed++
        }
    }

    if ($ec -gt 0) {
        log_error "Removal finished with ${ec} error(s): ${removed} removed, $($failed.Count) failed."
        if ($failed.Count -gt 0) {
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("  Failed to remove:")
            foreach ($f in $failed) { [Console]::Error.WriteLine("    ✗ ${f}") }
            [Console]::Error.WriteLine("")
        }
    } else {
        log_info "Removal complete: ${removed} file(s) removed."
    }

    $script:DF_REMOVE_ERRORS = $ec
    _exit $ec
    return $ec
}
