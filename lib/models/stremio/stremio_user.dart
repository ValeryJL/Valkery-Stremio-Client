class StremioUser {
  final String id;
  final String email;
  final String authKey;
  final String avatar;

  const StremioUser({
    required this.id,
    required this.email,
    required this.authKey,
    this.avatar = '',
  });

  bool get isAuthenticated => authKey.trim().isNotEmpty;

  StremioUser copyWith({
    String? id,
    String? email,
    String? authKey,
    String? avatar,
  }) {
    return StremioUser(
      id: id ?? this.id,
      email: email ?? this.email,
      authKey: authKey ?? this.authKey,
      avatar: avatar ?? this.avatar,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'id': id,
      'email': email,
      'authKey': authKey,
      'avatar': avatar,
    };
  }

  factory StremioUser.fromJson(
    Map<String, dynamic> json, {
    String? fallbackAuthKey,
  }) {
    final userMap = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json;
    final id = (userMap['_id'] ?? userMap['id'] ?? '').toString();
    final email = (userMap['email'] ?? '').toString();
    final authKey =
        (json['authKey'] ?? userMap['authKey'] ?? fallbackAuthKey ?? '')
            .toString();
    final avatar = (userMap['avatar'] ?? '').toString();

    return StremioUser(
      id: id,
      email: email,
      authKey: authKey,
      avatar: avatar,
    );
  }
}

class StremioAddon {
  final String id;
  final String name;
  final String version;
  final String description;
  final String transportUrl;
  final List<String> types;
  final List<String> resources;
  final List<String> idPrefixes;

  const StremioAddon({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    required this.transportUrl,
    this.types = const ['movie', 'series'],
    this.resources = const ['catalog', 'meta', 'stream', 'subtitles'],
    this.idPrefixes = const ['tt'],
  });

  /// Returns the base URL of the addon without the trailing `/manifest.json`.
  String get baseUrl {
    final trimmed = transportUrl.trim();
    if (trimmed.endsWith('/manifest.json')) {
      return trimmed.substring(0, trimmed.length - '/manifest.json'.length);
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  bool supportsResource(String resource, {String? type}) {
    final hasRes = resources.any(
      (r) => r.toLowerCase() == resource.toLowerCase(),
    );
    if (!hasRes) return false;
    if (type == null || type.isEmpty || type == 'all') return true;
    return types.any((t) => t.toLowerCase() == type.toLowerCase());
  }

  StremioAddon copyWith({
    String? id,
    String? name,
    String? version,
    String? description,
    String? transportUrl,
    List<String>? types,
    List<String>? resources,
    List<String>? idPrefixes,
  }) {
    return StremioAddon(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      transportUrl: transportUrl ?? this.transportUrl,
      types: types ?? this.types,
      resources: resources ?? this.resources,
      idPrefixes: idPrefixes ?? this.idPrefixes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transportUrl': transportUrl,
      'transportName': 'http',
      'manifest': {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'types': types,
        'resources': resources,
        'idPrefixes': idPrefixes,
      },
    };
  }

  factory StremioAddon.fromJson(Map<String, dynamic> json) {
    final manifest = json['manifest'] is Map<String, dynamic>
        ? json['manifest'] as Map<String, dynamic>
        : json;

    final rawResources = manifest['resources'] as List<dynamic>? ?? const [];
    final parsedResources = <String>[];
    for (final item in rawResources) {
      if (item is String) {
        parsedResources.add(item);
      } else if (item is Map<String, dynamic> && item['name'] != null) {
        parsedResources.add(item['name'].toString());
      }
    }

    final rawTypes = manifest['types'] as List<dynamic>? ?? const [];
    final parsedTypes = rawTypes.map((e) => e.toString()).toList();

    final rawPrefixes = manifest['idPrefixes'] as List<dynamic>? ?? const [];
    final parsedPrefixes = rawPrefixes.map((e) => e.toString()).toList();

    return StremioAddon(
      id: (manifest['id'] ?? json['id'] ?? 'unknown.addon').toString(),
      name: (manifest['name'] ?? json['name'] ?? 'Custom Addon').toString(),
      version: (manifest['version'] ?? json['version'] ?? '1.0.0').toString(),
      description:
          (manifest['description'] ?? json['description'] ?? '').toString(),
      transportUrl:
          (json['transportUrl'] ?? manifest['transportUrl'] ?? '').toString(),
      types: parsedTypes.isEmpty ? const ['movie', 'series'] : parsedTypes,
      resources: parsedResources.isEmpty
          ? const ['catalog', 'meta', 'stream']
          : parsedResources,
      idPrefixes: parsedPrefixes.isEmpty ? const ['tt'] : parsedPrefixes,
    );
  }

  static List<StremioAddon> defaultAddons() {
    return const [
      StremioAddon(
        id: 'com.linvo.cinemeta',
        name: 'Cinemeta',
        version: '3.0.13',
        description: 'Official Stremio movie and series catalog',
        transportUrl: 'https://v3-cinemeta.strem.io/manifest.json',
        types: ['movie', 'series'],
        resources: ['catalog', 'meta'],
        idPrefixes: ['tt'],
      ),
      StremioAddon(
        id: 'community.torrentio',
        name: 'Torrentio',
        version: '1.0.14',
        description: 'Multi-provider torrents and debrid stream provider',
        transportUrl: 'https://torrentio.strem.fun/manifest.json',
        types: ['movie', 'series', 'anime'],
        resources: ['stream'],
        idPrefixes: ['tt', 'kitsu'],
      ),
      StremioAddon(
        id: 'org.stremio.opensubtitles-v3',
        name: 'OpenSubtitles v3',
        version: '1.0.0',
        description: 'Official subtitle provider for Stremio',
        transportUrl: 'https://opensubtitles-v3.strem.io/manifest.json',
        types: ['movie', 'series'],
        resources: ['subtitles'],
        idPrefixes: ['tt'],
      ),
    ];
  }
}
