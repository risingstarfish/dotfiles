. $env:USERPROFILE\Documents\Powershell\Scripts\Set-MSVC-Environment.ps1
. $env:USERPROFILE\Documents\Powershell\Scripts\Update-Modules.ps1
##. $env:USERPROFILE\oh-my-posh\scripts\AutoCd.ps1
. $env:USERPROFILE\Documents\Powershell\Scripts\Print-Env.ps1
. $env:USERPROFILE\Documents\Powershell\Scripts\nproc.ps1
# hash functions
. $env:USERPROFILE\Documents\Powershell\Scripts\sha256.ps1
. $env:USERPROFILE\Documents\Powershell\Scripts\sha1.ps1
. $env:USERPROFILE\Documents\Powershell\Scripts\md5.ps1



if (-not $env:HOME) {
    $env:HOME = $env:USERPROFILE
}

if ($env:TMUX -or $env:PSMUX) {
    Remove-Item Function:\Set-Location -ErrorAction SilentlyContinue
}

Import-Module syntax-highlighting
Import-Module cd-extras
Import-Module LocationHistory
#Import-Module Terminal-Icons
Import-Module psfzf
# Import-Module foil
# Import-Module chocolateyget
Import-Module PowerShellGet
Import-Module 7zip4powershell
#Import-Module pspgp
Import-Module PSReadLine

Set-Alias G git -Force


Invoke-Expression (& { (zoxide init powershell | Out-String) })



# Keep last !!!
oh-my-posh init pwsh --config ~/.oh-my-posh/themes/tiger.omp.json | Invoke-Expression

#psmux