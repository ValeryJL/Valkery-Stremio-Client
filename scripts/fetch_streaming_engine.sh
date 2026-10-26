#!/usr/bin/env bash
set -e

PLATFORM="${1:-all}"
echo "[Valkery] Fetching latest streaming engine (Rivulet Go daemon) for: $PLATFORM"

RELEASE_JSON=$(curl -sSL "https://api.github.com/repos/M0Rf30/stremio-server-go/releases/latest")

fetch_tar_binary() {
    local asset_pattern="$1"
    local dest_file="$2"
    local url=$(echo "$RELEASE_JSON" | grep -o "https://[^\"]*${asset_pattern}" | head -n1)
    
    if [ -z "$url" ]; then
        echo "Error: Asset matching $asset_pattern not found in release."
        return 1
    fi
    
    echo "Downloading $url -> $dest_file"
    mkdir -p "$(dirname "$dest_file")"
    local temp_dir=$(mktemp -d)
    curl -sSL "$url" | tar -xz -C "$temp_dir"
    
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
    fetch_tar_binary "Android_arm64\.tar\.gz" "android/app/src/main/jniLibs/arm64-v8a/libstreamserver.so"
    fetch_tar_binary "Android_armv7\.tar\.gz" "android/app/src/main/jniLibs/armeabi-v7a/libstreamserver.so"
    fetch_tar_binary "Android_x86_64\.tar\.gz" "android/app/src/main/jniLibs/x86_64/libstreamserver.so"
    echo "Android streaming engine libraries ready in android/app/src/main/jniLibs/"
fi

if [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "all" ]; then
    echo "--- Bundling Linux x64 ---"
    fetch_tar_binary "Linux_x86_64\.tar\.gz" "build/linux/x64/release/bundle/stream-server"
fi

if [ "$PLATFORM" = "macos" ] || [ "$PLATFORM" = "all" ]; then
    echo "--- Bundling macOS Universal/ARM64 ---"
    fetch_tar_binary "Darwin_arm64\.tar\.gz" "build/macos/Build/Products/Release-production/Fladder.app/Contents/MacOS/stream-server"
fi

if [ "$PLATFORM" = "docker" ]; then
    echo "--- Bundling Docker Server ---"
    fetch_tar_binary "Linux_x86_64\.tar\.gz" "/stremio/stream-server"
fi

echo "[Valkery] Streaming engine setup completed for: $PLATFORM"
