import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/models/stremio/media_item.dart';
import 'package:fladder/models/stremio/stream_candidate.dart';
import 'package:fladder/providers/source_coordinator_provider.dart';
import 'package:fladder/services/stremio/stremio_api_service.dart';
import 'package:fladder/services/stremio/stremio_server_process_manager.dart';
import 'package:fladder/services/stremio/stremio_storage_service.dart';

void main() {
  group('Valkery Stremio Suite Verification', () {
    test('StremioStorageService initializes with default addons', () {
      final storage = StremioStorageService(inMemory: true);
      expect(storage.addons.isNotEmpty, isTrue);
      expect(storage.addons.any((a) => a.name.contains('Cinemeta')), isTrue);
    });

    test('StremioServerProcessManager defaults to 127.0.0.1:11470', () {
      final manager = StremioServerProcessManager();
      expect(manager.serverUrl, equals('http://127.0.0.1:11470'));
      expect(manager.currentStatus.isOnline, isFalse);
    });

    test('SourceCoordinator defaults to Stremio-only without cluttering with Jellyfin', () {
      const coordinator = SourceCoordinatorState();
      expect(coordinator.stremioEnabled, isTrue);
      expect(coordinator.jellyfinEnabled, isFalse);
      expect(coordinator.isStremioOnly, isTrue);
      expect(coordinator.isDualSource, isFalse);
      expect(coordinator.preferredPlayer, equals(ValkeryPlayerType.mediaKit));
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
  });
}
