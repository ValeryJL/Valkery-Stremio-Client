class StreamCandidate {
  final String title;
  final String name;
  final String infoHash;
  final int? fileIdx;
  final String url;
  final String magnetUri;
  final String quality;
  final String size;
  final int seeders;
  final String sourceTracker;
  final List<String> languages;
  final String addonName;
  final Map<String, dynamic> behaviorHints;

  const StreamCandidate({
    required this.title,
    required this.name,
    this.infoHash = '',
    this.fileIdx,
    this.url = '',
    this.magnetUri = '',
    this.quality = '1080p',
    this.size = '',
    this.seeders = 0,
    this.sourceTracker = 'DHT',
    this.languages = const [],
    this.addonName = 'Torrentio',
    this.behaviorHints = const {},
  });

  bool get isTorrent => infoHash.isNotEmpty || magnetUri.startsWith('magnet:');
  bool get isDirectHttp => url.startsWith('http://') || url.startsWith('https://');
  String get playbackUrl => url.isNotEmpty ? url : (infoHash.isNotEmpty ? 'http://127.0.0.1:11470/$infoHash/${fileIdx ?? 0}' : '');

  int get qualityWeight {
    final q = quality.toUpperCase();
    if (q.contains('4K') || q.contains('2160P')) return 4;
    if (q.contains('1080P')) return 3;
    if (q.contains('720P')) return 2;
    if (q.contains('480P')) return 1;
    return 0;
  }

  StreamCandidate copyWith({
    String? title,
    String? name,
    String? infoHash,
    int? fileIdx,
    String? url,
    String? magnetUri,
    String? quality,
    String? size,
    int? seeders,
    String? sourceTracker,
    List<String>? languages,
    String? addonName,
    Map<String, dynamic>? behaviorHints,
  }) {
    return StreamCandidate(
      title: title ?? this.title,
      name: name ?? this.name,
      infoHash: infoHash ?? this.infoHash,
      fileIdx: fileIdx ?? this.fileIdx,
      url: url ?? this.url,
      magnetUri: magnetUri ?? this.magnetUri,
      quality: quality ?? this.quality,
      size: size ?? this.size,
      seeders: seeders ?? this.seeders,
      sourceTracker: sourceTracker ?? this.sourceTracker,
      languages: languages ?? this.languages,
      addonName: addonName ?? this.addonName,
      behaviorHints: behaviorHints ?? this.behaviorHints,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'name': name,
      'infoHash': infoHash,
      'fileIdx': fileIdx,
      'url': url,
      'magnetUri': magnetUri,
      'quality': quality,
      'size': size,
      'seeders': seeders,
      'sourceTracker': sourceTracker,
      'languages': languages,
      'addonName': addonName,
      'behaviorHints': behaviorHints,
    };
  }

  factory StreamCandidate.fromJson(Map<String, dynamic> json) {
    final rawLangs = json['languages'] as List<dynamic>? ?? const [];
    final hints = json['behaviorHints'] is Map<String, dynamic>
        ? json['behaviorHints'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return StreamCandidate(
      title: (json['title'] ?? json['description'] ?? '').toString(),
      name: (json['name'] ?? 'Stream').toString(),
      infoHash: (json['infoHash'] ?? '').toString().toLowerCase(),
      fileIdx: json['fileIdx'] != null
          ? int.tryParse(json['fileIdx'].toString())
          : null,
      url: (json['url'] ?? '').toString(),
      magnetUri: (json['magnetUri'] ?? '').toString(),
      quality: (json['quality'] ?? '1080p').toString(),
      size: (json['size'] ?? '').toString(),
      seeders: int.tryParse((json['seeders'] ?? '0').toString()) ?? 0,
      sourceTracker: (json['sourceTracker'] ?? 'Torrentio').toString(),
      languages: rawLangs.map((e) => e.toString()).toList(),
      addonName: (json['addonName'] ?? 'Torrentio').toString(),
      behaviorHints: hints,
    );
  }
}

class TorrentFileEntry {
  final int index;
  final String path;
  final String name;
  final int sizeBytes;
  final int? seasonNumber;
  final int? episodeNumber;
  final bool isVideo;
  final bool isSubtitle;
  final bool selected;

  const TorrentFileEntry({
    required this.index,
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.seasonNumber,
    this.episodeNumber,
    this.isVideo = true,
    this.isSubtitle = false,
    this.selected = true,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return '0 B';
    const kb = 1024.0;
    const mb = kb * 1024.0;
    const gb = mb * 1024.0;
    if (sizeBytes >= gb) {
      return '${(sizeBytes / gb).toStringAsFixed(2)} GB';
    }
    if (sizeBytes >= mb) {
      return '${(sizeBytes / mb).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / kb).toStringAsFixed(0)} KB';
  }

  TorrentFileEntry copyWith({
    int? index,
    String? path,
    String? name,
    int? sizeBytes,
    int? seasonNumber,
    int? episodeNumber,
    bool? isVideo,
    bool? isSubtitle,
    bool? selected,
  }) {
    return TorrentFileEntry(
      index: index ?? this.index,
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      isVideo: isVideo ?? this.isVideo,
      isSubtitle: isSubtitle ?? this.isSubtitle,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'path': path,
      'name': name,
      'sizeBytes': sizeBytes,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'isVideo': isVideo,
      'isSubtitle': isSubtitle,
      'selected': selected,
    };
  }

  factory TorrentFileEntry.fromJson(Map<String, dynamic> json) {
    return TorrentFileEntry(
      index: int.tryParse((json['index'] ?? '0').toString()) ?? 0,
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      sizeBytes: int.tryParse((json['sizeBytes'] ?? '0').toString()) ?? 0,
      seasonNumber: json['seasonNumber'] != null
          ? int.tryParse(json['seasonNumber'].toString())
          : null,
      episodeNumber: json['episodeNumber'] != null
          ? int.tryParse(json['episodeNumber'].toString())
          : null,
      isVideo: json['isVideo'] != false,
      isSubtitle: json['isSubtitle'] == true,
      selected: json['selected'] != false,
    );
  }
}
