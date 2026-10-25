# Valkery Stremio Client

**Valkery Stremio Client** es un reproductor multimedia universal multiplataforma (**Windows, Linux, macOS, Android, iOS**) y cliente compatible con el ecosistema **Stremio**, construido en **Flutter (Dart)**.

## Características Principales

- **Reproductor Universal Híbrido (`libVLC` + VLC Nativo)**:
  - Reproducción integrada con soporte para `.mkv`, `.mp4`, HEVC/H.265, múltiples pistas de audio y subtítulos `.srt`/`.vtt`.
  - Lanzador de **1 clic hacia VLC Nativo Externo** con sincronización en tiempo real del progreso de reproducción vía interfaz HTTP local de VLC.
- **Doble Modo Serverless (Streaming Secuencial + Descarga Local Multi-Temporada)**:
  - **Modo Stream ("Ver Ahora")**: Servidor local HTTP Range (`206 Partial Content`) sobre loopback (`127.0.0.1`) para reproducción inmediata estilo Stremio.
  - **Modo Descarga Offline ("Guardar en Dispositivo")**: Selector de múltiples temporadas, episodios específicos e inspector de archivos internos de torrents (`fileIdx`) para reproducción sin conexión.
- **Sincronización con Cuenta de Stremio (`api.strem.io`)**:
  - Inicio de sesión (`login`), importación automática de Addons instalados (`addonCollectionGet`: **Torrentio**, **Cinemeta**, **OpenSubtitles v3**, etc.).
  - **Sincronización Automática del Historial de Visualización (`datastorePut` / `datastoreGet` en `libraryItem`)**: Actualiza el segundo exacto (`timeOffset`), duración y capítulos marcados como vistos tanto en **Streaming** como al reproducir capítulos descargados **Offline**.
- **Buscadores e Indexadores Integrados**:
  - Catálogo oficial **Cinemeta**, **Torrentio** (multi-tracker: YTS, 1337x, EZTV, RARBG, TorrentGalaxy, TPB), **Nyaa.si** (Anime RSS) y **Apibay**.
- **Diseño Multiplataforma Adaptativo (Desktop & Mobile)**:
  - Paleta **Valkery Steel/Slate** (`#323943` / `#21252B` en Modo Oscuro y `#F3F4F6` en Modo Claro, acento `#5E81AC`, geometría rectangular de 4px e icono minimalista **"V"**).
  - Barra lateral fija en Desktop y navegación táctil inferior en Mobile.
