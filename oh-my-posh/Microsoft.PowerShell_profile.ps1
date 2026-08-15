. $env:USERPROFILE\oh-my-posh\scripts\Set-MSVC-Environment.ps1 # comment to not auto-load

. $env:USERPROFILE\oh-my-posh\scripts\AutoCd.ps1
. $env:USERPROFILE\oh-my-posh\scripts\Update-Modules.ps1
. $env:USERPROFILE\oh-my-posh\scripts\nproc.ps1

# hash functions
. $env:USERPROFILE\oh-my-posh\scripts\md5.ps1
. $env:USERPROFILE\oh-my-posh\scripts\sha1.ps1
. $env:USERPROFILE\oh-my-posh\scripts\sha256.ps1



if (-not $env:HOME) {
    $env:HOME = $env:USERPROFILE
}

# Keep last !!!
oh-my-posh init pwsh --config ~/oh-my-posh/themes/tiger.omp.json | Invoke-Expression