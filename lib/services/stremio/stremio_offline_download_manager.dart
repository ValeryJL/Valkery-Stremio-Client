import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../util/file_downloader.dart';
import 'catalog_and_stream_service.dart';
import 'stremio_storage_service.dart';

enum OfflineItemStatus {
  queued,
  downloading,
  completed,
  paused,
  failed,
}

class OfflineSubtitleTrack {
  final String language;
  final String localPath;

  const OfflineSubtitleTrack({
    required this.language,
    required this.localPath,
  });

  Map<String, dynamic> toJson() => {
        'language': language,
        'localPath': localPath,
      };

  factory OfflineSubtitleTrack.fromJson(Map<String, dynamic> json) =>
      OfflineSubtitleTrack(
        language: json['language']?.toString() ?? 'und',
        localPath: json['localPath']?.toString() ?? '',
      );
}

class OfflineMediaEntry {
  final String id;
  final String mediaId;
  final String title;
  final String seriesTitle;
  final String? episodeTitle;
  final String type;
  final int? season;
  final int? episode;
  final String localVideoPath;
  final String? localPosterPath;
  final String? posterUrl;
  final List<OfflineSubtitleTrack> subtitles;
  final int totalBytes;
  final int downloadedBytes;
  final OfflineItemStatus status;
  final double progress;
  final String? errorMessage;
  final DateTime createdAt;

  const OfflineMediaEntry({
    required this.id,
    String? mediaId,
    required this.title,
    String? seriesTitle,
    this.episodeTitle,
    required this.type,
    this.season,
    this.episode,
    required this.localVideoPath,
    this.localPosterPath,
    this.posterUrl,
    this.subtitles = const [],
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = OfflineItemStatus.queued,
    this.progress = 0.0,
    this.errorMessage,
    required this.createdAt,
  })  : mediaId = mediaId ?? id,
        seriesTitle = seriesTitle ?? title;

