class EpisodeItem {
  final String id;
  final int season;
  final int episode;
  final String title;
  final String overview;
  final String thumbnail;
  final DateTime? released;
  final bool watched;
  final int progressSeconds;
  final int durationSeconds;

  const EpisodeItem({
    required this.id,
    required this.season,
    required this.episode,
    required this.title,
    this.overview = '',
    this.thumbnail = '',
    this.released,
    this.watched = false,
    this.progressSeconds = 0,
    this.durationSeconds = 0,
  });

  String get code =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  double get progressRatio {
    if (durationSeconds <= 0) return watched ? 1.0 : 0.0;
    final ratio = progressSeconds / durationSeconds;
    return ratio.clamp(0.0, 1.0);
  }

  EpisodeItem copyWith({
    String? id,
    int? season,
    int? episode,
    String? title,
    String? overview,
    String? thumbnail,
    DateTime? released,
    bool? watched,
    int? progressSeconds,
    int? durationSeconds,
  }) {
    return EpisodeItem(
      id: id ?? this.id,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      thumbnail: thumbnail ?? this.thumbnail,
      released: released ?? this.released,
      watched: watched ?? this.watched,
      progressSeconds: progressSeconds ?? this.progressSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'season': season,
      'episode': episode,
      'name': title,
      'title': title,
      'overview': overview,
      'thumbnail': thumbnail,
      'released': released?.toIso8601String(),
      'watched': watched,
      'progressSeconds': progressSeconds,
      'durationSeconds': durationSeconds,
    };
  }

  factory EpisodeItem.fromJson(
    Map<String, dynamic> json, {
    String? parentId,
  }) {
    final seasonNum = int.tryParse((json['season'] ?? '1').toString()) ?? 1;
    final episodeNum =
        int.tryParse((json['episode'] ?? json['number'] ?? '1').toString()) ??
        1;
    final rawId = (json['id'] ?? '').toString();
    final resolvedId = rawId.isNotEmpty
        ? rawId
        : (parentId != null ? '$parentId:$seasonNum:$episodeNum' : '');
    final title = (json['name'] ?? json['title'] ?? 'Episode $episodeNum')
        .toString();
    final overview =
        (json['overview'] ?? json['description'] ?? '').toString();
    final thumbnail = (json['thumbnail'] ?? '').toString();
    final releasedRaw = json['released']?.toString();

    return EpisodeItem(
      id: resolvedId,
      season: seasonNum,
      episode: episodeNum,
      title: title,
      overview: overview,
      thumbnail: thumbnail,
      released: releasedRaw != null ? DateTime.tryParse(releasedRaw) : null,
      watched: json['watched'] == true,
      progressSeconds:
          int.tryParse((json['progressSeconds'] ?? '0').toString()) ?? 0,
      durationSeconds:
          int.tryParse((json['durationSeconds'] ?? '0').toString()) ?? 0,
    );
  }
}

class MediaItem {
  final String id;
  final String type;
  final String name;
  final String poster;
  final String background;
  final String year;
  final String imdbRating;
  final String description;
  final List<String> genres;
  final List<EpisodeItem> episodes;
  final List<String> cast;
  final List<String> director;
  final String runtime;
  final String releaseDate;

  const MediaItem({
    required this.id,
    required this.type,
    required this.name,
    this.poster = '',
    this.background = '',
    this.year = '',
    this.imdbRating = '',
    this.description = '',
    this.genres = const [],
    this.episodes = const [],
    this.cast = const [],
    this.director = const [],
    this.runtime = '',
    this.releaseDate = '',
  });

  String get releaseInfo => releaseDate.isNotEmpty ? releaseDate : year;
  bool get isSeries => type == 'series' || type == 'anime' || episodes.isNotEmpty;

