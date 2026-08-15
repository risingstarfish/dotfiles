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
    $sdkBin = "$sdkRoot\Bin\$sdkVer\x64"
    $sdkInc = "$sdkRoot\Include\$sdkVer"
    $sdkLib = "$sdkRoot\Lib\$sdkVer"
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