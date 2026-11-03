#!/bin/sh
set -e

echo "=========================================================="
echo " Starting Valkery Stremio Integrated Server"
echo " Web UI Port: 8080 | Stremio Daemon Port: 11470"
echo "=========================================================="

# Install smart ffmpeg wrapper so embedded MKV subtitle extraction (*.vtt.tmp)
# flushes buffered cues immediately without blocking on 100% torrent download
if [ ! -f /usr/bin/ffmpeg.real ] && [ -f /usr/bin/ffmpeg ]; then
  mv /usr/bin/ffmpeg /usr/bin/ffmpeg.real
  cat > /usr/bin/ffmpeg <<'FFWRAP'
#!/bin/sh
LAST_ARG=""
for arg in "$@"; do
  LAST_ARG="$arg"
done

case "$LAST_ARG" in
  *.vtt.tmp)
    # Rebuild args inserting -flush_packets 1 right before the output file
     set -- "$@"
    NEW_ARGS=""
    i=1
    total=$#
    for arg in "$@"; do
      if [ "$i" -eq "$total" ]; then
        set -- "$@" -flush_packets 1 "$arg"
      else
        set -- "$@" "$arg"
      fi
      shift
      i=$((i + 1))
    done

    # Launch real ffmpeg in background session so it continues flushing cues as MKV downloads
    nohup timeout -s INT 1800 /usr/bin/ffmpeg.real "$@" >/dev/null 2>&1 < /dev/null &
    FF_PID=$!

    # Wait up to 2.5s for initial WEBVTT header + buffered cues to flush to disk
    waited=0
    while [ "$waited" -lt 25 ]; do
      if [ -s "$LAST_ARG" ]; then
        # Give it 400ms more to flush all currently buffered cues
        sleep 0.4
        break
      fi
      if ! kill -0 "$FF_PID" 2>/dev/null; then
        break
      fi
      sleep 0.1
      waited=$((waited + 1))
    done

    # Ensure valid WEBVTT file exists so rivulet-engine renames it and returns 200 OK
    if [ ! -s "$LAST_ARG" ]; then
      printf "WEBVTT\n\n" > "$LAST_ARG"
    fi
    exit 0
    ;;
  *)
    exec /usr/bin/ffmpeg.real "$@"
    ;;
esac
FFWRAP
  chmod +x /usr/bin/ffmpeg
fi

# Stremio environment defaults
export FFMPEG_BIN="${FFMPEG_BIN:-/usr/bin/ffmpeg}"
export FFPROBE_BIN="${FFPROBE_BIN:-/usr/bin/ffprobe}"
export APP_PATH="${APP_PATH:-/root/.stremio-server}"
export HTTP_PORT="${HTTP_PORT:-11470}"
export HTTPS_PORT="${HTTPS_PORT:-0}"
export RIVULET_ALLOWED_ORIGINS="*"
export NO_CORS="1"
export RIVULET_HLS_SESSION_TTL="${RIVULET_HLS_SESSION_TTL:-7200}"
export RIVULET_HLS_SESSION_OVERRIDES="${RIVULET_HLS_SESSION_OVERRIDES:-1}"
export RIVULET_HLS_SEGMENT_TIMEOUT="${RIVULET_HLS_SEGMENT_TIMEOUT:-60s}"
export RIVULET_HLS_PROBE_TIMEOUT="${RIVULET_HLS_PROBE_TIMEOUT:-45s}"
export RIVULET_TRANSCODE_TONEMAP="${RIVULET_TRANSCODE_TONEMAP:-hable}"

mkdir -p "$APP_PATH"

# Generate Jellyfin / Seerr client config.json from environment variables
mkdir -p /usr/share/nginx/html/assets/config
cat > /usr/share/nginx/html/assets/config/config.json <<EOF
{
  "baseUrl": "${BASE_URL:-}",
  "seerrBaseUrl": "${SEERR_BASE_URL:-}"
}
EOF

# Normalize FLADDER_WEBPATH (e.g. /fladder/)
WEBPATH=$(echo "${FLADDER_WEBPATH:-/}" | sed 's|^/*|/|; s|/*$|/|')
BUILD_HASH=$(date +%s)

# Update base href and cache-bust entrypoints in index.html
if [ -f "/usr/share/nginx/html/index.html" ]; then
  sed -i "s|<base href=\"[^\"]*\">|<base href=\"$WEBPATH\">|g" /usr/share/nginx/html/index.html
  sed -i "s|flutter_bootstrap\.js[^\"]*|flutter_bootstrap.js?v=$BUILD_HASH|g" /usr/share/nginx/html/index.html
fi

# Cache-bust main.dart.js in flutter_bootstrap.js to prevent CDN/Browser stale caches
if [ -f "/usr/share/nginx/html/flutter_bootstrap.js" ]; then
  sed -i "s|main\.dart\.js[^\"]*|main.dart.js?v=$BUILD_HASH|g" /usr/share/nginx/html/flutter_bootstrap.js
fi

# Start Native Streaming Server in background with keepalive loop
echo "[Valkery] Launching Native Streaming Server daemon with full CORS..."
(
  cd /stremio
  while true; do
    ./stream-server
    echo "[Valkery] Streaming server stopped, restarting in 1s..."
    sleep 1
  done
) &
STREMIO_PID=$!

# Trap signals for graceful shutdown of both services
cleanup() {
    echo "[Valkery] Stopping services..."
    kill -TERM "$STREMIO_PID" 2>/dev/null || true
    kill -TERM "$NGINX_PID" 2>/dev/null || true
    wait "$STREMIO_PID" 2>/dev/null || true
    wait "$NGINX_PID" 2>/dev/null || true
    exit 0
}

trap cleanup INT TERM

# Start Nginx Web Server in background and wait
echo "[Valkery] Launching Nginx Web Server on port 8080..."
nginx -g "daemon off;" &
NGINX_PID=$!

# Wait for Nginx (main process)
wait "$NGINX_PID"