  OfflineMediaEntry copyWith({
    OfflineItemStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    double? progress,
    List<OfflineSubtitleTrack>? subtitles,
    String? localPosterPath,
    String? posterUrl,
    String? episodeTitle,
    String? errorMessage,
  }) {
    return OfflineMediaEntry(
      id: id,
      mediaId: mediaId,
      title: title,
      seriesTitle: seriesTitle,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      type: type,
      season: season,
      episode: episode,
      localVideoPath: localVideoPath,
      localPosterPath: localPosterPath ?? this.localPosterPath,
      posterUrl: posterUrl ?? this.posterUrl,
      subtitles: subtitles ?? this.subtitles,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaId': mediaId,
        'title': title,
        'seriesTitle': seriesTitle,
        'episodeTitle': episodeTitle,
        'type': type,
        'season': season,
        'episode': episode,
        'localVideoPath': localVideoPath,
        'localPosterPath': localPosterPath,
        'posterUrl': posterUrl,
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'status': status.name,
        'progress': progress,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OfflineMediaEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final rawTitle = json['title']?.toString() ?? '';
    final resolvedMediaId = json['mediaId']?.toString().isNotEmpty == true
        ? json['mediaId'].toString()
        : rawId.split('_S').first;
    final resolvedSeriesTitle = json['seriesTitle']?.toString().isNotEmpty == true
        ? json['seriesTitle'].toString()
        : rawTitle.replaceAll(RegExp(r'\s*\(S\d+E\d+\)$'), '');

    return OfflineMediaEntry(
      id: rawId,
      mediaId: resolvedMediaId,
      title: rawTitle,
      seriesTitle: resolvedSeriesTitle,
      episodeTitle: json['episodeTitle']?.toString(),
      type: json['type']?.toString() ?? 'movie',
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      localVideoPath: json['localVideoPath']?.toString() ?? '',
      localPosterPath: json['localPosterPath']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      subtitles: (json['subtitles'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OfflineSubtitleTrack.fromJson)
          .toList(),
      totalBytes: json['totalBytes'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      status: OfflineItemStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => OfflineItemStatus.completed,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Offline Download Manager for Stremio media, downloading video chunks,
/// posters, and subtitle tracks to persistent local storage with offline playback.
class StremioOfflineDownloadManager {
  final http.Client _httpClient;
  final Map<String, OfflineMediaEntry> _entries = {};
  final Map<String, StreamSubscription<List<int>>> _activeDownloads = {};
  final _updatesController = StreamController<List<OfflineMediaEntry>>.broadcast();

  String? _downloadsDirectory;

  Stream<List<OfflineMediaEntry>> get downloadsStream => _updatesController.stream;
  List<OfflineMediaEntry> get allDownloads => List.unmodifiable(_entries.values);

  StremioOfflineDownloadManager({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Initializes the offline directory and restores saved offline items metadata.
  Future<void> initialize() async {
    if (kIsWeb) return;

    final appDocDir = await getApplicationDocumentsDirectory();
    final offlineDir = Directory(p.join(appDocDir.path, 'Valkery', 'Offline'));
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    _downloadsDirectory = offlineDir.path;

    await _loadPersistedIndex();
  }

  /// Starts downloading a stream candidate with subtitles and metadata.
  Future<OfflineMediaEntry> startDownload({
    required MediaItem media,
    required StreamCandidate stream,
    String? serverUrl,
    int? season,
    int? episode,
    List<SubtitleTrack>? subtitles,
  }) async {
    final effectiveStreamUrl = serverUrl != null && serverUrl.isNotEmpty
        ? stream.playbackUrlFor(serverUrl)
        : stream.playbackUrl;

    final entryId = (season != null && episode != null)
        ? '${media.id}_S${season}E$episode'
        : media.id;

    final epMeta = (season != null && episode != null)
        ? media.episodes
            .where((v) => v.season == season && v.episode == episode)
            .firstOrNull
        : null;

    if (kIsWeb) {
      await downloadFile(effectiveStreamUrl);
      final webEntry = OfflineMediaEntry(
        id: entryId,
        mediaId: media.id,
        title: (season != null && episode != null)
            ? '${media.name} (S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')})'
            : media.name,
        seriesTitle: media.name,
        episodeTitle: epMeta?.title,
        type: media.type,
        season: season,
        episode: episode,
        localVideoPath: effectiveStreamUrl,
        posterUrl: media.poster,
        status: OfflineItemStatus.completed,
        progress: 1.0,
        createdAt: DateTime.now(),
      );
      _entries[entryId] = webEntry;
      await _savePersistedIndex();
      _notify();

      // Fetch and attach subtitle references in background
      Future(() async {
        try {
          final subs = (subtitles != null && subtitles.isNotEmpty)
              ? subtitles
              : await CatalogAndStreamService().fetchSubtitles(
                  media.id,
                  media.type,
                  season: season,
                  episode: episode,
                );
          if (subs.isNotEmpty && _entries.containsKey(entryId)) {
            final filtered = _selectPreferredSubtitles(subs);
            _entries[entryId] = _entries[entryId]!.copyWith(
              subtitles: filtered
                  .map((s) => OfflineSubtitleTrack(language: s.lang, localPath: s.url))
                  .toList(),
            );
            await _savePersistedIndex();
            _notify();
          }
        } catch (_) {}
      });

      return webEntry;
    }

    if (_downloadsDirectory == null) {
      throw StateError('El directorio de descargas no está inicializado.');
    }

    final mediaFolder = Directory(p.join(_downloadsDirectory!, entryId));
    if (!await mediaFolder.exists()) {
      await mediaFolder.create(recursive: true);
    }

    final videoExt = _inferVideoExtension(effectiveStreamUrl);
    final videoPath = p.join(mediaFolder.path, 'video$videoExt');

    var entry = OfflineMediaEntry(
      id: entryId,
      mediaId: media.id,
      title: (season != null && episode != null)
          ? '${media.name} (S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')})'
          : media.name,
      seriesTitle: media.name,
      episodeTitle: epMeta?.title,
      type: media.type,
      season: season,
      episode: episode,
      localVideoPath: videoPath,
      posterUrl: media.poster,
      status: OfflineItemStatus.downloading,
      createdAt: DateTime.now(),
    );

    _entries[entryId] = entry;
    _notify();

    // 1. Download poster in background
    if (media.poster.isNotEmpty) {
      _downloadPoster(media.poster, mediaFolder.path).then((posterPath) {
        if (posterPath != null && _entries.containsKey(entryId)) {
          _entries[entryId] = _entries[entryId]!.copyWith(localPosterPath: posterPath);
          _savePersistedIndex();
          _notify();
        }
      });
    }

    // 2. Download subtitles in background (fetch automatically if not provided)
    Future(() async {
      try {
        final effectiveSubs = (subtitles != null && subtitles.isNotEmpty)
            ? subtitles
            : await CatalogAndStreamService().fetchSubtitles(
                media.id,
                media.type,
                season: season,
                episode: episode,
              );
        if (effectiveSubs.isNotEmpty) {
          final preferred = _selectPreferredSubtitles(effectiveSubs);
          final subList = await _downloadSubtitles(preferred, mediaFolder.path);
          if (subList.isNotEmpty && _entries.containsKey(entryId)) {
            _entries[entryId] = _entries[entryId]!.copyWith(subtitles: subList);
            await _savePersistedIndex();
            _notify();
          }
        }
      } catch (_) {}
    });

    // 3. Stream video file chunks
    _downloadVideoStream(
      streamUrl: effectiveStreamUrl,
      savePath: videoPath,
      entryId: entryId,
    );

    return entry;
  }

  List<SubtitleTrack> _selectPreferredSubtitles(List<SubtitleTrack> all) {
    final spanish = all.where((s) => s.isSpanish).take(6).toList();
    final english = all
        .where((s) =>
            !s.isSpanish &&
            (s.lang.toLowerCase().contains('eng') || s.lang.toLowerCase() == 'en'))
        .take(4)
        .toList();
    final combined = [...spanish, ...english];
    if (combined.isNotEmpty) return combined;
    return all.take(6).toList();
  }

  void _downloadVideoStream({
    required String streamUrl,
    required String savePath,
    required String entryId,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(streamUrl));
      final streamedResponse = await _httpClient.send(request);

      final totalBytes = streamedResponse.contentLength ?? 0;
      var receivedBytes = 0;

      final file = File(savePath);
      final sink = file.openWrite();

      final subscription = streamedResponse.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          final progress = totalBytes > 0
              ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
              : 0.0;

          final existing = _entries[entryId];
          if (existing != null) {
            _entries[entryId] = existing.copyWith(
              downloadedBytes: receivedBytes,
              totalBytes: totalBytes,
              progress: progress,
            );
            _notify();
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          _activeDownloads.remove(entryId);

          final existing = _entries[entryId];
          if (existing != null) {
            _entries[entryId] = existing.copyWith(
              status: OfflineItemStatus.completed,
              progress: 1.0,
            );
            await _savePersistedIndex();
            _notify();
          }
        },
        onError: (e) async {
          await sink.close();
          _activeDownloads.remove(entryId);

          final existing = _entries[entryId];
          if (existing != null) {
            _entries[entryId] = existing.copyWith(
              status: OfflineItemStatus.failed,
              errorMessage: e.toString(),
            );
            await _savePersistedIndex();
            _notify();
          }
        },
        cancelOnError: true,
      );

      _activeDownloads[entryId] = subscription;
    } catch (e) {
      final existing = _entries[entryId];
      if (existing != null) {
        _entries[entryId] = existing.copyWith(
          status: OfflineItemStatus.failed,
          errorMessage: e.toString(),
        );
        _notify();
      }
    }
  }

