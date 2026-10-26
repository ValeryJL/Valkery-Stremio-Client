import 'dart:convert';

import 'package:http/http.dart' as http;

import 'stremio_storage_service.dart';
import '../../models/stremio/media_item.dart';
import '../../models/stremio/stremio_user.dart';
import '../../models/stremio/watch_history_item.dart';

class StremioApiException implements Exception {
  final String message;
  final int? statusCode;

  const StremioApiException(this.message, {this.statusCode});

  @override
  String toString() => 'StremioApiException($statusCode): $message';
}

/// Complete implementation of the official Stremio API (api.strem.io/api),
/// Stremio Datastore (libraryItem, datastorePut, datastoreGet),
/// Stremio Addon Collection management, and local streaming server detection (11470).
class StremioApiService {
  static const String defaultBaseUrl = 'https://api.strem.io/api';
  static const String addonDirectoryUrl =
      'https://api.strem.io/addon-directory/catalog.json';
  static const String localStreamingServerBase = 'http://127.0.0.1:11470';

  final http.Client _httpClient;
  final StremioStorageService? _storage;
  final String baseUrl;

  StremioApiService({
    http.Client? httpClient,
    StremioStorageService? storage,
    this.baseUrl = defaultBaseUrl,
  }) : _httpClient = httpClient ?? http.Client(),
       _storage = storage;

