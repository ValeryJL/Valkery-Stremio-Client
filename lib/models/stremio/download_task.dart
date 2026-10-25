import 'stream_candidate.dart';

class DownloadTaskStatus {
  static const String queued = 'queued';
  static const String downloading = 'downloading';
  static const String paused = 'paused';
  static const String completed = 'completed';
  static const String failed = 'failed';
}

class DownloadTaskItem {
  final String id;
  final String mediaId;
  final String mediaTitle;
  final int? season;
  final int? episode;
  final String infoHash;
  final String magnetUri;
  final List<int> selectedFileIndices;
  final String status;
  final int totalBytes;
  final int completedBytes;
  final int downloadSpeedBytes;
  final int seeders;
  final String savePath;
  final List<TorrentFileEntry> files;
  final DateTime createdAt;

  const DownloadTaskItem({
    required this.id,
    required this.mediaId,
    required this.mediaTitle,
    this.season,
    this.episode,
    required this.infoHash,
    required this.magnetUri,
    this.selectedFileIndices = const [],
    this.status = DownloadTaskStatus.queued,
    this.totalBytes = 0,
    this.completedBytes = 0,
    this.downloadSpeedBytes = 0,
    this.seeders = 0,
    required this.savePath,
    this.files = const [],
    required this.createdAt,
  });

  double get progress {
    if (status == DownloadTaskStatus.completed) return 1.0;
    if (totalBytes <= 0) return 0.0;
    return (completedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isCompleted => status == DownloadTaskStatus.completed;
  bool get isDownloading => status == DownloadTaskStatus.downloading;
  bool get isPaused => status == DownloadTaskStatus.paused;

  /// Generates the `aria2c` `--select-file=...` 1-based argument string.
  String get aria2SelectFileArg {
    if (selectedFileIndices.isEmpty) return '';
    final oneBased = selectedFileIndices.map((idx) => idx + 1).toList()..sort();
    return '--select-file=${oneBased.join(',')}';
  }

  DownloadTaskItem copyWith({
    String? id,
    String? mediaId,
    String? mediaTitle,
    int? season,
    int? episode,
    String? infoHash,
    String? magnetUri,
    List<int>? selectedFileIndices,
    String? status,
    int? totalBytes,
    int? completedBytes,
    int? downloadSpeedBytes,
    int? seeders,
    String? savePath,
    List<TorrentFileEntry>? files,
    DateTime? createdAt,
  }) {
    return DownloadTaskItem(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      infoHash: infoHash ?? this.infoHash,
      magnetUri: magnetUri ?? this.magnetUri,
      selectedFileIndices: selectedFileIndices ?? this.selectedFileIndices,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      completedBytes: completedBytes ?? this.completedBytes,
      downloadSpeedBytes: downloadSpeedBytes ?? this.downloadSpeedBytes,
      seeders: seeders ?? this.seeders,
      savePath: savePath ?? this.savePath,
      files: files ?? this.files,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaId': mediaId,
      'mediaTitle': mediaTitle,
      'season': season,
      'episode': episode,
      'infoHash': infoHash,
      'magnetUri': magnetUri,
      'selectedFileIndices': selectedFileIndices,
      'status': status,
      'totalBytes': totalBytes,
      'completedBytes': completedBytes,
      'downloadSpeedBytes': downloadSpeedBytes,
      'seeders': seeders,
      'savePath': savePath,
      'files': files.map((f) => f.toJson()).toList(),
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  factory DownloadTaskItem.fromJson(Map<String, dynamic> json) {
    final rawIndices = json['selectedFileIndices'] as List<dynamic>? ?? const [];
    final rawFiles = json['files'] as List<dynamic>? ?? const [];

    return DownloadTaskItem(
      id: (json['id'] ?? '').toString(),
      mediaId: (json['mediaId'] ?? '').toString(),
      mediaTitle: (json['mediaTitle'] ?? '').toString(),
      season: json['season'] != null
          ? int.tryParse(json['season'].toString())
          : null,
      episode: json['episode'] != null
          ? int.tryParse(json['episode'].toString())
          : null,
      infoHash: (json['infoHash'] ?? '').toString(),
      magnetUri: (json['magnetUri'] ?? '').toString(),
      selectedFileIndices: rawIndices
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .toList(),
      status: (json['status'] ?? DownloadTaskStatus.queued).toString(),
      totalBytes: int.tryParse((json['totalBytes'] ?? '0').toString()) ?? 0,
      completedBytes:
          int.tryParse((json['completedBytes'] ?? '0').toString()) ?? 0,
      downloadSpeedBytes:
          int.tryParse((json['downloadSpeedBytes'] ?? '0').toString()) ?? 0,
      seeders: int.tryParse((json['seeders'] ?? '0').toString()) ?? 0,
      savePath: (json['savePath'] ?? '').toString(),
      files: rawFiles
          .whereType<Map<String, dynamic>>()
          .map(TorrentFileEntry.fromJson)
          .toList(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
    );
  }
}
