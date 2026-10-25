# ==========================================
# Valkery Stremio Client - Web Server Dockerfile
# ==========================================

# Stage 1: Build Flutter Web App
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Copy dependency definitions
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

# Copy source code and assets
COPY . .

# Build Flutter Web optimized with CanvasKit / HTML5
RUN flutter build web --release --wasm

# Stage 2: Serve with lightweight Nginx Alpine
FROM nginx:alpine

# Copy built web artifacts
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy custom Nginx configuration
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
