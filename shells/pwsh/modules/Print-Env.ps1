function Print-Env {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Name
    )
    
    $val = [Environment]::GetEnvironmentVariable($Name)
    if (-not $val) {
        Write-Warning "Environment variable '$Name' not found or is empty!"
        return
    }
    
    $val -split '[;]' | Where-Object { $_.Trim() }
}

function paths { Print-Env 'Path' }