  List<int> get seasons {
    final set = <int>{};
    for (final ep in episodes) {
      if (ep.season > 0) {
        set.add(ep.season);
      }
    }
    if (set.isEmpty && episodes.isNotEmpty) {
      set.add(episodes.first.season);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<EpisodeItem> episodesForSeason(int season) {
    final list = episodes.where((e) => e.season == season).toList();
    list.sort((a, b) => a.episode.compareTo(b.episode));
    return list;
  }

  MediaItem copyWith({
    String? id,
    String? type,
    String? name,
    String? poster,
    String? background,
    String? year,
    String? imdbRating,
    String? description,
    List<String>? genres,
    List<EpisodeItem>? episodes,
    List<String>? cast,
    List<String>? director,
    String? runtime,
    String? releaseDate,
  }) {
    return MediaItem(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      poster: poster ?? this.poster,
      background: background ?? this.background,
      year: year ?? this.year,
      imdbRating: imdbRating ?? this.imdbRating,
      description: description ?? this.description,
      genres: genres ?? this.genres,
      episodes: episodes ?? this.episodes,
      cast: cast ?? this.cast,
      director: director ?? this.director,
      runtime: runtime ?? this.runtime,
      releaseDate: releaseDate ?? this.releaseDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'poster': poster,
      'background': background,
      'year': year,
      'imdbRating': imdbRating,
      'description': description,
      'genres': genres,
      'videos': episodes.map((e) => e.toJson()).toList(),
      'cast': cast,
      'director': director,
      'runtime': runtime,
      'released': releaseDate,
    };
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] is Map<String, dynamic>
        ? json['meta'] as Map<String, dynamic>
        : json;
    final id = (meta['id'] ?? meta['imdb_id'] ?? '').toString();
    final type = (meta['type'] ?? 'movie').toString();
    final name = (meta['name'] ?? meta['title'] ?? 'Unknown Title').toString();
    var poster = (meta['poster'] ?? '').toString();
    if (poster.isEmpty && id.startsWith('tt')) {
      poster = 'https://images.metahub.space/poster/medium/$id/img.jpg';
    }
    final background = (meta['background'] ?? meta['backdrop'] ?? poster).toString();
    final year = (meta['year'] ?? meta['releaseInfo'] ?? '').toString();
    final releaseDate = (meta['released'] ?? meta['releaseInfo'] ?? year).toString();
    final runtime = (meta['runtime'] ?? '').toString();
    final imdbRating = (meta['imdbRating'] ?? meta['rating'] ?? '').toString();
    final description =
        (meta['description'] ?? meta['overview'] ?? '').toString();

    final rawGenres =
        (meta['genres'] ?? meta['genre'] ?? const <dynamic>[]) as List<dynamic>;
    final genres = rawGenres.map((g) => g.toString()).toList();

    final rawCast =
        (meta['cast'] ?? meta['actors'] ?? const <dynamic>[]) as List<dynamic>;
    final cast = rawCast
        .map((c) => c is Map ? (c['name'] ?? '').toString() : c.toString())
        .where((s) => s.isNotEmpty)
        .toList();

    final rawDir = meta['director'] ?? meta['directors'];
    final director = <String>[];
    if (rawDir is List) {
      director.addAll(
        rawDir
            .map((d) => d is Map ? (d['name'] ?? '').toString() : d.toString())
            .where((s) => s.isNotEmpty),
      );
    } else if (rawDir is String && rawDir.isNotEmpty) {
      director.add(rawDir);
    }

    final rawVideos =
        (meta['videos'] ?? meta['episodes'] ?? const <dynamic>[])
            as List<dynamic>;
    final episodes = rawVideos
        .whereType<Map<String, dynamic>>()
        .map((v) => EpisodeItem.fromJson(v, parentId: id))
        .toList();

    episodes.sort((a, b) {
      final sCmp = a.season.compareTo(b.season);
      if (sCmp != 0) return sCmp;
      return a.episode.compareTo(b.episode);
    });

    return MediaItem(
      id: id,
      type: type,
      name: name,
      poster: poster,
      background: background,
      year: year,
      imdbRating: imdbRating,
      description: description,
      genres: genres,
      episodes: episodes,
      cast: cast,
      director: director,
      runtime: runtime,
      releaseDate: releaseDate,
    );
  }
}

class SubtitleTrack {
  final String id;
  final String url;
  final String lang;
  final String label;
  final String addonName;

  const SubtitleTrack({
    required this.id,
    required this.url,
    required this.lang,
    required this.label,
    this.addonName = 'OpenSubtitles v3',
  });

  String get displayTitle => label.isNotEmpty ? label : (lang.isNotEmpty ? lang : id);

  bool get isSpanish {
    final normalized = lang.toLowerCase();
    return normalized == 'spa' ||
        normalized == 'es' ||
        normalized.startsWith('es-') ||
        normalized.contains('spanish') ||
        normalized.contains('español');
  }

