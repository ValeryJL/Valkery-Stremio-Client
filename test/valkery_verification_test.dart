import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

    test('StreamCandidate generates valid playback URL for local Stremio server with default and fallback trackers', () {
      const torrent = StreamCandidate(
        title: 'Big Buck Bunny 1080p',
        name: 'Torrentio 1080p',
        infoHash: 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        fileIdx: 0,
      );
      expect(
        torrent.playbackUrl,
        startsWith('http://127.0.0.1:11470/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/0?'),
      );
      expect(
        torrent.playbackUrl,
        contains('tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'),
      );
      expect(
        torrent.playbackUrl,
        contains('tr=https%3A%2F%2F1.tracker.eu.org%3A443%2Fannounce'),
      );
      expect(
        torrent.playbackUrlFor('http://example.com:11470/'),
        startsWith('http://example.com:11470/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/0?'),
      );
      expect(
        torrent.hlsPlaybackUrlFor('http://example.com:11470'),
        startsWith('http://example.com:11470/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/0/hls.m3u8?'),
      );

      // Verify null fileIdx uses -1 for automatic largest video selection
      const autoTorrent = StreamCandidate(
        title: 'Movie',
        name: 'Torrentio',
        infoHash: 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
      );
      expect(
        autoTorrent.playbackUrl,
        startsWith('http://127.0.0.1:11470/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/-1?'),
      );

      // Verify sources are cleanly passed as tr= and never f=
      const torrentWithSources = StreamCandidate(
        title: 'Movie with trackers',
        name: 'Torrentio',
        infoHash: 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        fileIdx: 1,
        behaviorHints: {'filename': 'movie.mp4'},
        sources: [
          'tracker:udp://tracker.opentrackr.org:1337/announce',
          'udp://open.stealth.si:80/announce',
        ],
      );
      final playUrl = torrentWithSources.playbackUrl;
      expect(playUrl, contains('/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/1?'));
      expect(playUrl, contains('tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'));
      expect(playUrl, contains('tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce'));
      expect(playUrl.contains('f='), isFalse);
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

    test('Stremio unified library: adding and removing library items maintains proper isLibraryItem flag', () async {
      final storage = StremioStorageService(inMemory: true);
      await storage.init();

      const movie = MediaItem(
        id: 'tt0137523',
        type: 'movie',
        name: 'Fight Club',
        poster: 'https://images.metahub.space/poster/medium/tt0137523/img.jpg',
      );

      expect(storage.isInLibrary(movie.id), isFalse);
      expect(storage.stremioLibraryItems, isEmpty);

      // Add to Library
      await storage.addToLibrary(movie);
      expect(storage.isInLibrary(movie.id), isTrue);
      expect(storage.stremioLibraryItems.length, equals(1));
      expect(storage.stremioLibraryItems.first.name, equals('Fight Club'));
      expect(storage.stremioLibraryItems.first.toStremioDatastoreItem()['temp'], isFalse);

      // Remove from Library
      await storage.removeFromLibrary(movie.id);
      expect(storage.isInLibrary(movie.id), isFalse);
      expect(storage.stremioLibraryItems, isEmpty);
    });

    test('Stremio unified library migrates legacy libraryFavorites', () async {
      final tempDir = await Directory.systemTemp.createTemp('valkery_test_');
      final stateFile = File(p.join(tempDir.path, 'state.json'));
      final legacyPayload = {
        'libraryFavorites': [
          {
            'id': 'tt0068646',
            'name': 'The Godfather',
            'type': 'movie',
            'poster': 'https://images.metahub.space/poster/medium/tt0068646/img.jpg',
          }
        ]
      };
      await stateFile.writeAsString(jsonEncode(legacyPayload));

      final storage = StremioStorageService(customFilePath: stateFile.path);
      await storage.init();

      expect(storage.isInLibrary('tt0068646'), isTrue);
      expect(storage.stremioLibraryItems.length, equals(1));
      expect(storage.stremioLibraryItems.first.name, equals('The Godfather'));

      await tempDir.delete(recursive: true);
    });
  });
}