  /// Logs in to Stremio with email and password.
  Future<StremioUser> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/login');
    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'type': 'Login',
            'email': email.trim(),
            'password': password,
            'facebook': false,
          }),
        )
        .timeout(const Duration(seconds: 14));

    final body = _decodeResponse(response);
    final result = _extractResultMap(body);
    final user = StremioUser.fromJson(result);
    if (user.authKey.isEmpty) {
      throw const StremioApiException(
        'Credenciales inválidas o authKey ausente en la respuesta de Stremio.',
      );
    }
    await _storage?.saveUser(user);

    // Automatically synchronize addons and watch history from user's account
    try {
      await getAddonCollection(user.authKey);
      await fetchWatchHistory(user.authKey);
    } catch (_) {}

    return user;
  }

  /// Syncs addons and watch history for currently stored user session.
  Future<void> syncAccountData() async {
    final key = _storage?.authKey;
    if (key != null && key.isNotEmpty) {
      try {
        await getAddonCollection(key);
        await fetchWatchHistory(key);
      } catch (_) {}
    }
  }

  /// Registers a new user account on official Stremio backend.
  Future<StremioUser> register(String email, String password) async {
    final uri = Uri.parse('$baseUrl/register');
    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'type': 'Register',
            'email': email.trim(),
            'password': password,
            'facebook': false,
          }),
        )
        .timeout(const Duration(seconds: 14));

    final body = _decodeResponse(response);
    final result = _extractResultMap(body);
    final user = StremioUser.fromJson(result);
    if (user.authKey.isEmpty) {
      throw const StremioApiException(
        'No se pudo completar el registro en Stremio.',
      );
    }
    await _storage?.saveUser(user);
    return user;
  }

  /// Validates an existing authKey and retrieves user profile information.
  Future<StremioUser> getUser(String authKey) async {
    final uri = Uri.parse('$baseUrl/getUser');
    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'type': 'GetUser',
            'authKey': authKey.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));

    final body = _decodeResponse(response);
    final result = _extractResultMap(body);
    final user = StremioUser.fromJson(result, fallbackAuthKey: authKey.trim());
    await _storage?.saveUser(user);
    return user;
  }

  /// Logs out the user from Stremio API session and clears local session.
  Future<void> logout({String? authKey}) async {
    final activeKey = authKey ?? _storage?.authKey;
    if (activeKey != null && activeKey.isNotEmpty) {
      try {
        final uri = Uri.parse('$baseUrl/logout');
        await _httpClient
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'type': 'Logout',
                'authKey': activeKey,
              }),
            )
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        // Proceed with local sign-out even if network request fails.
      }
    }
    await _storage?.clearUser();
  }

  /// Fetches the user's installed addons collection directly from Stremio account.
  /// If the user has addons installed in their account, ONLY those addons are returned.
  Future<List<StremioAddon>> getAddonCollection(String authKey) async {
    if (authKey.trim().isEmpty) {
      return _storage?.addons ?? const [];
    }
    try {
      final uri = Uri.parse('$baseUrl/addonCollectionGet');
      final response = await _httpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': 'AddonCollectionGet',
              'authKey': authKey.trim(),
              'update': true,
            }),
          )
          .timeout(const Duration(seconds: 14));

      final body = _decodeResponse(response);
      final result = _extractResultMap(body);
      final rawAddons = result['addons'] as List<dynamic>? ?? const [];
      final addons = rawAddons
          .whereType<Map<String, dynamic>>()
          .map(StremioAddon.fromJson)
          .toList();

      if (addons.isNotEmpty) {
        // Ensure default fallback addons (like Torrentio/OpenSubtitles) are retained if not present
        for (final def in StremioAddon.defaultAddons()) {
          if (!addons.any((a) => a.id == def.id)) {
            addons.add(def);
          }
        }
        await _storage?.saveAddons(addons);
        return addons;
      }
    } catch (_) {}
    return _storage?.addons ?? StremioAddon.defaultAddons();
  }

  /// Sets/synchronizes the user's addons collection on Stremio cloud account.
  Future<bool> setAddonCollection(
    String authKey,
    List<StremioAddon> addons,
  ) async {
    await _storage?.saveAddons(addons);
    if (authKey.trim().isEmpty) return false;

    final uri = Uri.parse('$baseUrl/addonCollectionSet');
    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'type': 'AddonCollectionSet',
            'authKey': authKey.trim(),
            'addons': addons.map((a) => a.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 14));

    final body = _decodeResponse(response);
    final result = body['result'];
    if (result is Map<String, dynamic>) {
      return result['success'] != false;
    }
    return true;
  }

  /// Installs an addon by fetching its manifest URL and optionally syncing to Stremio.
  Future<StremioAddon> installAddonFromManifestUrl(
    String manifestUrl, {
    String? authKey,
  }) async {
    final normalizedUrl = manifestUrl.trim().endsWith('/manifest.json')
        ? manifestUrl.trim()
        : '${manifestUrl.trim().replaceAll(RegExp(r'/+$'), '')}/manifest.json';

    final response = await _httpClient
        .get(Uri.parse(normalizedUrl))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StremioApiException(
        'Failed to load addon manifest from $normalizedUrl',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const StremioApiException('Invalid addon manifest format.');
    }

    final addon = StremioAddon.fromJson({
      'transportUrl': normalizedUrl,
      'manifest': decoded,
    });

    await _storage?.addOrUpdateAddon(addon);
    final key = authKey ?? _storage?.authKey;
    final storage = _storage;
    if (key != null && key.isNotEmpty && storage != null) {
      try {
        await setAddonCollection(key, storage.addons);
      } catch (_) {
        // Keep local addon installed even if remote sync fails.
      }
    }
    return addon;
  }

  /// Uninstalls an addon by ID and syncs changes to Stremio.
  Future<void> uninstallAddon(String addonId, {String? authKey}) async {
    await _storage?.removeAddon(addonId);
    final key = authKey ?? _storage?.authKey;
    final storage = _storage;
    if (key != null && key.isNotEmpty && storage != null) {
      try {
        await setAddonCollection(key, storage.addons);
      } catch (_) {
        // Ignore remote sync failure on removal.
      }
    }
  }

  /// Fetches the official community addons directory list from Stremio.
  Future<List<StremioAddon>> fetchCommunityAddonDirectory() async {
    try {
      final response = await _httpClient
          .get(Uri.parse(addonDirectoryUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map(StremioAddon.fromJson)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  /// Fetches the user's library and watch history from Stremio datastore (`datastoreGet`).
  Future<List<LibraryWatchState>> fetchWatchHistory(String authKey) async {
    if (authKey.trim().isEmpty) {
      return _storage?.watchHistory ?? const [];
    }

    final uri = Uri.parse('$baseUrl/datastoreGet');
    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'authKey': authKey.trim(),
            'collection': 'libraryItem',
            'ids': const <String>[],
            'all': true,
          }),
        )
        .timeout(const Duration(seconds: 14));

    final body = _decodeResponse(response);
    final rawResult = body['result'];
    final items = <LibraryWatchState>[];

    if (rawResult is List) {
      for (final entry in rawResult) {
        if (entry is Map<String, dynamic>) {
          if (entry['removed'] == true) continue;
          final parsed = LibraryWatchState.fromJson(entry);
          if (parsed.id.isNotEmpty) {
            items.add(parsed);
          }
        }
      }
    }

    items.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    await _storage?.mergeRemoteWatchHistory(items);
    return _storage?.watchHistory ?? items;
  }

  /// Syncs single watch progress to Stremio datastore (`datastorePut`).
  Future<bool> syncWatchState(
    String authKey,
    LibraryWatchState item,
  ) async {
    if (authKey.trim().isEmpty) {
      await _storage?.enqueueOfflineWatchSync(item);
      return false;
    }

    try {
      final uri = Uri.parse('$baseUrl/datastorePut');
      final response = await _httpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'authKey': authKey.trim(),
              'collection': 'libraryItem',
              'changes': [item.toStremioDatastoreItem()],
            }),
          )
          .timeout(const Duration(seconds: 12));

      _decodeResponse(response);
      await _storage?.upsertWatchState(item, enqueueOfflineSync: false);
      await _storage?.markOfflineWatchSynced(item.id);
      return true;
    } catch (_) {
      await _storage?.enqueueOfflineWatchSync(item);
      return false;
    }
  }

  /// Adds a media item to the user's Stremio library.
  Future<bool> addToLibrary(String authKey, MediaItem item) async {
    final storage = _storage;
    final existing = storage?.getWatchState(item.id);
    final watchState = (existing ??
        LibraryWatchState(
          id: item.id,
          name: item.name,
          type: item.type,
          poster: item.poster,
          videoId: item.id,
          timeOffset: 0,
          duration: 1,
          timesWatched: 0,
          flaggedWatched: 0,
          watchedEpisodes: const [],
          lastWatched: DateTime.now().toUtc(),
          pendingOfflineSync: false,
        ))
        .copyWith(isLibraryItem: true);

    await storage?.upsertWatchState(watchState);
    if (authKey.trim().isEmpty) return true;
    return syncWatchState(authKey, watchState);
  }

  /// Removes an item from the user's Stremio library (`removed: true` via datastorePut).
  Future<bool> removeFromLibrary(String authKey, String itemId) async {
    await _storage?.removeFromLibrary(itemId);
    if (authKey.trim().isEmpty) return true;

    try {
      final uri = Uri.parse('$baseUrl/datastorePut');
      final response = await _httpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'authKey': authKey.trim(),
              'collection': 'libraryItem',
              'changes': [
                {
                  '_id': itemId,
                  'removed': true,
                  '_mtime': DateTime.now().toUtc().toIso8601String(),
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      _decodeResponse(response);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Flushes pending offline watch states to Stremio (`datastorePut`).
  Future<int> flushOfflineSyncQueue(String authKey) async {
    final storage = _storage;
    if (storage == null || authKey.trim().isEmpty) return 0;

    final pending = storage.offlineSyncQueue;
    if (pending.isEmpty) return 0;

    try {
      final uri = Uri.parse('$baseUrl/datastorePut');
      final response = await _httpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'authKey': authKey.trim(),
              'collection': 'libraryItem',
              'changes': pending
                  .map((item) => item.toStremioDatastoreItem())
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 14));

      _decodeResponse(response);
      for (final item in pending) {
        await storage.markOfflineWatchSynced(item.id);
      }
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  /// Detects if an official local Stremio Streaming Server is running on port 11470.
  Future<bool> isLocalStreamingServerOnline({int port = 11470}) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$port/stats.json');
      final response = await _httpClient.get(uri).timeout(
        const Duration(milliseconds: 1500),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StremioApiException(
        'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const StremioApiException('Invalid JSON payload from Stremio API.');
    }
    if (decoded['error'] != null) {
      final err = decoded['error'];
      final message = err is Map<String, dynamic>
          ? (err['message'] ?? err.toString()).toString()
          : err.toString();
      throw StremioApiException(message, statusCode: response.statusCode);
    }
    return decoded;
  }

  Map<String, dynamic> _extractResultMap(Map<String, dynamic> body) {
    final result = body['result'];
    if (result is Map<String, dynamic>) {
      return result;
    }
    return body;
  }
}
