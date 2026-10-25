import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum StremioServerState {
  offline,
  starting,
  online,
  error,
}

class StremioServerStatus {
  final StremioServerState state;
  final String serverUrl;
  final String? version;
  final int activeTorrents;
  final String? errorMessage;

  const StremioServerStatus({
    required this.state,
    required this.serverUrl,
    this.version,
    this.activeTorrents = 0,
    this.errorMessage,
  });

  bool get isOnline => state == StremioServerState.online;
}

/// Manages detection, background daemon lifecycle, and status monitoring
/// of the official Stremio Streaming Server (default: http://127.0.0.1:11470).
class StremioServerProcessManager {
  static const String defaultServerUrl = 'http://127.0.0.1:11470';

  final http.Client _httpClient;
  String _serverUrl;
  Process? _serverProcess;
  Timer? _healthCheckTimer;
  StremioServerStatus _status;

  final _statusController = StreamController<StremioServerStatus>.broadcast();
  Stream<StremioServerStatus> get statusStream => _statusController.stream;
  StremioServerStatus get currentStatus => _status;
  String get serverUrl => _serverUrl;

  StremioServerProcessManager({
    String? serverUrl,
    http.Client? httpClient,
  })  : _serverUrl = serverUrl ?? defaultServerUrl,
        _httpClient = httpClient ?? http.Client(),
        _status = StremioServerStatus(
          state: StremioServerState.offline,
          serverUrl: serverUrl ?? defaultServerUrl,
        );

  /// Configures a custom Stremio Server URL (e.g. LAN server or VPS).
  void setCustomServerUrl(String url) {
    _serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    checkHealth();
  }

  /// Starts polling health status and attempts to spawn background daemon if offline.
  Future<void> initialize({bool autoStartLocalDaemon = true}) async {
    await checkHealth();

    if (!_status.isOnline && autoStartLocalDaemon && !kIsWeb) {
      await startLocalServer();
    }

    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => checkHealth(),
    );
  }

  /// Pings http://127.0.0.1:11470/stats.json to detect server availability.
  Future<StremioServerStatus> checkHealth() async {
    try {
      final uri = Uri.parse('$_serverUrl/stats.json');
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(milliseconds: 1800));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        var torrentsCount = 0;
        String? ver;

        if (decoded is Map<String, dynamic>) {
          ver = (decoded['version'] ?? decoded['engineVersion'])?.toString();
          if (decoded['torrents'] is List) {
            torrentsCount = (decoded['torrents'] as List).length;
          }
        }

        _status = StremioServerStatus(
          state: StremioServerState.online,
          serverUrl: _serverUrl,
          version: ver ?? 'v4.x',
          activeTorrents: torrentsCount,
        );
      } else {
        _status = StremioServerStatus(
          state: StremioServerState.offline,
          serverUrl: _serverUrl,
        );
      }
    } catch (_) {
      _status = StremioServerStatus(
        state: StremioServerState.offline,
        serverUrl: _serverUrl,
      );
    }

    _statusController.add(_status);
    return _status;
  }

  /// Attempts to locate and spawn the official Stremio runtime / service daemon.
  Future<bool> startLocalServer({String? executableOverride}) async {
    if (kIsWeb) return false;
    // Check health first to avoid spawning if already running
    final initialCheck = await checkHealth();
    if (initialCheck.isOnline) return true;

    _status = StremioServerStatus(
      state: StremioServerState.starting,
      serverUrl: _serverUrl,
    );
    _statusController.add(_status);

    final exePath = executableOverride ?? _detectInstalledStremioExecutable();
    if (exePath == null) {
      _status = StremioServerStatus(
        state: StremioServerState.offline,
        serverUrl: _serverUrl,
        errorMessage: 'Stremio Streaming Server no encontrado en el sistema.',
      );
      _statusController.add(_status);
      return false;
    }

    try {
      final exeFile = File(exePath);
      final exeDir = exeFile.parent.path;
      final serverJs = File('$exeDir${Platform.pathSeparator}server.js');

      List<String> args;
      if (serverJs.existsSync()) {
        args = [serverJs.path];
      } else {
        args = ['--port=11470'];
      }

      final process = await Process.start(
        exePath,
        args,
        workingDirectory: exeDir,
        mode: ProcessStartMode.detached,
      );
      _serverProcess = process;

      // Allow 2.5 seconds for socket bind and verify
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final health = await checkHealth();
      return health.isOnline;
    } catch (e) {
      _status = StremioServerStatus(
        state: StremioServerState.error,
        serverUrl: _serverUrl,
        errorMessage: 'Error al iniciar motor local: $e',
      );
      _statusController.add(_status);
      return false;
    }
  }

  /// Locates standard installation paths for Stremio headless server / runtime.
  /// NOTE: We deliberately EXCLUDE `stremio.exe` because that launches the Qt desktop GUI.
  static String? _detectInstalledStremioExecutable() {
    if (kIsWeb) return null;

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? '';
      final candidates = [
        // Stremio 4 headless Node runtime with server.js
        '$localAppData\\Programs\\LNV\\Stremio-4\\stremio-runtime.exe',
        '$localAppData\\Programs\\LNV\\Stremio-4\\server.exe',
        '$localAppData\\Programs\\Stremio\\stremio-runtime.exe',
        '$localAppData\\Programs\\Stremio\\server.exe',
        '$localAppData\\Stremio\\stremio-runtime.exe',
        '$programFiles\\Stremio\\stremio-runtime.exe',
        '$programFiles\\Stremio\\server.exe',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
    } else if (Platform.isLinux) {
      final candidates = [
        '/usr/bin/stremio-service',
        '/usr/bin/stremio-runtime',
        '/opt/stremio/stremio-runtime',
        '/var/lib/flatpak/exports/bin/com.stremio.Service',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
    } else if (Platform.isMacOS) {
      final candidates = [
        '/Applications/Stremio.app/Contents/MacOS/stremio-runtime',
        '/Applications/Stremio.app/Contents/MacOS/stremio-service',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
    }
    return null;
  }

  /// Stops health monitoring and terminates the spawned background process if any.
  Future<void> dispose() async {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    final proc = _serverProcess;
    _serverProcess = null;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
    }

    await _statusController.close();
  }
}
