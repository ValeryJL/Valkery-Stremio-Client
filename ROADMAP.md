# 🚀 Roadmap & TODO Completo: Valkery Stremio Client

Este documento centraliza todas las tareas completadas, pendientes, diagnósticos técnicos y la hoja de ruta de arquitectura para continuar el desarrollo desde cualquier dispositivo.

---

## 📌 Estado Actual de Builds y CI (Multiplataforma)

- **Windows Desktop x64**: ✅ **Operativo / Exitoso** (`Valkery-Stremio-Client-Windows-x64` y `Valkery-Windows-Installer` publicados en CI).
- **Linux Desktop x64**: ✅ **Operativo / Exitoso** (`Valkery-Stremio-Client-Linux-x64` publicado en CI).
- **macOS Universal**: ✅ **Operativo / Exitoso** (`Valkery-Stremio-Client-macOS` publicado en CI).
- **Android APK**: ✅ **Operativo / Exitoso** (`Valkery-Stremio-Client-Android-APK` publicado en CI).
- **Web App**: 🔄 Desplegando en `https://stremio.valeryjl.com.ar/` con soporte de `hls.js` y selector avanzado de audio.

---

## 🔍 Diagnóstico Técnico: Reproducción Web en Chrome ("No anda el búfer") - [RESUELTO]

### Causa Identificada y Solución Aplicada:
1. **Falta de HLS nativo en Chrome Desktop**: Se inyectó **`hls.js`** en `web/index.html` con CDN y fallback local asegurando que `window.Hls` esté siempre disponible al arrancar la app.
2. **Encabezados CORS para segmentos HLS**: Se configuró `Access-Control-Expose-Headers: Content-Range, Accept-Ranges, Content-Length, Content-Type` en Nginx para que `hls.js` inspeccione metadatos de fragmentos sin restricciones.
3. **Manejo de Políticas de Autoplay**: Se ajustó `_errorSubscription` en `stremio_player_screen.dart` para interceptar restricciones de autoplay (`NotAllowedError` / interrupción por falta de interacción) sin provocar error fatal en la interfaz. Al pausarse por autoplay, el botón central de Play queda activo para arrancar al primer clic.
4. **Protección de Duración**: Si la duración o posición ya fue demuxada (`duration > 0`), los errores transitorios de búfer ya no abortan el reproductor ni cancelan las estadísticas de torrent.

---

## 🎵 Selector Avanzado de Pistas de Audio (Top Bar, Bottom Bar, Atajo 'A') - [COMPLETADO]

- [x] **Traducción y Mapeo Inteligente de Idiomas**: Mapeo automático de códigos de lenguaje (`spa`/`esp` -> `Español (Castellano)`, `lat`/`es-419` -> `Español (Latino)`, `eng` -> `Inglés`, `jpn` -> `Japonés`, etc.).
- [x] **Detección de Canales y Códecs**: Etiquetas dinámicas para Surround 5.1, 7.1, Estéreo, Dolby Atmos, TrueHD, Dolby Digital+ (E-AC-3), DTS, AAC y FLAC.
- [x] **Interfaz Moderna**: Tarjetas con efecto hover/tap, indicador de reproducción activo en morado `#8B5CF6`, icono de volumen y checkmark de selección.
- [x] **Acceso Rápido**:
  - En la **Barra Superior**: Botón directo de Audio (`IconsaxPlusLinear.audio_square`) y Subtítulos junto a la insignia de calidad.
  - En la **Barra Inferior**: Botón con resaltado de color si hay pista no predeterminada.
  - En el **Menú de Opciones** (engranaje).
  - Mediante **Atajo de Teclado**: Tecla **`A`** abre el selector de audio; tecla **`S`** o **`C`** abre el selector de subtítulos.

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
