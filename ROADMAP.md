# 🚀 Roadmap & TODO Completo: Valkery Stremio Client

Este documento centraliza todas las tareas completadas, pendientes, diagnósticos técnicos y la hoja de ruta de arquitectura para continuar el desarrollo desde cualquier dispositivo.

---

## 📌 Estado Actual de Builds y CI (Multiplataforma)

- **Windows Desktop x64**: ✅ **Operativo / Exitoso** (Ejecutable e Instalador Inno Setup compilando sin errores).
- **Linux Desktop x64**: ✅ **Operativo / Exitoso** (Corregido error de sintaxis en `stremio_detail_screen.dart`, artifact generado).
- **Android APK**: 🔄 Compilando en CI / Verificado soporte de streaming serverless.
- **macOS Universal**: 🔄 Compilando en CI.
- **Web App**: ✅ Desplegado en `https://stremio.valeryjl.com.ar/`.

---

## 🔍 Diagnóstico Técnico: Reproducción Web en Chrome ("No anda el búfer")

### ¿Qué está ocurriendo exactamente?
Al reproducir un torrent en el navegador (`https://stremio.valeryjl.com.ar/`):
1. El servidor de Stremio **está funcionando a la perfección**: descarga a alta velocidad (descargó más de 250 MB con 28 pares activos) y transcodifica el video MKV/H.264 a HLS (`/hlsv2/.../master.m3u8` y `playlist.m3u8` con segmentos `.ts` que responden HTTP 206).
2. La app detecta la duración y cantidad de pares ("me marca el tiempo y todo").
3. **La causa raíz en Web**: Google Chrome en escritorio **no soporta HLS (`.m3u8` / MPEG-TS) de forma nativa** en el tag `<video>` de HTML5 (solo Safari en macOS/iOS tiene demuxer HLS nativo). Cuando Chrome intenta leer los fragmentos `.ts` sin una librería puente, el elemento `<video>` emite un `MEDIA_ELEMENT_ERROR: Format error`.
4. El reproductor de Valkery recibe este error del navegador y activa el cartel de error con el botón *"Reintentar búfer"*.

### Solución Encolada para Web:
- Integrar **`hls.js`** en `web/index.html` o un puente JS interop para que Chrome/Firefox/Edge decodifiquen y reproduzcan los segmentos HLS `.ts` en tiempo real mediante Media Source Extensions (MSE).

---

## 🍎 Integración y Verificación de iOS: ¿Qué falta?

Para que Valkery funcione e instale en dispositivos Apple (iPhone / iPad), se deben cumplir las siguientes restricciones y requerimientos específicos de iOS:

### 1. Arquitectura del Motor Stremio en iOS (Sandbox)
- **Restricción de Apple**: En iOS, el sistema operativo prohíbe terminantemente ejecutar procesos demonio en segundo plano (`fork`/`exec` están bloqueados por el kernel de iOS). Por lo tanto, no es posible empaquetar ni correr `node / stremio-server` localmente en el dispositivo como se hace en Windows/Linux/Android.
- **Solución implementada**: Valkery debe operar en **Modo Servidor Remoto / LAN**:
  - Conectarse al motor central desplegado (ej. `https://stremio.valeryjl.com.ar` o el IP local de una PC en la misma red Wi-Fi: `http://192.168.x.x:11470`).
  - O utilizar enlaces directos de Debrid (RealDebrid / Torrentio RD) que son URLs HTTP directas compatibles nativamente con AVPlayer de iOS.

### 2. Dependencias Nativas de CocoaPods
- `pubspec.yaml` ya cuenta con el override de `media_kit_libs_ios_video`.
- Falta ejecutar la inicialización de Pods en el runner de macOS:
  ```bash
  cd ios && pod install --repo-update
  ```

