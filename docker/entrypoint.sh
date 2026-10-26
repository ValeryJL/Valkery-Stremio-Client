#!/bin/sh
set -e

echo "=========================================================="
echo " Starting Valkery Stremio Integrated Server"
echo " Web UI Port: 8080 | Stremio Daemon Port: 11470"
echo "=========================================================="

# Stremio environment defaults
export FFMPEG_BIN="${FFMPEG_BIN:-/usr/bin/ffmpeg}"
export FFPROBE_BIN="${FFPROBE_BIN:-/usr/bin/ffprobe}"
export APP_PATH="${APP_PATH:-/root/.stremio-server}"

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

# Update base href in index.html (always at root of build/web)
if [ -f "/usr/share/nginx/html/index.html" ]; then
  sed -i "s|<base href=\"[^\"]*\">|<base href=\"$WEBPATH\">|g" /usr/share/nginx/html/index.html
fi

# Start Native Streaming Server in background with keepalive loop
echo "[Valkery] Launching Native Streaming Server daemon..."
(
  cd /stremio
  while true; do
    ./stream-server -p 11470
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
