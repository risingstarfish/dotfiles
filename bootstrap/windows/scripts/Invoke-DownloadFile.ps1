function Invoke-DownloadFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxAttempts = 10    )

    if (-not (Test-Path $Destination)) {
        Write-Host "         -> Downloading $Title..." -ForegroundColor DarkGray
        
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                # -ErrorAction Stop ensures that any HTTP error triggers the catch block
                Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
                
                # If we reach this line, the download succeeded. Break out of the loop.
                Write-Host "         -> $Title downloaded successfully." -ForegroundColor Green
                break 
            }
            catch {
                if ($attempt -lt $MaxAttempts) {
                    Write-Host "         -> Attempt $attempt failed for $Title. Retrying in 3 seconds... ($_)" -ForegroundColor DarkYellow
                    Start-Sleep -Seconds 3
                }
                else {
                    Write-Host "         -> Failed to download $Title after $MaxAttempts attempts. $_" -ForegroundColor Red
                    Write-Host "         -> Exiting..." -ForegroundColor Red
                    exit 1
                }
            }
        }
    }
    else {
        Write-Host "         -> $Title already exists at $Destination. Skipping download." -ForegroundColor DarkGray
    }
}