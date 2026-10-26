param (
    [string]$TargetDir = "build\windows\x64\runner\Release"
)

Write-Host "[Valkery] Fetching latest Windows streaming engine from GitHub releases..."
try {
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    }

    $zipPath = Join-Path $env:TEMP "stream-server.zip"
    $extractPath = Join-Path $env:TEMP "stream-server-extract"

    if (Test-Path $extractPath) {
        Remove-Item -Recurse -Force $extractPath
    }

    $downloadUrl = "https://github.com/rivulet-kodi/rivulet-engine/releases/latest/download/rivulet-engine_Windows_x86_64.zip"
    Write-Host "Downloading $downloadUrl..."

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Warning "Direct download failed, attempting via GitHub API..."
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/rivulet-kodi/rivulet-engine/releases/latest' -Headers @{'User-Agent'='PowerShell'}
        $asset = $release.assets | Where-Object { $_.name -like '*Windows_x86_64*.zip' } | Select-Object -First 1
        if (-not $asset) {
            throw "Could not find Windows x86_64 asset in release."
        }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $binary = Get-ChildItem -Path $extractPath -Filter "*.exe" -Recurse | Select-Object -First 1
    if ($binary) {
        $destPath = Join-Path $TargetDir "stream-server.exe"
        Copy-Item -Path $binary.FullName -Destination $destPath -Force
        Write-Host "[Valkery] Successfully bundled stream-server.exe to $destPath"
    } else {
        throw "No .exe found in extracted stream-server archive."
    }

    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $extractPath -ErrorAction SilentlyContinue
} catch {
    Write-Error "Failed to fetch streaming engine: $_"
    exit 1
}
