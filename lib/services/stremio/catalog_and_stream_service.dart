import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../models/stremio/stremio_user.dart';

class CatalogAndStreamService {
  static const String cinemetaBaseUrl = 'https://v3-cinemeta.strem.io';
  static const String torrentioBaseUrl = 'https://torrentio.strem.fun';
  static const String openSubtitlesBaseUrl =
      'https://opensubtitles-v3.strem.io';
  static const String nyaaRssBaseUrl = 'https://nyaa.si/?page=rss';
  static const String apibayBaseUrl = 'https://apibay.org/q.php';

  static const List<String> defaultTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://explodie.org:6969/announce',
    'https://1.tracker.eu.org:443/announce',
    'https://tracker.foreverpirates.co:443/announce',
    'https://tracker.tamersunion.org:443/announce',
    'http://tracker.dler.com:6969/announce',
    'http://tracker.renfei.net:8080/announce',
    'wss://tracker.openwebtorrent.com:443/announce',
  ];

  final http.Client _httpClient;

  CatalogAndStreamService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<List<MediaItem>> fetchTopCatalog({
    String type = 'movie',
    String? genre,
  }) async {
    final normalizedType = type == 'anime' ? 'series' : type;
    final genreSuffix = (genre != null && genre.trim().isNotEmpty)
        ? '/genre=${Uri.encodeComponent(genre.trim())}.json'
        : '.json';
    final url = '$cinemetaBaseUrl/catalog/$normalizedType/top$genreSuffix';

    final response = await _httpClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final metas = decoded['metas'] as List<dynamic>? ?? const [];
    return metas
        .whereType<Map<String, dynamic>>()
        .map(MediaItem.fromJson)
        .toList();
  }

  Future<List<MediaItem>> searchCatalog(
    String query, {
    String type = 'all',
    List<StremioAddon>? addons,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return fetchTopCatalog(type: type == 'all' ? 'movie' : type);
    }

    final encodedQuery = Uri.encodeComponent(trimmed);
    final targetTypes = <String>[];
    if (type == 'all') {
      targetTypes.addAll(['movie', 'series']);
    } else if (type == 'anime') {
      targetTypes.add('series');
    } else {
      targetTypes.add(type);
    }

    final urls = <String>{};
    for (final t in targetTypes) {
      urls.add('$cinemetaBaseUrl/catalog/$t/top/search=$encodedQuery.json');
    }

    if (addons != null) {
      for (final addon in addons) {
        if (!addon.supportsResource('catalog')) continue;
        for (final t in targetTypes) {
          if (addon.types.contains(t)) {
            urls.add(
              '${addon.baseUrl}/catalog/$t/top/search=$encodedQuery.json',
            );
          }
        }
      }
    }

    final resultsById = <String, MediaItem>{};
    for (final url in urls) {
      try {
        final response = await _httpClient
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['metas'] is List) {
            for (final raw in decoded['metas'] as List<dynamic>) {
              if (raw is Map<String, dynamic>) {
                final item = MediaItem.fromJson(raw);
                if (item.id.isNotEmpty) {
                  resultsById.putIfAbsent(item.id, () => item);
                }
              }
            }
          }
        }
      } catch (_) {
        // Continue querying remaining catalog endpoints.
      }
    }

    return resultsById.values.toList();
  }

  Future<MediaItem> fetchMediaDetails(String id, String type) async {
    final normalizedType = type == 'anime' ? 'series' : type;
    final url = '$cinemetaBaseUrl/meta/$normalizedType/$id.json';

    final response = await _httpClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to fetch metadata for $id ($type)');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid metadata JSON for $id');
    }

    return MediaItem.fromJson(decoded);
  }

  Future<List<StreamCandidate>> fetchStreams(
    String id,
    String type, {
    int? season,
    int? episode,
    List<StremioAddon>? addons,
  }) async {
    final normalizedType = type == 'anime' ? 'series' : type;
    final isEpisodic =
        normalizedType == 'series' && season != null && episode != null;
    final streamId = isEpisodic ? '$id:$season:$episode' : id;
    final encodedStreamId = Uri.encodeComponent(streamId);

    final addonEndpoints = <MapEntry<String, String>>[];

    // Ensure Torrentio is always queried as primary/guaranteed stream provider
    addonEndpoints.add(
      MapEntry(
        'Torrentio',
        '$torrentioBaseUrl/stream/$normalizedType/$encodedStreamId.json',
      ),
    );

    if (addons != null) {
      for (final addon in addons) {
        if (!addon.supportsResource('stream', type: normalizedType)) continue;
        final endpoint =
            '${addon.baseUrl}/stream/$normalizedType/$encodedStreamId.json';
        final alreadyPresent = addonEndpoints.any((e) => e.value == endpoint);
        if (!alreadyPresent) {
          addonEndpoints.add(MapEntry(addon.name, endpoint));
        }
      }
    }

    final candidates = <StreamCandidate>[];
    for (final entry in addonEndpoints) {
      try {
        final response = await _httpClient
            .get(Uri.parse(entry.value))
            .timeout(const Duration(seconds: 12));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['streams'] is List) {
            for (final raw in decoded['streams'] as List<dynamic>) {
              if (raw is Map<String, dynamic>) {
                candidates.add(
                  parseTorrentioStream(raw, addonName: entry.key),
                );
              }
            }
          }
        }
      } catch (_) {
        // Ignore single addon timeout/failure.
      }
    }

    if (candidates.isEmpty) {
      try {
        final apibay = await searchApibay(id);
        candidates.addAll(apibay);
      } catch (_) {}
    }

    candidates.sort((a, b) {
      final qCmp = b.qualityWeight.compareTo(a.qualityWeight);
      if (qCmp != 0) return qCmp;
      return b.seeders.compareTo(a.seeders);
    });

    return candidates;
  }

  Future<List<StreamCandidate>> searchNyaaAnime(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final url =
        '$nyaaRssBaseUrl&q=${Uri.encodeQueryComponent(trimmed)}&c=1_0&f=0';

    final response = await _httpClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    return parseNyaaRssXml(response.body);
  }

  Future<List<StreamCandidate>> searchApibay(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final url = '$apibayBaseUrl?q=${Uri.encodeQueryComponent(trimmed)}';

    final response = await _httpClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    final results = <StreamCandidate>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final name = (entry['name'] ?? '').toString();
      final infoHash = (entry['info_hash'] ?? '').toString().toLowerCase();
      if (name.isEmpty ||
          name == 'No results returned' ||
          infoHash.isEmpty ||
          RegExp(r'^0+$').hasMatch(infoHash)) {
        continue;
      }

      final seeders = int.tryParse((entry['seeders'] ?? '0').toString()) ?? 0;
      final sizeBytes = int.tryParse((entry['size'] ?? '0').toString()) ?? 0;
      final formattedSize = _formatBytes(sizeBytes);
      final quality = _detectQuality('$name ');

      results.add(
        StreamCandidate(
          title: name,
          name: 'Apibay $quality',
          infoHash: infoHash,
          magnetUri: buildMagnetUri(infoHash, title: name),
          quality: quality,
          size: formattedSize,
          seeders: seeders,
          sourceTracker: 'ThePirateBay / Apibay',
          languages: _detectLanguages(name),
          addonName: 'Apibay Direct',
        ),
      );
    }

    results.sort((a, b) => b.seeders.compareTo(a.seeders));
    return results;
  }

  Future<List<SubtitleTrack>> fetchSubtitles(
    String id,
    String type, {
    int? season,
    int? episode,
    String? videoHash,
    List<StremioAddon>? addons,
  }) async {
    final normalizedType = type == 'anime' ? 'series' : type;
    final isEpisodic =
        normalizedType == 'series' && season != null && episode != null;
    final baseId = isEpisodic ? '$id:$season:$episode' : id;
    final pathSegment = (videoHash != null && videoHash.trim().isNotEmpty)
        ? '$baseId/videoHash=${Uri.encodeComponent(videoHash.trim())}'
        : baseId;

    final endpoints = <MapEntry<String, String>>[
      MapEntry(
        'OpenSubtitles v3',
        '$openSubtitlesBaseUrl/subtitles/$normalizedType/$pathSegment.json',
      ),
    ];

    if (addons != null) {
      for (final addon in addons) {
        if (!addon.supportsResource('subtitles', type: normalizedType)) {
          continue;
        }
        final url =
            '${addon.baseUrl}/subtitles/$normalizedType/$pathSegment.json';
        if (!endpoints.any((e) => e.value == url)) {
          endpoints.add(MapEntry(addon.name, url));
        }
      }
    }

    final tracks = <SubtitleTrack>[];
    for (final entry in endpoints) {
      try {
        final response = await _httpClient
            .get(Uri.parse(entry.value))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> &&
              decoded['subtitles'] is List) {
            for (final raw in decoded['subtitles'] as List<dynamic>) {
              if (raw is Map<String, dynamic>) {
                final track = SubtitleTrack.fromJson(
                  raw,
                  addonName: entry.key,
                );
                if (track.url.isNotEmpty) {
                  tracks.add(track);
                }
              }
            }
          }
        }
      } catch (_) {
        // Ignore single subtitle addon error.
      }
    }

    tracks.sort((a, b) {
      int priority(SubtitleTrack t) {
        if (t.isSpanish) return 0;
        if (t.isEnglish) return 1;
        return 2;
      }

      final pCmp = priority(a).compareTo(priority(b));
      if (pCmp != 0) return pCmp;
      return a.label.compareTo(b.label);
    });

    return tracks;
  }

  static StreamCandidate parseTorrentioStream(
    Map<String, dynamic> raw, {
    String addonName = 'Torrentio',
  }) {
    final name = (raw['name'] ?? addonName).toString();
    final title = (raw['title'] ?? raw['description'] ?? '').toString();
    final infoHash = (raw['infoHash'] ?? '').toString().toLowerCase();
    final fileIdx = raw['fileIdx'] != null
        ? int.tryParse(raw['fileIdx'].toString())
        : null;
    final directUrl = (raw['url'] ?? '').toString();
    final combined = '$name\n$title';

    final quality = _detectQuality(combined);

    int seeders = 0;
    final seederMatch = RegExp(r'👤\s*(\d+)').firstMatch(title);
    if (seederMatch != null) {
      seeders = int.tryParse(seederMatch.group(1)!) ?? 0;
    }

    String size = '';
    final sizeMatch = RegExp(
      r'💾\s*([\d.,]+\s*(?:GB|MB|KB|TB))',
      caseSensitive: false,
    ).firstMatch(title);
    if (sizeMatch != null) {
      size = sizeMatch.group(1)!.trim();
    }

    String tracker = addonName;
    final trackerMatch = RegExp(r'⚙️\s*([^\n\r]+)').firstMatch(title);
    if (trackerMatch != null) {
      tracker = trackerMatch.group(1)!.trim();
    }

    final extraTrackers = <String>[];
    final rawSources = <String>[];
    if (raw['sources'] is List) {
      for (final s in raw['sources'] as List<dynamic>) {
        final str = s.toString();
        rawSources.add(str);
        if (str.startsWith('tracker:')) {
          extraTrackers.add(str.substring('tracker:'.length));
        }
      }
    }

    final magnetUri = infoHash.isNotEmpty
        ? buildMagnetUri(
            infoHash,
            title: title.split('\n').first.trim(),
            extraTrackers: extraTrackers,
          )
        : '';

    final behaviorHints = raw['behaviorHints'] is Map<String, dynamic>
        ? raw['behaviorHints'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return StreamCandidate(
      title: title,
      name: name,
      infoHash: infoHash,
      fileIdx: fileIdx,
      url: directUrl,
      magnetUri: magnetUri,
      quality: quality,
      size: size,
      seeders: seeders,
      sourceTracker: tracker,
      languages: _detectLanguages(combined),
      addonName: addonName,
      sources: rawSources,
      behaviorHints: behaviorHints,
    );
  }

  static List<StreamCandidate> parseNyaaRssXml(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final items = document.findAllElements('item');
    final results = <StreamCandidate>[];

    for (final item in items) {
      final title = _xmlText(item, 'title') ?? 'Nyaa Anime Release';
      final link = _xmlText(item, 'link') ?? '';
      final infoHash =
          (_xmlText(item, 'nyaa:infoHash') ?? _xmlText(item, 'infoHash') ?? '')
              .toLowerCase();
      final seeders =
          int.tryParse(
            _xmlText(item, 'nyaa:seeders') ?? _xmlText(item, 'seeders') ?? '0',
          ) ??
          0;
      final size =
          _xmlText(item, 'nyaa:size') ?? _xmlText(item, 'size') ?? '';
      final quality = _detectQuality(title);
      final magnet = infoHash.isNotEmpty
          ? buildMagnetUri(infoHash, title: title)
          : (link.startsWith('magnet:') ? link : '');

      results.add(
        StreamCandidate(
          title: title,
          name: 'Nyaa $quality',
          infoHash: infoHash,
          url: link.startsWith('http') ? link : '',
          magnetUri: magnet,
          quality: quality,
          size: size,
          seeders: seeders,
          sourceTracker: 'Nyaa.si',
          languages: _detectLanguages(title),
          addonName: 'Nyaa Indexer',
        ),
      );
    }

    results.sort((a, b) => b.seeders.compareTo(a.seeders));
    return results;
  }

  static String buildMagnetUri(
    String infoHash, {
    String? title,
    List<String>? extraTrackers,
  }) {
    final cleanHash = infoHash.trim().toLowerCase();
    final buffer = StringBuffer('magnet:?xt=urn:btih:$cleanHash');
    if (title != null && title.trim().isNotEmpty) {
      buffer.write('&dn=${Uri.encodeQueryComponent(title.trim())}');
    }
    final trackers = <String>{
      ...defaultTrackers,
      ...?extraTrackers,
    };
    for (final tr in trackers) {
      if (tr.trim().isNotEmpty) {
        buffer.write('&tr=${Uri.encodeQueryComponent(tr.trim())}');
      }
    }
    return buffer.toString();
  }

  static String? _xmlText(XmlElement parent, String tagName) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.qualified == tagName || child.name.local == tagName) {
        return child.innerText.trim();
      }
    }
    return null;
  }

  static String _detectQuality(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('2160P') || upper.contains('4K') || upper.contains('UHD')) {
      return '4K';
    }
    if (upper.contains('1080P') || upper.contains('FHD')) {
      return '1080p';
    }
    if (upper.contains('720P') || upper.contains('HD')) {
      return '720p';
    }
    if (upper.contains('480P') || upper.contains('SD')) {
      return '480p';
    }
    return '1080p';
  }

  static List<String> _detectLanguages(String text) {
    final lower = text.toLowerCase();
    final langs = <String>[];
    if (lower.contains('latino') ||
        lower.contains('spanish') ||
        lower.contains('español') ||
        lower.contains('🇪🇸') ||
        lower.contains('🇲🇽') ||
        lower.contains('multi') ||
        lower.contains('dual')) {
      langs.add('spa');
    }
    if (lower.contains('english') ||
        lower.contains('eng') ||
        lower.contains('🇬🇧') ||
        lower.contains('🇺🇸') ||
        lower.contains('subs') ||
        lower.contains('multi') ||
        lower.contains('dual')) {
      langs.add('eng');
    }
    if (lower.contains('jpn') ||
        lower.contains('japanese') ||
        lower.contains('🇯🇵') ||
        lower.contains('dual')) {
      langs.add('jpn');
    }
    if (langs.isEmpty) {
      langs.add('eng');
    }
    return langs;
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
}
