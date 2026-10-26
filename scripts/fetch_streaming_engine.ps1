param (
    [string]$TargetDir = "build\windows\x64\runner\Release"
)

Write-Host "[Valkery] Fetching latest Windows streaming engine from GitHub releases..."
try {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/M0Rf30/stremio-server-go/releases/latest' -Headers @{'User-Agent'='PowerShell'}
    $asset = $release.assets | Where-Object { $_.name -like '*Windows_x86_64*.zip' } | Select-Object -First 1

    if (-not $asset) {
        Write-Error "Could not find Windows x86_64 asset in latest release."
        exit 1
    }

    Write-Host "Downloading $($asset.name) from $($asset.browser_download_url)..."
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    }

    $zipPath = Join-Path $env:TEMP "stream-server.zip"
    $extractPath = Join-Path $env:TEMP "stream-server-extract"

    if (Test-Path $extractPath) {
        Remove-Item -Recurse -Force $extractPath
    }

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $binary = Get-ChildItem -Path $extractPath -Filter "*.exe" -Recurse | Select-Object -First 1
    if ($binary) {
        $destPath = Join-Path $TargetDir "stream-server.exe"
        Copy-Item -Path $binary.FullName -Destination $destPath -Force
        Write-Host "[Valkery] Successfully bundled stream-server.exe to $destPath"
    } else {
        Write-Error "No .exe found in extracted stream-server archive."
        exit 1
    }

    Remove-Item -Force $zipPath
    Remove-Item -Recurse -Force $extractPath
} catch {
    Write-Error "Failed to fetch streaming engine: $_"
    exit 1
}
