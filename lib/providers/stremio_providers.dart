import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stremio/media_item.dart';
import '../models/stremio/stream_candidate.dart';
import '../models/stremio/watch_history_item.dart';
import '../services/stremio/catalog_and_stream_service.dart';
import '../services/stremio/stremio_api_service.dart';
import '../services/stremio/stremio_offline_download_manager.dart';
import '../services/stremio/stremio_server_process_manager.dart';
import '../services/stremio/stremio_storage_service.dart';
import 'source_coordinator_provider.dart';

/// Local Storage for Stremio user, addons, and watch progress.
final stremioStorageProvider = Provider<StremioStorageService>((ref) {
  return StremioStorageService();
});

/// Official Stremio Cloud API Service (api.strem.io).
final stremioApiServiceProvider = Provider<StremioApiService>((ref) {
  final storage = ref.watch(stremioStorageProvider);
  return StremioApiService(storage: storage);
});

/// Catalog and Streams Service (Cinemeta + Community Addons + Subtitles).
final catalogAndStreamServiceProvider = Provider<CatalogAndStreamService>((ref) {
  return CatalogAndStreamService();
});

/// Background daemon process manager for Stremio Streaming Server (11470).
final stremioServerProcessManagerProvider = Provider<StremioServerProcessManager>((ref) {
  final coordinator = ref.watch(sourceCoordinatorProvider);
  final manager = StremioServerProcessManager(
    serverUrl: coordinator.stremioServerUrl,
  );
  manager.initialize();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Stream of Stremio Server health status.
final stremioServerStatusStreamProvider = StreamProvider<StremioServerStatus>((ref) {
  final manager = ref.watch(stremioServerProcessManagerProvider);
  return manager.statusStream;
});

/// Offline Downloads Manager for persistent local video and subtitles.
final stremioOfflineDownloadManagerProvider = Provider<StremioOfflineDownloadManager>((ref) {
  final manager = StremioOfflineDownloadManager();
  manager.initialize();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Stream of active and completed offline downloads.
final stremioOfflineDownloadsStreamProvider = StreamProvider<List<OfflineMediaEntry>>((ref) {
  final manager = ref.watch(stremioOfflineDownloadManagerProvider);
  return manager.downloadsStream;
});

/// Top popular movies from Cinemeta.
final stremioTopMoviesProvider = FutureProvider.autoDispose<List<MediaItem>>((ref) async {
  final service = ref.watch(catalogAndStreamServiceProvider);
  return service.fetchTopCatalog(type: 'movie');
});

/// Top popular TV series from Cinemeta.
final stremioTopSeriesProvider = FutureProvider.autoDispose<List<MediaItem>>((ref) async {
  final service = ref.watch(catalogAndStreamServiceProvider);
  return service.fetchTopCatalog(type: 'series');
});

/// Search results provider for Stremio catalog.
final stremioSearchQueryProvider = StateProvider<String>((ref) => '');

final stremioSearchResultsProvider = FutureProvider.autoDispose<List<MediaItem>>((ref) async {
  final query = ref.watch(stremioSearchQueryProvider);
  final service = ref.watch(catalogAndStreamServiceProvider);
  if (query.trim().isEmpty) return const [];
  return service.searchCatalog(query);
});

/// Full media details (synopsis, cast, director, episodes, backdrop) from Cinemeta.
final stremioMediaDetailsProvider = FutureProvider.family
    .autoDispose<MediaItem, ({String id, String type})>((ref, params) async {
  final service = ref.watch(catalogAndStreamServiceProvider);
  return service.fetchMediaDetails(params.id, params.type);
});

/// Streams discovery for a specific media item ID and type.
final stremioStreamsProvider = FutureProvider.family
    .autoDispose<List<StreamCandidate>, ({String id, String type, int? season, int? episode})>(
  (ref, params) async {
    final service = ref.watch(catalogAndStreamServiceProvider);
    final storage = ref.watch(stremioStorageProvider);
    return service.fetchStreams(
      params.id,
      params.type,
      season: params.season,
      episode: params.episode,
      addons: storage.addons,
    );
  },
);

/// User's library and watch history from Stremio datastore.
final stremioWatchHistoryProvider = FutureProvider.autoDispose<List<LibraryWatchState>>((ref) async {
  final storage = ref.watch(stremioStorageProvider);
  final api = ref.watch(stremioApiServiceProvider);
  final key = storage.authKey;
  if (key != null && key.isNotEmpty) {
    try {
      final remote = await api.fetchWatchHistory(key);
      if (remote.isNotEmpty) return remote;
    } catch (_) {}
  }
  return storage.watchHistory;
});
