import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ValkeryPlayerType {
  mediaKit,
  vlcExternal,
  mpvExternal,
  askEveryTime,
}

class SourceCoordinatorState {
  final bool stremioEnabled;
  final bool jellyfinEnabled;
  final bool stremioGuestMode;
  final bool jellyfinGuestMode;
  final String stremioServerUrl;
  final String jellyfinServerUrl;
  final String? jellyfinServerName;
  final String? jellyfinServerVersion;
  final ValkeryPlayerType preferredPlayer;

  const SourceCoordinatorState({
    this.stremioEnabled = true,
    this.jellyfinEnabled = false,
    this.stremioGuestMode = true,
    this.jellyfinGuestMode = true,
    this.stremioServerUrl = 'http://127.0.0.1:11470',
    this.jellyfinServerUrl = '',
    this.jellyfinServerName,
    this.jellyfinServerVersion,
    this.preferredPlayer = ValkeryPlayerType.mediaKit,
  });

  bool get isJellyfinActive =>
      jellyfinEnabled && jellyfinServerUrl.trim().isNotEmpty;
  bool get isDualSource => stremioEnabled && isJellyfinActive;
  bool get isStremioOnly => stremioEnabled && !isJellyfinActive;
  bool get isJellyfinOnly => !stremioEnabled && isJellyfinActive;

  SourceCoordinatorState copyWith({
    bool? stremioEnabled,
    bool? jellyfinEnabled,
    bool? stremioGuestMode,
    bool? jellyfinGuestMode,
    String? stremioServerUrl,
    String? jellyfinServerUrl,
    String? jellyfinServerName,
    String? jellyfinServerVersion,
    ValkeryPlayerType? preferredPlayer,
  }) {
    return SourceCoordinatorState(
      stremioEnabled: stremioEnabled ?? this.stremioEnabled,
      jellyfinEnabled: jellyfinEnabled ?? this.jellyfinEnabled,
      stremioGuestMode: stremioGuestMode ?? this.stremioGuestMode,
      jellyfinGuestMode: jellyfinGuestMode ?? this.jellyfinGuestMode,
      stremioServerUrl: stremioServerUrl ?? this.stremioServerUrl,
      jellyfinServerUrl: jellyfinServerUrl ?? this.jellyfinServerUrl,
      jellyfinServerName: jellyfinServerName ?? this.jellyfinServerName,
      jellyfinServerVersion:
          jellyfinServerVersion ?? this.jellyfinServerVersion,
      preferredPlayer: preferredPlayer ?? this.preferredPlayer,
    );
  }
}

class SourceCoordinatorNotifier extends StateNotifier<SourceCoordinatorState> {
  static const _keyStremioEnabled = 'valkery_stremio_enabled';
  static const _keyJellyfinEnabled = 'valkery_jellyfin_enabled';
  static const _keyStremioGuest = 'valkery_stremio_guest';
  static const _keyStremioServer = 'valkery_stremio_server_url';
  static const _keyJellyfinServer = 'valkery_jellyfin_server_url';
  static const _keyJellyfinName = 'valkery_jellyfin_server_name';
  static const _keyJellyfinVersion = 'valkery_jellyfin_server_version';
  static const _keyPlayerType = 'valkery_preferred_player_type';

  SourceCoordinatorNotifier() : super(const SourceCoordinatorState()) {
    _loadFromPreferences();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stremioOn = prefs.getBool(_keyStremioEnabled) ?? true;
      final jellyfinServer = prefs.getString(_keyJellyfinServer) ?? '';
      final jellyfinOn = prefs.getBool(_keyJellyfinEnabled) ?? (jellyfinServer.isNotEmpty);
      final jellyName = prefs.getString(_keyJellyfinName);
      final jellyVersion = prefs.getString(_keyJellyfinVersion);
      final stremioGuest = prefs.getBool(_keyStremioGuest) ?? true;
      final serverUrl = prefs.getString(_keyStremioServer) ?? 'http://127.0.0.1:11470';
      final playerIndex = prefs.getInt(_keyPlayerType) ?? 0;

      state = SourceCoordinatorState(
        stremioEnabled: stremioOn,
        jellyfinEnabled: jellyfinOn && jellyfinServer.isNotEmpty,
        jellyfinServerUrl: jellyfinServer,
        jellyfinServerName: jellyName,
        jellyfinServerVersion: jellyVersion,
        stremioGuestMode: stremioGuest,
        stremioServerUrl: serverUrl,
        preferredPlayer: ValkeryPlayerType.values[
          playerIndex.clamp(0, ValkeryPlayerType.values.length - 1)
        ],
      );
    } catch (_) {}
  }

  Future<void> setStremioEnabled(bool enabled) async {
    state = state.copyWith(stremioEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStremioEnabled, enabled);
  }

  Future<void> setJellyfinServer({
    required String url,
    String? serverName,
    String? version,
  }) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    final isEnabled = clean.isNotEmpty;
    state = state.copyWith(
      jellyfinServerUrl: clean,
      jellyfinEnabled: isEnabled,
      jellyfinServerName: serverName,
      jellyfinServerVersion: version,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyJellyfinServer, clean);
    await prefs.setBool(_keyJellyfinEnabled, isEnabled);
    if (serverName != null) {
      await prefs.setString(_keyJellyfinName, serverName);
    }
    if (version != null) {
      await prefs.setString(_keyJellyfinVersion, version);
    }
  }

  Future<void> disconnectJellyfin() async {
    state = state.copyWith(
      jellyfinServerUrl: '',
      jellyfinEnabled: false,
      jellyfinServerName: null,
      jellyfinServerVersion: null,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyJellyfinServer);
    await prefs.setBool(_keyJellyfinEnabled, false);
    await prefs.remove(_keyJellyfinName);
    await prefs.remove(_keyJellyfinVersion);
  }

  Future<void> setStremioGuestMode(bool isGuest) async {
    state = state.copyWith(stremioGuestMode: isGuest);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStremioGuest, isGuest);
  }

  Future<void> setStremioServerUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    state = state.copyWith(stremioServerUrl: clean);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStremioServer, clean);
  }

  Future<void> setPreferredPlayer(ValkeryPlayerType type) async {
    state = state.copyWith(preferredPlayer: type);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPlayerType, type.index);
  }
}

final sourceCoordinatorProvider =
    StateNotifierProvider<SourceCoordinatorNotifier, SourceCoordinatorState>(
  (ref) => SourceCoordinatorNotifier(),
);