  Future<String?> _downloadPoster(String posterUrl, String targetFolder) async {
    try {
      final response = await _httpClient.get(Uri.parse(posterUrl));
      if (response.statusCode == 200) {
        final posterFile = File(p.join(targetFolder, 'poster.jpg'));
        await posterFile.writeAsBytes(response.bodyBytes);
        return posterFile.path;
      }
    } catch (_) {}
    return null;
  }

  Future<List<OfflineSubtitleTrack>> _downloadSubtitles(
    List<SubtitleTrack> subtitles,
    String targetFolder,
  ) async {
    final list = <OfflineSubtitleTrack>[];
    for (var i = 0; i < subtitles.length; i++) {
      final sub = subtitles[i];
      if (sub.url.isEmpty) continue;

      try {
        final response = await _httpClient.get(Uri.parse(sub.url));
        if (response.statusCode == 200) {
          final lang = sub.lang.isNotEmpty ? sub.lang : 'und';
          final subFile = File(p.join(targetFolder, 'sub_${i}_$lang.srt'));
          // Limpiar artefactos de traducción automática estilo [cite: 2]
          final rawContent = utf8.decode(response.bodyBytes, allowMalformed: true);
          final cleanContent = rawContent.replaceAll(
            RegExp(r'\[cite(?:_start|_end|:\s*[^\]]*)?\]', caseSensitive: false),
            '',
          );
          await subFile.writeAsString(cleanContent, encoding: utf8);
          list.add(OfflineSubtitleTrack(language: lang, localPath: subFile.path));
        }
      } catch (_) {}
    }
    return list;
  }

