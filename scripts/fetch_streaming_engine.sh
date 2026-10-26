#!/usr/bin/env bash
set -e

PLATFORM="${1:-all}"
echo "[Valkery] Fetching latest streaming engine (Rivulet Go daemon) for: $PLATFORM"

fetch_tar_binary() {
    local asset_name="$1"
    local dest_file="$2"
    local direct_url="https://github.com/rivulet-kodi/rivulet-engine/releases/latest/download/${asset_name}"
    
    echo "Downloading $direct_url -> $dest_file"
    mkdir -p "$(dirname "$dest_file")"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    local download_ok=false
    if curl -sSL -f "$direct_url" -o "$temp_dir/$asset_name" 2>/dev/null; then
        if tar -xzf "$temp_dir/$asset_name" -C "$temp_dir" 2>/dev/null; then
            download_ok=true
            echo "Direct release asset download succeeded."
        fi
    fi

    if [ "$download_ok" = false ]; then
        echo "Direct URL failed or tar error, trying gh release download..."
        if command -v gh &>/dev/null; then
            gh release download -R rivulet-kodi/rivulet-engine --pattern "*${asset_name}*" -D "$temp_dir"
            tar -xzf "$temp_dir/$asset_name" -C "$temp_dir"
            download_ok=true
        else
            echo "Error: Failed to download $asset_name"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    if [ -f "$temp_dir/rivulet-engine" ]; then
        mv "$temp_dir/rivulet-engine" "$dest_file"
    elif [ -f "$temp_dir/stremio-server" ]; then
        mv "$temp_dir/stremio-server" "$dest_file"
    else
        find "$temp_dir" -type f -executable -exec mv {} "$dest_file" \;
    fi
    
    chmod +x "$dest_file"
    rm -rf "$temp_dir"
}

if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
    echo "--- Bundling Android ABIs ---"
    fetch_tar_binary "rivulet-engine_Android_arm64.tar.gz" "android/app/src/main/jniLibs/arm64-v8a/libstreamserver.so"
    fetch_tar_binary "rivulet-engine_Android_armv7.tar.gz" "android/app/src/main/jniLibs/armeabi-v7a/libstreamserver.so"
    fetch_tar_binary "rivulet-engine_Android_x86_64.tar.gz" "android/app/src/main/jniLibs/x86_64/libstreamserver.so"
    echo "Android streaming engine libraries ready in android/app/src/main/jniLibs/"
fi

if [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "all" ]; then
    echo "--- Bundling Linux x64 ---"
    fetch_tar_binary "rivulet-engine_Linux_x86_64.tar.gz" "build/linux/x64/release/bundle/stream-server"
fi

if [ "$PLATFORM" = "macos" ] || [ "$PLATFORM" = "all" ]; then
    echo "--- Bundling macOS Universal/ARM64 ---"
    APP_DIR=$(ls -d build/macos/Build/Products/Release-production/*.app 2>/dev/null | head -n1 || echo "")
    if [ -n "$APP_DIR" ]; then
        fetch_tar_binary "rivulet-engine_Darwin_arm64.tar.gz" "$APP_DIR/Contents/MacOS/stream-server"
    else
        fetch_tar_binary "rivulet-engine_Darwin_arm64.tar.gz" "build/macos/Build/Products/Release-production/Valkery.app/Contents/MacOS/stream-server"
    fi
fi

if [ "$PLATFORM" = "docker" ]; then
    echo "--- Bundling Docker Server ---"
    fetch_tar_binary "rivulet-engine_Linux_x86_64.tar.gz" "/stremio/stream-server"
fi

echo "[Valkery] Streaming engine setup completed for: $PLATFORM"
