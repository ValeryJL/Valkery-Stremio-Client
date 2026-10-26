Add-Type -AssemblyName System.Drawing

$sourcePng = Join-Path $PWD "assets/icons/valkery_icon.png"
$sourceIco = Join-Path $PWD "assets/icons/valkery_icon.ico"

if (-not (Test-Path $sourcePng)) {
    Write-Error "Source icon not found at $sourcePng"
    exit 1
}

$srcImg = [System.Drawing.Image]::FromFile($sourcePng)
Write-Host "Source image loaded: $($srcImg.Width)x$($srcImg.Height)"

function Save-ResizedImage($width, $height, $destPath) {
    $dir = Split-Path -Parent $destPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $destBmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($destBmp)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $graphics.DrawImage($srcImg, $rect)
    $graphics.Dispose()

    $destBmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $destBmp.Dispose()
    Write-Host "Generated: $destPath ($width x $height)"
}

# 1. Root and Subdirectory Icons in icons/
Save-ResizedImage 1024 1024 "icons/valkery_notification_icon.png"

$iconDirs = @("icons/production", "icons/development")
foreach ($dir in $iconDirs) {
    Save-ResizedImage 1024 1024 "$dir/valkery_icon.png"
    Save-ResizedImage 1024 1024 "$dir/valkery_adaptive_icon.png"
    Save-ResizedImage 1024 1024 "$dir/valkery_icon_desktop.png"
    Save-ResizedImage 1024 1024 "$dir/valkery_macos_icon.png"
    Save-ResizedImage 1024 1024 "$dir/valkery_store_icon.png"
}
Save-ResizedImage 512 512 "icons/production/valkery_icon_512.png"
Copy-Item $sourceIco "icons/production/valkery_icon.ico" -Force
if (Test-Path "icons/development") {
    Copy-Item $sourceIco "icons/development/valkery_icon.ico" -Force
}

# 2. Android Mipmaps for all flavors
$androidFlavors = @("android/app/src/main/res", "android/app/src/production/res", "android/app/src/development/res")
$mipmapSizes = @{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
}

foreach ($flavor in $androidFlavors) {
    foreach ($name in $mipmapSizes.Keys) {
        $size = $mipmapSizes[$name]
        $folder = "$flavor/$name"
        Save-ResizedImage $size $size "$folder/ic_launcher.png"
        Save-ResizedImage $size $size "$folder/launcher_icon.png"
        Save-ResizedImage ($size * 2) ($size * 2) "$folder/ic_launcher_foreground.png"
        Save-ResizedImage $size $size "$folder/ic_launcher_monochrome.png"
    }
    Save-ResizedImage 512 512 "$flavor/../ic_launcher-playstore.png"
}

# 3. Web icons
Save-ResizedImage 192 192 "web/icons/Icon-192.png"
Save-ResizedImage 512 512 "web/icons/Icon-512.png"
Save-ResizedImage 192 192 "web/icons/Icon-maskable-192.png"
Save-ResizedImage 512 512 "web/icons/Icon-maskable-512.png"
Save-ResizedImage 64 64 "web/favicon.png"

# 4. Windows runner resources
Copy-Item $sourceIco "windows/runner/resources/app_icon.ico" -Force

$srcImg.Dispose()
Write-Host "[Valkery] All icons successfully regenerated from Valkery master logo!"
