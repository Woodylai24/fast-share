# Fast Share - SendTo script
# Usage: Called from Windows SendTo menu with file paths as arguments
param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$FilePaths
)

$ErrorActionPreference = "Stop"
$httpPort = 3000
$uploadUrl = "http://127.0.0.1:$httpPort/upload"

foreach ($filePath in $FilePaths) {
    # Handle quoted paths that come from SendTo
    $filePath = $filePath.Trim('"').Trim("'")
    
    if (-not (Test-Path $filePath)) {
        Write-Host "File not found: $filePath"
        continue
    }

    $fileName = [System.IO.Path]::GetFileName($filePath)
    
    try {
        # Read file bytes
        $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
        
        # Upload via HTTP with filename header
        $headers = @{
            'x-filename' = $fileName
        }
        
        Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $fileBytes -ContentType 'application/octet-stream'
        Write-Host "Sent: $fileName"
    } catch {
        Write-Host "Failed to send ${fileName}: $_"
    }
}

Write-Host ""
Write-Host "Done! Press any key to close..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