  /// Cancels an active download and purges files from storage.
  Future<void> deleteDownload(String entryId) async {
    final sub = _activeDownloads.remove(entryId);
    await sub?.cancel();

    final entry = _entries.remove(entryId);
    if (entry != null && _downloadsDirectory != null) {
      final folder = Directory(p.join(_downloadsDirectory!, entryId));
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    }

    await _savePersistedIndex();
    _notify();
  }

  /// Returns completed downloads that are already marked as watched in storage,
  /// so the UI can ask the user for explicit confirmation before deleting anything.
  List<OfflineMediaEntry> getWatchedCompletedDownloads(
    StremioStorageService storage,
  ) {
    final watched = <OfflineMediaEntry>[];
    for (final entry in _entries.values) {
      if (entry.status != OfflineItemStatus.completed) continue;
      final watchState = storage.getWatchState(entry.mediaId);
      if (watchState == null) continue;
      if (entry.season != null && entry.episode != null) {
        final epId = '${entry.mediaId}:${entry.season}:${entry.episode}';
        if (watchState.watchedEpisodes.contains(epId)) {
          watched.add(entry);
        }
      } else {
        if (watchState.flaggedWatched > 0 ||
            watchState.timesWatched > 0 ||
            watchState.progressRatio >= 0.9) {
          watched.add(entry);
        }
      }
    }
    return watched;
  }

  /// Deletes only the specified download entry IDs after explicit user approval.
  Future<int> deleteSelectedDownloads(Iterable<String> entryIds) async {
    final ids = entryIds.toList();
    for (final id in ids) {
      await deleteDownload(id);
    }
    return ids.length;
  }

  Future<void> _savePersistedIndex() async {
    final data = _entries.values.map((e) => e.toJson()).toList();
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('valkery_offline_downloads_web', jsonEncode(data));
      } catch (_) {}
      return;
    }
    if (_downloadsDirectory == null) return;
    try {
      final indexFile = File(p.join(_downloadsDirectory!, 'index.json'));
      await indexFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadPersistedIndex() async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('valkery_offline_downloads_web');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                final entry = OfflineMediaEntry.fromJson(item);
                if (entry.id.isNotEmpty) {
                  _entries[entry.id] = entry;
                }
              }
            }
            _notify();
          }
        }
      } catch (_) {}
      return;
    }
    if (_downloadsDirectory == null) return;
    try {
      final indexFile = File(p.join(_downloadsDirectory!, 'index.json'));
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final entry = OfflineMediaEntry.fromJson(item);
              if (File(entry.localVideoPath).existsSync()) {
                _entries[entry.id] = entry;
              }
            }
          }
          _notify();
        }
      }
    } catch (_) {}
  }

  static String _inferVideoExtension(String url) {
    final clean = url.split('?').first.toLowerCase();
    for (final ext in ['.mp4', '.mkv', '.avi', '.webm', '.ts']) {
      if (clean.endsWith(ext)) return ext;
    }
    return '.mp4';
  }

  void _notify() {
    if (!_updatesController.isClosed) {
      _updatesController.add(allDownloads);
    }
  }

  Future<void> dispose() async {
    for (final sub in _activeDownloads.values) {
      await sub.cancel();
    }
    _activeDownloads.clear();
    await _updatesController.close();
  }
}
