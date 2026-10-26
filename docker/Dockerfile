# ==========================================
# Valkery Stremio Client - Web Server Dockerfile
# Integrated Flutter Web + Stremio Streaming Server Daemon
# ==========================================

# Stage 1: Build Flutter Web App
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Ensure git trusts directory
RUN git config --global --add safe.directory '*'

# Copy dependency definitions
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

# Copy source code and assets
COPY . .

# Build Flutter Web optimized with CanvasKit / HTML5
RUN flutter build web --release

# Stage 2: Serve with Nginx + Stremio Streaming Server (Node.js + FFmpeg)
FROM nginx:alpine

# Install Node.js, FFmpeg, Coreutils (for GNU df), and required tools for Stremio Streaming Server
RUN apk add --no-cache nodejs ffmpeg wget ca-certificates coreutils

# Copy Stremio Server runtime
WORKDIR /stremio
COPY --from=stremio/server:latest /stremio/server.js /stremio/server.js

# Copy built web artifacts
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy custom Nginx configuration
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables for Stremio Streaming Server
ENV FFMPEG_BIN=/usr/bin/ffmpeg
ENV FFPROBE_BIN=/usr/bin/ffprobe
ENV NO_CORS=1
ENV CASTING_DISABLED=1
ENV APP_PATH=/root/.stremio-server

VOLUME ["/root/.stremio-server"]

# 8080: Web UI | 11470: Stremio Streaming Server (HTTP) | 12470: Stremio Streaming Server (HTTPS)
EXPOSE 8080 11470 12470

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1:8080/ && \
      wget --quiet --tries=1 --spider http://127.0.0.1:11470/stats.json || exit 1

ENTRYPOINT ["/entrypoint.sh"]