### 3. Permisos en `ios/Runner/Info.plist`
Se deben declarar las siguientes claves requeridas por Apple:
- `NSAppTransportSecurity` -> `NSAllowsArbitraryLoads: true` (o excepciones de red local) para permitir streaming HTTP desde el servidor de Stremio local/remoto sin bloqueo de certificados autofirmados.
- `NSLocalNetworkUsageDescription`: Para descubrir servidores Stremio en la red Wi-Fi local mediante Bonjour o escaneo mDNS.
- `UIBackgroundModes` -> `audio`: Para mantener la reproducción de audio si se apaga la pantalla o cambia de app.

### 4. Firma de Código y Generación de IPA
- **Para desarrollo y pruebas caseras (Sideloading sin cuenta paga)**:
  - Generar el `.ipa` sin firmar (`flutter build ipa --no-codesign`) y cargarlo al dispositivo mediante **AltStore**, **SideStore**, **TrollStore** o **Sideloadly**.
- **Para TestFlight / App Store**:
  - Requiere membresía de Apple Developer Program ($99/año), certificados `Distribution` y perfiles de aprovisionamiento en los secretos de GitHub Actions (`APPLE_CERTIFICATE`, `PROVISIONING_PROFILE`).

### 5. Tarea en CI (`.github/workflows/multiplatform_build.yml`)
- Agregar el target de compilación de iOS en el job de macOS:
  ```yaml
  - name: Build iOS IPA (Unsigned)
    run: |
      flutter build ipa --no-codesign
      cd build/ios/iphoneos
      mkdir Payload && cp -r Runner.app Payload/
      zip -r Valkery-iOS-Unsigned.ipa Payload
  ```

---

## 📋 Lista Completa de Tareas (Roadmap)

### Fase 1: Completado Hoy ✅
- [x] Corrección de velocidad de descarga torrent en el reproductor (ya no se clava en `0 KB/s`).
- [x] Ocultar pestaña "Offline" en Web (exclusivo para apps nativas).
- [x] Switch "Forzar Modo Offline" en Ajustes para Desktop y Móvil.
- [x] Control del servicio Stremio: **detención automática del daemon** al entrar a modo offline (en Windows, Linux, macOS y Android) y **reactivación automática** al salir de modo offline.
- [x] Atenuación visual de la pestaña "Explorar" en modo offline con redirección a "Biblioteca".
- [x] Caché local de imágenes (`CachedNetworkImage`) para pósters y miniaturas sin conexión.
- [x] Biblioteca inteligente: títulos descargados en **color vibrante** con badge verde `OFFLINE / DESCARGADO`; títulos no descargados en **escala de grises** con badge `SOLO ONLINE`.
- [x] Filtro de Biblioteca "Todos" vs. "Offline".
- [x] Pantalla de detalles: episodios no descargados bloqueados y atenuados en offline; episodios descargados listos para reproducción local directa.
- [x] Corrección de error de compilación en Linux y Web (`276c23ba`).

### Fase 2: Pendiente para Retomar ⏳
- [ ] **Reproducción Web con `hls.js`**:
  - Incorporar soporte para transcodificación HLS en Chrome de escritorio mediante `hls.js` en `web/index.html`.
- [ ] **Rediseño de la Pantalla "Offline"**:
  - Agrupación por Series y Temporadas con tamaño en disco (MB/GB) y botón de reproducción directa.
  - Barra de espacio de almacenamiento ocupado y botón para liberar espacio/eliminar episodios vistos.
- [ ] **Sincronización de Historial Offline**:
  - Almacenar el progreso de reproducción en una cola local (`_offlineSyncQueue`) y enviarla a la API de Stremio (`datastorePut`) al recuperar internet.
- [ ] **Selector de Pistas de Audio**:
  - Menú modal en el reproductor para alternar entre idiomas de audio (Original, Español Latino, Castellano).
- [ ] **Subtítulos Externos en Web**:
  - Soporte de OpenSubtitles v3 inyectado como WebVTT en el tag de video web.
- [ ] **Limpieza de Código Jellyfin**:
  - Eliminar servicios, modelos y vistas heredadas de Jellyfin.
- [ ] **Pipeline de CI para iOS**:
  - Configurar CocoaPods, `Info.plist` y el build de IPA en GitHub Actions para pruebas en iPhone/iPad.
