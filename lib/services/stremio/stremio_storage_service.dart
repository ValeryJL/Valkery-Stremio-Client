import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/stremio/download_task.dart';
import '../../models/stremio/media_item.dart';
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
  final Map<String, MediaItem> _libraryFavorites = {};
  final Map<String, LibraryWatchState> _offlineSyncQueue = {};
  final Map<String, DownloadTaskItem> _downloadTasks = {};
  AppPreferences _preferences = const AppPreferences();
  bool _initialized = false;

  final _watchHistoryController = StreamController<List<LibraryWatchState>>.broadcast();
  Stream<List<LibraryWatchState>> get watchHistoryStream => _watchHistoryController.stream;

  final _libraryFavoritesController = StreamController<List<MediaItem>>.broadcast();
  Stream<List<MediaItem>> get libraryFavoritesStream => _libraryFavoritesController.stream;

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

  List<LibraryWatchState> get stremioLibraryItems {
    final list = _watchHistory.values.where((item) => item.isLibraryItem).toList();
    list.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return list;
  }

  bool isInLibrary(String mediaId) => _watchHistory[mediaId]?.isLibraryItem ?? false;
  bool isFavorite(String mediaId) => isInLibrary(mediaId);

  Future<void> addToLibrary(MediaItem item) async {
    _libraryFavorites[item.id] = item;
    final existing = _watchHistory[item.id];
    final updated = (existing ??
        LibraryWatchState(
          id: item.id,
          name: item.name,
          type: item.type,
          poster: item.poster,
          videoId: item.id,
          lastWatched: DateTime.now().toUtc(),
        ))
        .copyWith(isLibraryItem: true);
    await upsertWatchState(updated);
  }

  Future<void> removeFromLibrary(String mediaId) async {
    _libraryFavorites.remove(mediaId);
    final existing = _watchHistory[mediaId];
    if (existing != null) {
      if (existing.timeOffset > 0 || existing.timesWatched > 0) {
        final updated = existing.copyWith(isLibraryItem: false);
        await upsertWatchState(updated);
      } else {
        await deleteWatchState(mediaId);
      }
    }
  }

  Future<void> toggleFavorite(MediaItem item) async {
    if (isInLibrary(item.id)) {
      await removeFromLibrary(item.id);
    } else {
      await addToLibrary(item);
    }
  }

  AppPreferences get preferences => _preferences;

  void _notifyWatchHistory() {
    if (!_watchHistoryController.isClosed) {
      _watchHistoryController.add(watchHistory);
    }
  }

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
    if (inMemory || kIsWeb) {
      _notifyWatchHistory();
      return;
    }

    try {
      final file = File(resolvedStorageFilePath);
      if (!await file.exists()) {
        try {
          final legacyHome = Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'];
          if (legacyHome != null) {
            final legacyFile = File(p.join(legacyHome, '.valkery_stremio', 'state.json'));
            if (await legacyFile.exists()) {
              final legacyRaw = await legacyFile.readAsString();
              if (legacyRaw.trim().isNotEmpty) {
                await file.parent.create(recursive: true);
                await file.writeAsString(legacyRaw);
              }
            }
          }
        } catch (_) {}
      }

      if (!await file.exists()) {
        await _persist();
        _notifyWatchHistory();
        return;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _notifyWatchHistory();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _notifyWatchHistory();
        return;
      }

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

      if (decoded['libraryFavorites'] is List) {
        _libraryFavorites.clear();
        for (final item in decoded['libraryFavorites'] as List<dynamic>) {
          if (item is Map<String, dynamic>) {
            try {
              final media = MediaItem.fromJson(item);
              if (media.id.isNotEmpty) {
                _libraryFavorites[media.id] = media;
              }
            } catch (_) {}
          }
        }
      }

      // Migrate legacy favorites into _watchHistory with isLibraryItem: true
      for (final fav in _libraryFavorites.values) {
        final existing = _watchHistory[fav.id];
        if (existing == null) {
          _watchHistory[fav.id] = LibraryWatchState(
            id: fav.id,
            name: fav.name,
            type: fav.type,
            poster: fav.poster,
            videoId: fav.id,
            lastWatched: DateTime.now().toUtc(),
            isLibraryItem: true,
          );
        } else if (!existing.isLibraryItem) {
          _watchHistory[fav.id] = existing.copyWith(isLibraryItem: true);
        }
      }
    } catch (_) {
      // Recover gracefully with default state if JSON is corrupted.
    }

    _notifyWatchHistory();
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
    _notifyWatchHistory();
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
    _notifyWatchHistory();
  }

  Future<void> enqueueOfflineWatchSync(LibraryWatchState state) async {
    final flagged = state.copyWith(pendingOfflineSync: true);
    _watchHistory[flagged.id] = flagged;
    _offlineSyncQueue[flagged.id] = flagged;
    await _persist();
    _notifyWatchHistory();
  }

  Future<void> markOfflineWatchSynced(String mediaId) async {
    _offlineSyncQueue.remove(mediaId);
    final existing = _watchHistory[mediaId];
    if (existing != null) {
      _watchHistory[mediaId] = existing.copyWith(pendingOfflineSync: false);
    }
    await _persist();
    _notifyWatchHistory();
  }

  Future<void> deleteWatchState(String mediaId) async {
    _watchHistory.remove(mediaId);
    _offlineSyncQueue.remove(mediaId);
    await _persist();
    _notifyWatchHistory();
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
        'libraryFavorites':
            _libraryFavorites.values.map((m) => m.toJson()).toList(),
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

  Future<void> dispose() async {
    await _watchHistoryController.close();
    await _libraryFavoritesController.close();
  }
}
