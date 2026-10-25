import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/stremio/download_task.dart';
import '../../models/stremio/stremio_user.dart';
import '../../models/stremio/watch_history_item.dart';

class AppPreferences {
  final bool darkMode;
  final String vlcExecutablePath;
  final String downloadDirectory;
  final String preferredSubtitleLang;
  final String preferredQuality;
  final bool autoSyncStremioHistory;

  const AppPreferences({
    this.darkMode = true,
    this.vlcExecutablePath = '',
    this.downloadDirectory = '',
    this.preferredSubtitleLang = 'spa',
    this.preferredQuality = '1080p',
    this.autoSyncStremioHistory = true,
  });

  AppPreferences copyWith({
    bool? darkMode,
    String? vlcExecutablePath,
    String? downloadDirectory,
    String? preferredSubtitleLang,
    String? preferredQuality,
    bool? autoSyncStremioHistory,
  }) {
    return AppPreferences(
      darkMode: darkMode ?? this.darkMode,
      vlcExecutablePath: vlcExecutablePath ?? this.vlcExecutablePath,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      preferredSubtitleLang:
          preferredSubtitleLang ?? this.preferredSubtitleLang,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      autoSyncStremioHistory:
          autoSyncStremioHistory ?? this.autoSyncStremioHistory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'darkMode': darkMode,
      'vlcExecutablePath': vlcExecutablePath,
      'downloadDirectory': downloadDirectory,
      'preferredSubtitleLang': preferredSubtitleLang,
      'preferredQuality': preferredQuality,
      'autoSyncStremioHistory': autoSyncStremioHistory,
    };
  }

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    return AppPreferences(
      darkMode: json['darkMode'] != false,
      vlcExecutablePath: (json['vlcExecutablePath'] ?? '').toString(),
      downloadDirectory: (json['downloadDirectory'] ?? '').toString(),
      preferredSubtitleLang:
          (json['preferredSubtitleLang'] ?? 'spa').toString(),
      preferredQuality: (json['preferredQuality'] ?? '1080p').toString(),
      autoSyncStremioHistory: json['autoSyncStremioHistory'] != false,
    );
  }
}

class StremioStorageService {
  final bool inMemory;
  final String? customFilePath;

  StremioUser? _currentUser;
  List<StremioAddon> _addons = StremioAddon.defaultAddons();
  final Map<String, LibraryWatchState> _watchHistory = {};
  final Map<String, LibraryWatchState> _offlineSyncQueue = {};
  final Map<String, DownloadTaskItem> _downloadTasks = {};
  AppPreferences _preferences = const AppPreferences();
  bool _initialized = false;

  StremioStorageService({
    this.inMemory = false,
    this.customFilePath,
  });

  bool get isInitialized => _initialized;

  StremioUser? get currentUser => _currentUser;
  String? get authKey =>
      (_currentUser != null && _currentUser!.authKey.isNotEmpty)
          ? _currentUser!.authKey
          : null;

  List<StremioAddon> get addons => List.unmodifiable(_addons);

  List<LibraryWatchState> get watchHistory {
    final list = _watchHistory.values.toList();
    list.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return list;
  }

  List<LibraryWatchState> get offlineSyncQueue {
    final list = _offlineSyncQueue.values.toList();
    list.sort((a, b) => a.lastWatched.compareTo(b.lastWatched));
    return list;
  }

