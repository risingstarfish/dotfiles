function Set-MSVC-Environment {
    $vsRoot = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
    $sdkRoot = "C:\Program Files (x86)\Windows Kits\10"
    
    if (-not (Test-Path $vsRoot) -or -not (Test-Path $sdkRoot)) {
        Write-Warning "[MSVC] Visual Studio BuildTools or Windows SDK not found."
        return
    }

    # Auto-detect latest Windows SDK version
    $sdkVer = Get-ChildItem "$sdkRoot\Include" -Directory | 
              Sort-Object Name -Descending | 
              Select-Object -First 1 | 
              Select-Object -ExpandProperty Name
    if (-not $sdkVer) { throw "[MSVC] No Windows SDK versions found." }

    # Auto-detect latest MSVC toolset (or override below)
    $msvcDir = Get-ChildItem "$vsRoot\VC\Tools\MSVC" -Directory | 
               Sort-Object { [version]$_.Name } -Descending | 
               Select-Object -First 1
    $msvcVer = $msvcDir.Name

    # Core paths
    $msvcBin = "$vsRoot\VC\Tools\MSVC\$msvcVer\bin\hostx64\x64"
    $sdkBin  = "$sdkRoot\Bin\$sdkVer\x64"
    $sdkInc  = "$sdkRoot\Include\$sdkVer"
    $sdkLib  = "$sdkRoot\Lib\$sdkVer"
    $msvcInc = "$vsRoot\VC\Tools\MSVC\$msvcVer\include"
    $msvcLib = "$vsRoot\VC\Tools\MSVC\$msvcVer\lib\x64"

    # Avoid duplicate PATH entries
    if ($env:PATH -notlike "*$msvcBin*" -and $env:PATH -notlike "*$sdkBin*") {
        $env:PATH = "$msvcBin;$sdkBin;$env:PATH"
    }

    # SDK & Toolchain routing variables
    $env:INCLUDE = "$msvcInc;$sdkInc\um;$sdkInc\ucrt;$sdkInc\shared;$env:INCLUDE"
    $env:LIB = "$msvcLib;$sdkLib\um\x64;$sdkLib\ucrt\x64;$env:LIB"
    $env:WindowsSdkDir = $sdkRoot
    $env:WindowsSdkVersion = $sdkVer
    $env:VCToolsVersion = $msvcVer
    $env:UniversalCRTSdkDir = $sdkRoot
    $env:UniversalCRTSdkVersion = $sdkVer
}

# Auto-load on profile startup
Set-MSVC-Environment

# zsh
Set-MSVC-Environment() {
    local vsRoot="C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
    local sdkRoot="C:\Program Files (x86)\Windows Kits\10"

    if [[ ! -d "$vsRoot" ]] || [[ ! -d "$sdkRoot" ]]; then
        echo "[MSVC] Visual Studio BuildTools or Windows SDK not found." >&2
        return 1
    fi

    # Auto-detect latest Windows SDK version
    local sdkVer
    sdkVer=$(find "$sdkRoot/Include" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -rV | head -n 1 | sed 's|.*/||')
    if [[ -z "$sdkVer" ]]; then
        echo "[MSVC] No Windows SDK versions found." >&2
        return 1
    fi

    # Auto-detect latest MSVC toolset
    local msvcDir msvcVer
    msvcDir=$(find "$vsRoot/VC/Tools/MSVC" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -rV | head -n 1)
    msvcVer=$(basename "$msvcDir")

    # Core paths (forward slashes are safe & preferred in Zsh/Git Bash)
    local msvcBin="$vsRoot/VC/Tools/MSVC/$msvcVer/bin/hostx64/x64"
    local sdkBin="$sdkRoot/Bin/$sdkVer/x64"
    local sdkInc="$sdkRoot/Include/$sdkVer"
    local sdkLib="$sdkRoot/Lib/$sdkVer"
    local msvcInc="$vsRoot/VC/Tools/MSVC/$msvcVer/include"
    local msvcLib="$vsRoot/VC/Tools/MSVC/$msvcVer/lib/x64"

    # ⚠️ CRITICAL: Use ';' for Windows tools, not ':'
    if [[ "$PATH" != *"$msvcBin"* ]] && [[ "$PATH" != *"$sdkBin"* ]]; then
        export PATH="$msvcBin;$sdkBin;$PATH"
    fi

    # SDK & Toolchain routing variables (Windows expects ';')
    export INCLUDE="$msvcInc;$sdkInc/um;$sdkInc/ucrt;$sdkInc/shared;$INCLUDE"
    export LIB="$msvcLib;$sdkLib/um/x64;$sdkLib/ucrt/x64;$LIB"
    export WindowsSdkDir="$sdkRoot"
    export WindowsSdkVersion="$sdkVer"
    export VCToolsVersion="$msvcVer"
    export VCToolsInstallDir="$vsRoot/VC/Tools/MSVC/$msvcVer"
    export UniversalCRTSdkDir="$sdkRoot"
    export UniversalCRTSdkVersion="$sdkVer"
}

# Auto-load on profile startup
Set-MSVC-Environment