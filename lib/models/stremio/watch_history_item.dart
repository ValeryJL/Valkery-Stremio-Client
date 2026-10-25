class LibraryWatchState {
  final String id;
  final String name;
  final String type;
  final String poster;
  final String videoId;
  final int timeOffset;
  final int duration;
  final int timesWatched;
  final int flaggedWatched;
  final List<String> watchedEpisodes;
  final DateTime lastWatched;
  final bool pendingOfflineSync;

  const LibraryWatchState({
    required this.id,
    required this.name,
    this.type = 'movie',
    this.poster = '',
    required this.videoId,
    this.timeOffset = 0,
    this.duration = 0,
    this.timesWatched = 0,
    this.flaggedWatched = 0,
    this.watchedEpisodes = const [],
    required this.lastWatched,
    this.pendingOfflineSync = false,
  });

  double get progressRatio {
    if (duration <= 0) return flaggedWatched > 0 ? 1.0 : 0.0;
    return (timeOffset / duration).clamp(0.0, 1.0);
  }

  bool get isCompleted =>
      flaggedWatched > 0 || (duration > 0 && (timeOffset / duration) >= 0.9);

  int? get currentSeason {
    final parts = videoId.split(':');
    if (parts.length >= 3) {
      return int.tryParse(parts[1]);
    }
    return null;
  }

  int? get currentEpisode {
    final parts = videoId.split(':');
    if (parts.length >= 3) {
      return int.tryParse(parts[2]);
    }
    return null;
  }

  LibraryWatchState copyWith({
    String? id,
    String? name,
    String? type,
    String? poster,
    String? videoId,
    int? timeOffset,
    int? duration,
    int? timesWatched,
    int? flaggedWatched,
    List<String>? watchedEpisodes,
    DateTime? lastWatched,
    bool? pendingOfflineSync,
  }) {
    return LibraryWatchState(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      poster: poster ?? this.poster,
      videoId: videoId ?? this.videoId,
      timeOffset: timeOffset ?? this.timeOffset,
      duration: duration ?? this.duration,
      timesWatched: timesWatched ?? this.timesWatched,
      flaggedWatched: flaggedWatched ?? this.flaggedWatched,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      lastWatched: lastWatched ?? this.lastWatched,
      pendingOfflineSync: pendingOfflineSync ?? this.pendingOfflineSync,
    );
  }

  /// Formats this state into a Stremio `libraryItem` document suitable for
  /// `POST https://api.strem.io/api/datastorePut`.
  Map<String, dynamic> toStremioDatastoreItem() {
    final isoNow = lastWatched.toUtc().toIso8601String();
    final watchedString = watchedEpisodes.isNotEmpty
        ? watchedEpisodes.join('|')
        : (flaggedWatched > 0 ? '$videoId:1:1' : '');

    return {
      '_id': id,
      'name': name,
      'type': type,
      'poster': poster,
      'posterShape': 'poster',
      'removed': false,
      'temp': false,
      '_ctime': isoNow,
      '_mtime': isoNow,
      'state': {
        'lastWatched': isoNow,
        'timeWatched': timeOffset,
        'timeOffset': timeOffset,
        'overallTimeWatched': timeOffset,
        'timesWatched': timesWatched,
        'flaggedWatched': flaggedWatched,
        'duration': duration,
        'video_id': videoId,
        'watched': watchedString,
        'noNotif': false,
      },
    };
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'id': id,
      'name': name,
      'type': type,
      'poster': poster,
      'videoId': videoId,
      'timeOffset': timeOffset,
      'duration': duration,
      'timesWatched': timesWatched,
      'flaggedWatched': flaggedWatched,
      'watchedEpisodes': watchedEpisodes,
      'lastWatched': lastWatched.toUtc().toIso8601String(),
      'pendingOfflineSync': pendingOfflineSync,
    };
  }

  factory LibraryWatchState.fromJson(Map<String, dynamic> json) {
    final state = json['state'] is Map<String, dynamic>
        ? json['state'] as Map<String, dynamic>
        : json;

    final id = (json['_id'] ?? json['id'] ?? '').toString();
    final name = (json['name'] ?? 'Unknown').toString();
    final type = (json['type'] ?? 'movie').toString();
    final poster = (json['poster'] ?? '').toString();
    final videoId =
        (state['video_id'] ?? state['videoId'] ?? json['videoId'] ?? id)
            .toString();
    final timeOffset =
        int.tryParse((state['timeOffset'] ?? json['timeOffset'] ?? '0').toString()) ??
        0;
    final duration =
        int.tryParse((state['duration'] ?? json['duration'] ?? '0').toString()) ??
        0;
    final timesWatched =
        int.tryParse(
          (state['timesWatched'] ?? json['timesWatched'] ?? '0').toString(),
        ) ??
        0;
    final flaggedWatched =
        int.tryParse(
          (state['flaggedWatched'] ?? json['flaggedWatched'] ?? '0').toString(),
        ) ??
        0;

    final watchedEpisodes = <String>[];
    if (json['watchedEpisodes'] is List) {
      for (final e in json['watchedEpisodes'] as List<dynamic>) {
        watchedEpisodes.add(e.toString());
      }
    } else if (state['watched'] is String &&
        (state['watched'] as String).isNotEmpty) {
      final rawWatched = state['watched'] as String;
      if (rawWatched.contains('|')) {
        watchedEpisodes.addAll(
          rawWatched.split('|').where((s) => s.trim().isNotEmpty),
        );
      } else {
        watchedEpisodes.add(rawWatched);
      }
    }

    final rawLastWatched =
        (state['lastWatched'] ?? json['lastWatched'] ?? json['_mtime'])
            ?.toString();
    final lastWatched = rawLastWatched != null
        ? (DateTime.tryParse(rawLastWatched) ?? DateTime.now().toUtc())
        : DateTime.now().toUtc();

    return LibraryWatchState(
      id: id,
      name: name,
      type: type,
      poster: poster,
      videoId: videoId,
      timeOffset: timeOffset,
      duration: duration,
      timesWatched: timesWatched,
      flaggedWatched: flaggedWatched,
      watchedEpisodes: watchedEpisodes,
      lastWatched: lastWatched,
      pendingOfflineSync: json['pendingOfflineSync'] == true,
    );
  }
}
