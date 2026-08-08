function Test-InternetPing {
    <#
    .SYNOPSIS
    Tests internet connectivity using a simple ping.
    
    .DESCRIPTION
    Pings a specified server (default Google DNS: 8.8.8.8) once to verify network connectivity.
    Returns $true if successful, and $false if it fails.
    #>
    [CmdletBinding()]
    param (
        [string]$Server = "8.8.8.8"
    )

    return Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue
}