  bool get isEnglish {
    final normalized = lang.toLowerCase();
    return normalized == 'eng' ||
        normalized == 'en' ||
        normalized.startsWith('en-') ||
        normalized.contains('english');
  }

  SubtitleTrack copyWith({
    String? id,
    String? url,
    String? lang,
    String? label,
    String? addonName,
  }) {
    return SubtitleTrack(
      id: id ?? this.id,
      url: url ?? this.url,
      lang: lang ?? this.lang,
      label: label ?? this.label,
      addonName: addonName ?? this.addonName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'lang': lang,
      'label': label,
      'addonName': addonName,
    };
  }

  factory SubtitleTrack.fromJson(
    Map<String, dynamic> json, {
    String addonName = 'OpenSubtitles v3',
  }) {
    final lang = (json['lang'] ?? 'und').toString();
    final id = (json['id'] ?? json['url'] ?? '').toString();
    final url = (json['url'] ?? '').toString();
    final humanLang = _humanizeLanguage(lang);
    final rawLabel = (json['label'] ?? '').toString().trim();
    final releaseName = (json['movieReleaseName'] ?? json['subtitleFileName'] ?? '').toString().trim();
    final releaseGroup = (json['releaseGroup'] ?? '').toString().trim();

    String label;
    if (rawLabel.isNotEmpty) {
      label = rawLabel;
    } else if (releaseName.isNotEmpty) {
      final cleanRelease = releaseName.replaceAll(RegExp(r'\.(srt|vtt|ass|ssa|sub)$', caseSensitive: false), '');
      label = '$humanLang • $cleanRelease';
    } else if (releaseGroup.isNotEmpty) {
      label = '$humanLang ($releaseGroup)';
    } else {
      label = humanLang;
    }

    return SubtitleTrack(
      id: id,
      url: url,
      lang: lang,
      label: label,
      addonName: (json['addonName'] ?? addonName).toString(),
    );
  }

  static String _humanizeLanguage(String code) {
    final lower = code.trim().toLowerCase();
    switch (lower) {
      case 'spa':
      case 'es':
      case 'es-es':
      case 'esp':
        return 'Español';
      case 'spl':
      case 'lat':
      case 'es-la':
      case 'es-419':
      case 'es-mx':
        return 'Español Latino';
      case 'eng':
      case 'en':
      case 'en-us':
      case 'en-gb':
        return 'Inglés';
      case 'pob':
      case 'pt-br':
        return 'Portugués (Brasil)';
      case 'por':
      case 'pt':
        return 'Portugués';
      case 'fre':
      case 'fra':
      case 'fr':
        return 'Francés';
      case 'deu':
      case 'ger':
      case 'de':
        return 'Alemán';
      case 'ita':
      case 'it':
        return 'Italiano';
      case 'jpn':
      case 'ja':
        return 'Japonés';
      case 'kor':
      case 'ko':
        return 'Coreano';
      case 'rus':
      case 'ru':
        return 'Ruso';
      case 'ara':
      case 'ar':
        return 'Árabe';
      case 'zho':
      case 'chi':
      case 'zh':
        return 'Chino';
      case 'nld':
      case 'dut':
      case 'nl':
        return 'Neerlandés';
      case 'pol':
      case 'pl':
        return 'Polaco';
      case 'tur':
      case 'tr':
        return 'Turco';
      case 'swe':
      case 'sv':
        return 'Sueco';
      case 'dan':
      case 'da':
        return 'Danés';
      case 'fin':
      case 'fi':
        return 'Finés';
      case 'nor':
      case 'nob':
      case 'no':
        return 'Noruego';
      case 'heb':
      case 'he':
        return 'Hebreo';
      case 'hun':
      case 'hu':
        return 'Húngaro';
      case 'ces':
      case 'cze':
      case 'cs':
        return 'Checo';
      case 'ell':
      case 'gre':
      case 'el':
        return 'Griego';
      case 'ron':
      case 'rum':
      case 'ro':
        return 'Rumano';
      case 'ukr':
      case 'uk':
        return 'Ucraniano';
      case 'ind':
      case 'id':
        return 'Indonesio';
      case 'hin':
      case 'hi':
        return 'Hindi';
      case 'cat':
      case 'ca':
        return 'Catalán';
      case 'eus':
      case 'baq':
      case 'eu':
        return 'Euskera';
      case 'glg':
      case 'gl':
        return 'Gallego';
      default:
        return code.toUpperCase();
    }
  }
}
