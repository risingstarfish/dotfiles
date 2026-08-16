function Set-MSVC-Environment {
    [CmdletBinding()]
    param(
        [ValidateSet('x64', 'x86', 'arm64')]
        [string]$Architecture = 'x64',
        
        [ValidateSet('User', 'Machine', 'Process')]
        [string]$Scope = 'User',
        
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'

    # Resolve architecture from env if not explicitly provided
    if (-not $Architecture) {
        $Architecture = switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { 'x64' }
            'ARM64' { 'arm64' }
            'x86' { 'x86' }
            default { 'x64' }
        }
    }

    # Locate VS Installation
    $vsBases = @("C:\Program Files (x86)\Microsoft Visual Studio", "C:\Program Files\Microsoft Visual Studio")
    $vsDir = $null
    foreach ($base in $vsBases) {
        if (Test-Path $base) {
            $vsDir = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName "BuildTools") } |
            Sort-Object Name -Descending | Select-Object -First 1
            if ($vsDir) { break }
        }
    }
    if (-not $vsDir) { Write-Warning "Visual Studio BuildTools not found in expected locations."; return }

    $buildToolsRoot = Join-Path $vsDir.FullName "BuildTools"
    if (-not (Test-Path $buildToolsRoot)) { Write-Warning "BuildTools directory not found: $buildToolsRoot"; return }

    # Auto-detect latest MSVC toolset 
    $msvcToolsPath = Join-Path $buildToolsRoot "VC\Tools\MSVC"
    if (-not (Test-Path $msvcToolsPath)) { Write-Warning "MSVC tools directory not found: $msvcToolsPath"; return }

    $msvcVer = (Get-ChildItem $msvcToolsPath -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]($_.Name -split '\+')[0] } catch { [version]"0.0.0.0" } } -Descending).Name[0]
    if (-not $msvcVer) { Write-Warning "No MSVC toolset versions found."; return }

    # Auto-detect latest Windows SDK
    $sdkBase = "C:\Program Files (x86)\Windows Kits\10"
    $sdkIncludePath = Join-Path $sdkBase "Include"
    if (-not (Test-Path $sdkIncludePath)) { Write-Warning "Windows SDK Include directory not found: $sdkIncludePath"; return }

    $sdkVer = (Get-ChildItem $sdkIncludePath -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]$_.Name } catch { [version]"0.0.0.0" } } -Descending).Name[0]
    if (-not $sdkVer) { Write-Warning "No Windows SDK versions found."; return }

    # Construct exact paths
    $msvcBin = Join-Path $msvcToolsPath "$msvcVer\bin\Host$Architecture\$Architecture"
    $msvcInc = Join-Path $msvcToolsPath "$msvcVer\include"
    $msvcLib = Join-Path $msvcToolsPath "$msvcVer\lib\$Architecture"
    $sdkInc = Join-Path $sdkBase "Include\$sdkVer"
    $sdkLib = Join-Path $sdkBase "Lib\$sdkVer"

    # 🔍 VALIDATE CRITICAL PATHS (Collect ALL failures before failing)
    $missingCritical = @()
    $corePaths = @($msvcBin, $msvcInc, $msvcLib, $sdkInc, $sdkLib)
    foreach ($p in $corePaths) {
        if (-not (Test-Path $p)) { $missingCritical += "Core: $p" }
    }
    # Safely check cl.exe only if bin directory exists
    if (Test-Path $msvcBin) {
        if (-not (Test-Path (Join-Path $msvcBin "cl.exe"))) {
            $missingCritical += "Compiler: $msvcBin\cl.exe"
        }
    }

    if ($missingCritical.Count -gt 0) {
        $errorMsg = "Missing critical MSVC paths (validation failed):`n" + ($missingCritical | ForEach-Object { "  $_" })
        throw $errorMsg
    }

    # Build final path arrays
    $incPaths = ($msvcInc, "$sdkInc\um", "$sdkInc\ucrt", "$sdkInc\shared") | Sort-Object -Unique
    $libPaths = ($msvcLib, "$sdkLib\um\$Architecture", "$sdkLib\ucrt\$Architecture") | Sort-Object -Unique

    # validate inc and lib paths
    $missingInc = @()
    $missingLib = @()

    foreach ($p in $incPaths) {
        if (-not (Test-Path $p)) { $missingInc += $p }
    }
    foreach ($p in $libPaths) {
        if (-not (Test-Path $p)) { $missingLib += $p }
    }

    if ($missingInc.Count -gt 0 -or $missingLib.Count -gt 0) {
        $errorMsg = "Missing required paths (validation failed):`n"
        if ($missingInc.Count -gt 0) {
            $errorMsg += "  INCLUDE:`n" + ($missingInc | ForEach-Object { "    $_" }) + "`n"
        }
        if ($missingLib.Count -gt 0) {
            $errorMsg += "  LIB:`n" + ($missingLib | ForEach-Object { "    $_" }) + "`n"
        }
        throw $errorMsg.TrimEnd()
    }

    # idempotency check
    $normalizePath = { param([string[]]$arr) $arr | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ } | Sort-Object }
    $currentInc = & $normalizePath ($env:INCLUDE -split ';')
    $currentLib = & $normalizePath ($env:LIB -split ';')
    $newInc     = & $normalizePath $incPaths
    $newLib     = & $normalizePath $libPaths

    # Strict comparison: must match in count AND content
    $incMatch = ($currentInc.Count -eq $newInc.Count) -and ($currentInc -join ';' -eq $newInc -join ';')
    $libMatch = ($currentLib.Count -eq $newLib.Count) -and ($currentLib -join ';' -eq $newLib -join ';')

    # Helper to format paths with newlines
    $formatPaths = { param([string[]]$arr) if ($arr.Count -eq 0) { "    (none)" } else { ($arr | ForEach-Object { "    $_" }) -join "`n" } }

    if ($incMatch -and $libMatch) {
        Write-Host "[MSVC] Environment already up-to-date." -ForegroundColor Cyan
        Write-Host "Current INCLUDE:`n$(& $formatPaths $currentInc)" -ForegroundColor DarkGray
        Write-Host "Current LIB:`n$(& $formatPaths $currentLib)" -ForegroundColor DarkGray
        return
    }

    # apply env
    try {
        [Environment]::SetEnvironmentVariable("INCLUDE", ($newInc -join ';'), $Scope)
        [Environment]::SetEnvironmentVariable("LIB", ($newLib -join ';'), $Scope)
        $env:INCLUDE = $newInc -join ';'
        $env:LIB = $newLib -join ';'

        Write-Host "[MSVC] Environment updated successfully." -ForegroundColor Green
        Write-Host "   Toolchain: $msvcVer | SDK: $sdkVer | Arch: $Architecture | Scope: $Scope"

        if (-not $incMatch) {
            Write-Host "Old INCLUDE:`n$(& $formatPaths $currentInc)" -ForegroundColor Yellow
            Write-Host "New INCLUDE:`n$(& $formatPaths $newInc)" -ForegroundColor Green
        } else {
            Write-Host "Current INCLUDE:`n$(& $formatPaths $currentInc)" -ForegroundColor DarkGray
        }
        if (-not $libMatch) {
            Write-Host "Old LIB:`n$(& $formatPaths $currentLib)" -ForegroundColor Yellow
            Write-Host "New LIB:`n$(& $formatPaths $newLib)" -ForegroundColor Green
        } else {
            Write-Host "Current LIB:`n$(& $formatPaths $currentLib)" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Error "Failed to update environment variables: $_"
        throw
    }
}

# manual trigger
Set-Alias -Name set-vc -Value Set-MSVC-Environment -Scope Global
# startup
# Set-MSVC-Environment