  List<DownloadTaskItem> get downloadTasks {
    final list = _downloadTasks.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  AppPreferences get preferences => _preferences;

  String get resolvedStorageFilePath {
    if (kIsWeb) return '/valkery_state.json';
    if (customFilePath != null && customFilePath!.trim().isNotEmpty) {
      return customFilePath!;
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return p.join(home, '.valkery_stremio', 'state.json');
  }

  String get defaultDownloadDirectory {
    if (kIsWeb) return '/downloads';
    if (_preferences.downloadDirectory.trim().isNotEmpty) {
      return _preferences.downloadDirectory;
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return p.join(home, 'Downloads', 'ValkeryStremio');
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (inMemory || kIsWeb) return;

    try {
      final file = File(resolvedStorageFilePath);
      if (!await file.exists()) {
        await _persist();
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['user'] is Map<String, dynamic>) {
        _currentUser = StremioUser.fromJson(
          decoded['user'] as Map<String, dynamic>,
        );
      }

      if (decoded['addons'] is List) {
        final loadedAddons = (decoded['addons'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(StremioAddon.fromJson)
            .toList();
        if (loadedAddons.isNotEmpty) {
          _addons = loadedAddons;
        }
      }

      if (decoded['watchHistory'] is List) {
        _watchHistory.clear();
        for (final item in decoded['watchHistory'] as List<dynamic>) {
          if (item is Map<String, dynamic>) {
            final state = LibraryWatchState.fromJson(item);
            if (state.id.isNotEmpty) {
              _watchHistory[state.id] = state;
            }
          }
        }
      }

      if (decoded['offlineSyncQueue'] is List) {
        _offlineSyncQueue.clear();
        for (final item in decoded['offlineSyncQueue'] as List<dynamic>) {
          if (item is Map<String, dynamic>) {
            final state = LibraryWatchState.fromJson(
              item,
            ).copyWith(pendingOfflineSync: true);
            if (state.id.isNotEmpty) {
              _offlineSyncQueue[state.id] = state;
            }
          }
        }
      }

      if (decoded['downloadTasks'] is List) {
        _downloadTasks.clear();
        for (final item in decoded['downloadTasks'] as List<dynamic>) {
          if (item is Map<String, dynamic>) {
            final task = DownloadTaskItem.fromJson(item);
            if (task.id.isNotEmpty) {
              _downloadTasks[task.id] = task;
            }
          }
        }
      }

      if (decoded['preferences'] is Map<String, dynamic>) {
        _preferences = AppPreferences.fromJson(
          decoded['preferences'] as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Recover gracefully with default state if JSON is corrupted.
    }
  }

  Future<void> saveUser(StremioUser? user) async {
    _currentUser = user;
    await _persist();
  }

  Future<void> clearUser() async {
    _currentUser = null;
    await _persist();
  }

  Future<void> saveAddons(List<StremioAddon> addons) async {
    _addons = addons.isEmpty ? StremioAddon.defaultAddons() : List.of(addons);
    await _persist();
  }

  Future<void> addOrUpdateAddon(StremioAddon addon) async {
    final idx = _addons.indexWhere(
      (a) => a.id == addon.id || a.transportUrl == addon.transportUrl,
    );
    if (idx >= 0) {
      _addons[idx] = addon;
    } else {
      _addons = [..._addons, addon];
    }
    await _persist();
  }

  Future<void> removeAddon(String addonId) async {
    _addons = _addons.where((a) => a.id != addonId).toList();
    if (_addons.isEmpty) {
      _addons = StremioAddon.defaultAddons();
    }
    await _persist();
  }

  LibraryWatchState? getWatchState(String mediaId) => _watchHistory[mediaId];

  Future<void> upsertWatchState(
    LibraryWatchState state, {
    bool enqueueOfflineSync = false,
  }) async {
    final updated = state.copyWith(pendingOfflineSync: enqueueOfflineSync);
    _watchHistory[updated.id] = updated;
    if (enqueueOfflineSync) {
      _offlineSyncQueue[updated.id] = updated;
    }
    await _persist();
  }

  Future<void> mergeRemoteWatchHistory(List<LibraryWatchState> remoteItems) async {
    for (final remote in remoteItems) {
      if (remote.id.isEmpty) continue;
      final local = _watchHistory[remote.id];
      if (local == null ||
          (!local.pendingOfflineSync &&
              remote.lastWatched.isAfter(local.lastWatched))) {
        _watchHistory[remote.id] = remote;
      }
    }
    await _persist();
  }

  Future<void> enqueueOfflineWatchSync(LibraryWatchState state) async {
    final flagged = state.copyWith(pendingOfflineSync: true);
    _watchHistory[flagged.id] = flagged;
    _offlineSyncQueue[flagged.id] = flagged;
    await _persist();
  }

  Future<void> markOfflineWatchSynced(String mediaId) async {
    _offlineSyncQueue.remove(mediaId);
    final existing = _watchHistory[mediaId];
    if (existing != null) {
      _watchHistory[mediaId] = existing.copyWith(pendingOfflineSync: false);
    }
    await _persist();
  }

  Future<void> deleteWatchState(String mediaId) async {
    _watchHistory.remove(mediaId);
    _offlineSyncQueue.remove(mediaId);
    await _persist();
  }

  Future<void> upsertDownloadTask(DownloadTaskItem task) async {
    _downloadTasks[task.id] = task;
    await _persist();
  }

  Future<void> removeDownloadTask(String taskId) async {
    _downloadTasks.remove(taskId);
    await _persist();
  }

  Future<void> savePreferences(AppPreferences preferences) async {
    _preferences = preferences;
    await _persist();
  }

  Future<void> _persist() async {
    if (inMemory) return;
    try {
      final file = File(resolvedStorageFilePath);
      await file.parent.create(recursive: true);
      final payload = {
        'user': _currentUser?.toJson(),
        'addons': _addons.map((a) => a.toJson()).toList(),
        'watchHistory': _watchHistory.values.map((w) => w.toJson()).toList(),
        'offlineSyncQueue':
            _offlineSyncQueue.values.map((w) => w.toJson()).toList(),
        'downloadTasks': _downloadTasks.values.map((t) => t.toJson()).toList(),
        'preferences': _preferences.toJson(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (_) {
      // Ignore write failures in read-only sandboxed test environments.
    }
  }
}
