import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/models/stremio/media_item.dart';
import 'package:fladder/models/stremio/stream_candidate.dart';
import 'package:fladder/models/stremio/watch_history_item.dart';
import 'package:fladder/providers/source_coordinator_provider.dart';
import 'package:fladder/services/stremio/stremio_server_process_manager.dart';
import 'package:fladder/services/stremio/stremio_storage_service.dart';

void main() {
  group('Valkery Stremio Suite Verification', () {
    test('StremioStorageService initializes with default addons including Cinemeta and Torrentio', () {
      final storage = StremioStorageService(inMemory: true);
      expect(storage.addons.isNotEmpty, isTrue);
      expect(storage.addons.any((a) => a.name.contains('Cinemeta')), isTrue);
      expect(storage.addons.any((a) => a.name.contains('Torrentio')), isTrue);
      expect(storage.addons.any((a) => a.name.contains('OpenSubtitles')), isTrue);
    });

    test('LibraryWatchState provides automatic poster fallback for IMDb IDs', () {
      final item = LibraryWatchState.fromJson({
        'id': 'tt0111161',
        'name': 'The Shawshank Redemption',
        'type': 'movie',
      });
      expect(item.poster, equals('https://images.metahub.space/poster/medium/tt0111161/img.jpg'));
    });

    test('StremioServerProcessManager defaults to 127.0.0.1:11470', () {
      final manager = StremioServerProcessManager();
      expect(manager.serverUrl, equals('http://127.0.0.1:11470'));
      expect(manager.currentStatus.isOnline, isFalse);
    });

    test('SourceCoordinator dynamically switches dual source and zero clutter on Jellyfin activation', () {
      var state = const SourceCoordinatorState();
      expect(state.isJellyfinActive, isFalse);
      expect(state.isStremioOnly, isTrue);

      // Activating with valid server URL
      state = state.copyWith(
        jellyfinEnabled: true,
        jellyfinServerUrl: 'http://192.168.1.100:8096',
        jellyfinServerName: 'Home Jellyfin',
      );
      expect(state.isJellyfinActive, isTrue);
      expect(state.isDualSource, isTrue);
      expect(state.isStremioOnly, isFalse);

      // Disconnecting reverts to clean Stremio-only view
      state = state.copyWith(
        jellyfinEnabled: false,
        jellyfinServerUrl: '',
      );
      expect(state.isJellyfinActive, isFalse);
      expect(state.isStremioOnly, isTrue);
    });

    test('StreamCandidate generates valid playback URL for local Stremio server', () {
      const torrent = StreamCandidate(
        title: 'Big Buck Bunny 1080p',
        name: 'Torrentio 1080p',
        infoHash: 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        fileIdx: 0,
      );
      expect(
        torrent.playbackUrl,
        equals('http://127.0.0.1:11470/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/0'),
      );
    });

    test('MediaItem model parses and provides releaseInfo fallback', () {
      const item = MediaItem(
        id: 'tt0111161',
        type: 'movie',
        name: 'The Shawshank Redemption',
        year: '1994',
        poster: 'https://images.metahub.space/poster/medium/tt0111161/img.jpg',
      );
      expect(item.releaseInfo, equals('1994'));
      expect(item.isSeries, isFalse);
    });

    test('SubtitleTrack exposes displayTitle fallback and language helpers', () {
      const track1 = SubtitleTrack(
        id: '1',
        url: 'http://example.com/sub.srt',
        lang: 'spa',
        label: 'Español (Latino)',
      );
      expect(track1.displayTitle, equals('Español (Latino)'));
      expect(track1.isSpanish, isTrue);

      const track2 = SubtitleTrack(
        id: '2',
        url: 'http://example.com/sub2.srt',
        lang: 'eng',
        label: '',
      );
      expect(track2.displayTitle, equals('eng'));
      expect(track2.isEnglish, isTrue);
    });
  });
}
