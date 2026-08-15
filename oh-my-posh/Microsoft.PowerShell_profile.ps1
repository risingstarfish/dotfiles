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

# Import-Module syntax-highlighting
Import-Module cd-extras
Import-Module LocationHistory
# Import-Module Terminal-Icons TODO: lazy load https://docs.jimbrig.com/NoClocksVaultNew/04-RESOURCES/Code/PowerShell/PowerShell---Lazy-Loading
# Import-Module psfzf
# Import-Module foil
# Import-Module chocolateyget
Import-Module PowerShellGet
Import-Module 7zip4powershell
Import-Module pspgp
Import-Module PSReadLine
# Import-Module posh-git #TODO: alias G


$script:LazyModules = @{
    'psfzf'         = @('fz', 'fzf', 'fzf-preview', 'fzf-ctrl-r', 'fzf-tab')
    'Terminal-Icons'= @('Get-ChildItemIcon', 'Get-ItemIcon', 'Get-PSDriveIcon', 'Get-FileSystemItemIcon')
}


Invoke-Expression (& { (zoxide init powershell | Out-String) })

# Keep last !!!
oh-my-posh init pwsh --config ~/oh-my-posh/themes/tiger.omp.json | Invoke-Expression