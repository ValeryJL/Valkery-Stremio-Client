import 'package:flutter/foundation.dart';
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
  final bool stremioGuestMode;
  final String stremioServerUrl;
  final ValkeryPlayerType preferredPlayer;

  static String get defaultStremioServerUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.startsWith('file://')) {
        return origin;
      }
    }
    return 'http://127.0.0.1:11470';
  }

  SourceCoordinatorState({
    this.stremioEnabled = true,
    this.stremioGuestMode = true,
    String? stremioServerUrl,
    this.preferredPlayer = ValkeryPlayerType.mediaKit,
  }) : stremioServerUrl =
            (stremioServerUrl != null && stremioServerUrl.isNotEmpty)
                ? stremioServerUrl
                : defaultStremioServerUrl;

  bool get isStremioOnly => stremioEnabled;

  SourceCoordinatorState copyWith({
    bool? stremioEnabled,
    bool? stremioGuestMode,
    String? stremioServerUrl,
    ValkeryPlayerType? preferredPlayer,
  }) {
    return SourceCoordinatorState(
      stremioEnabled: stremioEnabled ?? this.stremioEnabled,
      stremioGuestMode: stremioGuestMode ?? this.stremioGuestMode,
      stremioServerUrl: stremioServerUrl ?? this.stremioServerUrl,
      preferredPlayer: preferredPlayer ?? this.preferredPlayer,
    );
  }
}

class SourceCoordinatorNotifier extends StateNotifier<SourceCoordinatorState> {
  static const _keyStremioEnabled = 'valkery_stremio_enabled';
  static const _keyStremioGuest = 'valkery_stremio_guest';
  static const _keyStremioServer = 'valkery_stremio_server_url';
  static const _keyPlayerType = 'valkery_preferred_player_type';

  SourceCoordinatorNotifier() : super(SourceCoordinatorState()) {
    _loadFromPreferences();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stremioOn = prefs.getBool(_keyStremioEnabled) ?? true;
      final stremioGuest = prefs.getBool(_keyStremioGuest) ?? true;

      final savedServer = prefs.getString(_keyStremioServer);
      String serverUrl;
      if (savedServer != null && savedServer.trim().isNotEmpty) {
        if (kIsWeb &&
            (savedServer == 'http://127.0.0.1:11470' ||
                savedServer == 'http://localhost:11470' ||
                savedServer.contains(':11470'))) {
          serverUrl = SourceCoordinatorState.defaultStremioServerUrl;
        } else {
          serverUrl = savedServer.trim();
        }
      } else {
        serverUrl = SourceCoordinatorState.defaultStremioServerUrl;
      }
      final playerIndex = prefs.getInt(_keyPlayerType) ?? 0;

      state = SourceCoordinatorState(
        stremioEnabled: stremioOn,
        stremioGuestMode: stremioGuest,
        stremioServerUrl: serverUrl,
        preferredPlayer: ValkeryPlayerType.values[
            playerIndex.clamp(0, ValkeryPlayerType.values.length - 1)],
      );
    } catch (_) {}
  }

  Future<void> setStremioEnabled(bool enabled) async {
    state = state.copyWith(stremioEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStremioEnabled, enabled);
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
