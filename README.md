<h1 align="center">
  <br>
  <img src="assets/icons/valkery_icon.png" alt="Valkery Media Client" width="160">
  <br>
  Valkery Media Client
  <br>
</h1>

<h4 align="center">Cliente de medios unificado multiplataforma que fusiona la potencia del motor <b>Stremio</b> con el ecosistema <b>Jellyfin / Seerr</b>, interfaz fluida de cristal translúcido en color violeta, descargas offline y reproducción acelerada por hardware.</h4>

<p align="center">
  <a href="#características-principales">Características</a> •
  <a href="#arquitectura-híbrida">Arquitectura</a> •
  <a href="#visión-offline">Visión Offline</a> •
  <a href="#instalación-y-ejecución">Instalación</a> •
  <a href="#despliegue-en-servidor-web-docker">Servidor Web / Docker</a> •
  <a href="#licencia">Licencia</a>
</p>

<div align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27%2B-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.6%2B-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Theme-Valkery%20Violet%20%238B5CF6-8B5CF6" alt="Valkery Theme">
  <img src="https://img.shields.io/badge/Engine-Stremio%20Daemon%2011470-purple" alt="Stremio Engine">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20Android%20%7C%20Web-blue" alt="Multiplatform">
</div>

---

## Características Principales

* 🟣 **Motor Stremio Nativo**: Exploración fluida del catálogo Cinemeta y Addons comunitarios/privados (Torrentio, Anime, Cyberflix, etc.).
* ⚡ **Streaming Server Embebido (Zero-Setup)**: La aplicación detecta y ejecuta automáticamente el daemon local de Stremio en `http://127.0.0.1:11470` en segundo plano sin intervención manual del usuario.
* 📦 **Visión Offline Persistente**: Descarga de video en segundo plano junto con pistas de subtítulos (`.srt` / `.vtt`) y carátulas en almacenamiento local para reproducir sin conexión a internet.
* 🎛️ **Doble Vinculación Inteligente (Zero-Clutter)**:
  * Si solo usas Stremio: la aplicación se comporta como un cliente puro de Stremio (sin pantallas vacías ni avisos de Jellyfin).
  * Si conectas tu servidor Jellyfin: se activa la experiencia híbrida para acceder a tus bibliotecas y solicitudes con el stack Seerr.
* 👤 **Modo Invitado y Autenticado**: Explora catálogos y reproduce en local sin necesidad de crear cuenta; o inicia sesión con Stremio para sincronizar addons y progreso en la nube (`datastorePut/Get`).
* 🎬 **Reproducción Multimodal con MediaKit**:
  * Decodificación de video con aceleración por hardware (D3D11 / VAAPI / Metal / MediaCodec).
  * Picture-in-Picture (PiP) nativo y mini-reproductor flotante mientras navegas el catálogo.
  * Compatibilidad con reproductores externos (VLC / MPV) configurable en Ajustes.
* 🎨 **Diseño Moderno Glassmorphism**: Tarjetas translúcidas con desenfoque de fondo (`BackdropFilter`), gradientes cinematográficos y paleta violeta `#8B5CF6` por defecto.
* 🌐 **Soporte Web y Docker para Servidores**: Compilación Web PWA e imagen Docker multi-stage con Nginx optimizada para desplegar en tu propio VPS o servidor local.

---

## Arquitectura Híbrida

```
┌─────────────────────────────────────────────────────────────────┐
│               Valkery UI (Base Fladder Glassmorphism)           │
│         [ Stremio Discover ]  [ Descargas Offline ]  [ Ajustes ] │
└───────────────────────────────┬─────────────────────────────────┘
                                │
               ┌────────────────┴────────────────┐
               ▼                                 ▼
      [ Stremio Core Suite ]          [ Jellyfin / Seerr Stack ]
      • StremioApiService             • Client OpenAPI
      • CatalogAndStreamService       • User Session
      • StremioOfflineDownloadManager • Jellyseerr Requests
               │
               ▼
   [ Stremio Server Daemon ]
   http://127.0.0.1:11470
   (Auto-detectado y ejecutado en background)
               │
               ▼
   [ Reproductor MediaKit + Hardware Accel ]
   (Soporte de subtítulos, PiP y miniatura)
```

---

## Visión Offline

Valkery permite guardar cualquier película o episodio en tu dispositivo:
1. En la vista de detalle de cualquier contenido, pulsa el icono de **Descarga Offline** en la fuente deseada.
2. La app descargará de forma paralela el video por chunks, las pistas de subtítulos sincronizadas y los metadatos.
3. Ve a la pestaña **Offline**: podrás pausar, monitorear el progreso y reproducir tus archivos locales sin conexión a internet.
4. En la versión **Web**, la app dispara la descarga directa a través del navegador.

---

## Instalación y Ejecución

### Prerrequisitos
* [Flutter SDK](https://flutter.dev) (versión 3.27 o superior)
* Visual Studio 2022 con C++ (para Windows nativo)

### 1. Clonar el repositorio
```bash
git clone https://github.com/ValeryJL/Valkery-Stremio-Client.git
cd Valkery-Stremio-Client
```

### 2. Instalar dependencias
```bash
flutter pub get
```

### 3. Ejecutar pruebas unitarias
```bash
flutter test test/valkery_verification_test.dart
```

### 4. Ejecutar en Windows
```bash
flutter run -d windows
```

### 5. Ejecutar en el Navegador Web
```bash
flutter run -d chrome
```

---

## Despliegue en Servidor Web (Docker)

Puedes compilar y ejecutar Valkery en cualquier servidor casero (Home Server, Unraid, TrueNAS, VPS) con un solo comando:

```bash
# Construir la imagen Docker optimizada con Nginx Alpine
docker build -t valkery-media-client -f docker/Dockerfile .

# Correr el contenedor en el puerto 8080
docker run -d -p 8080:8080 --name valkery valkery-media-client
```

Luego accede desde cualquier dispositivo en tu red local abriendo `http://<IP_DE_TU_SERVIDOR>:8080`.

---

## Estructura Git y Mantenibilidad Upstream

Valkery mantiene un vínculo con el repositorio upstream de Fladder para incorporar futuras mejoras de la interfaz sin romper la integración de Stremio:

* **Origin**: `https://github.com/ValeryJL/Valkery-Stremio-Client.git`
* **Upstream**: `https://github.com/DonutWare/Fladder.git`

Para recibir actualizaciones futuras de upstream:
```bash
git fetch upstream
git merge upstream/main
```

---

## Licencia

Distribuido bajo la licencia GPL-3.0. Consulta `LICENSE` para más detalles.
