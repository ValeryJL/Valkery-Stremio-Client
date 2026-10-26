import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/stremio_providers.dart';
import 'valkery_desktop_title_bar.dart';

class StremioPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem media;
  final StreamCandidate stream;
  final int? season;
  final int? episode;
  final String? localFilePath;

  const StremioPlayerScreen({
    super.key,
    required this.media,
    required this.stream,
    this.season,
    this.episode,
    this.localFilePath,
  });

  @override
  ConsumerState<StremioPlayerScreen> createState() => _StremioPlayerScreenState();
}

class _StremioPlayerScreenState extends ConsumerState<StremioPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription? _errorSubscription;
  Timer? _progressSyncTimer;

  bool _isControlsVisible = true;
  Timer? _hideControlsTimer;
  String? _playbackError;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _errorSubscription = _player.stream.error.listen((err) {
      if (mounted) {
        setState(() {
          _playbackError = err;
          _isControlsVisible = true;
        });
      }
    });

    final url = widget.localFilePath ?? widget.stream.playbackUrl;
    _player.open(Media(url));

    _startProgressSyncTimer();
    _resetHideControlsTimer();
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playbackError == null) {
        setState(() => _isControlsVisible = false);
      }
    });
  }

  void _startProgressSyncTimer() {
    _progressSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final position = _player.state.position.inSeconds;
      final duration = _player.state.duration.inSeconds;

      if (position > 0 && duration > 0) {
        final storage = ref.read(stremioStorageProvider);
        final api = ref.read(stremioApiServiceProvider);
        final authKey = storage.authKey;

        final videoId = (widget.season != null && widget.episode != null)
            ? '${widget.media.id}:${widget.season}:${widget.episode}'
            : widget.media.id;

        final completed = (position / duration) >= 0.9;
        final existing = storage.getWatchState(widget.media.id);
        final watchedList = <String>{
          if (existing != null) ...existing.watchedEpisodes,
          if (completed) videoId,
        }.toList();

        final watchState = LibraryWatchState(
          id: widget.media.id,
          name: widget.media.name,
          type: widget.media.type,
          poster: widget.media.poster,
          videoId: videoId,
          timeOffset: position,
          duration: duration,
          timesWatched: completed
              ? ((existing?.timesWatched ?? 0) + 1)
              : (existing?.timesWatched ?? 0),
          flaggedWatched: completed ? 1 : (existing?.flaggedWatched ?? 0),
          watchedEpisodes: watchedList,
          lastWatched: DateTime.now().toUtc(),
        );

        if (authKey != null && authKey.isNotEmpty) {
          await api.syncWatchState(authKey, watchState);
        } else {
          await storage.upsertWatchState(watchState);
        }
      }
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _progressSyncTimer?.cancel();
    _errorSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _isControlsVisible = !_isControlsVisible;
            if (_isControlsVisible) {
              _resetHideControlsTimer();
            }
          });
        },
        child: Stack(
          children: [
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
              ),
            ),
            if (_isControlsVisible)
              _buildControlsOverlay(isDesktopPlatform),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(bool isDesktopPlatform) {
    return Container(
      color: Colors.black.withValues(alpha: 0.50),
      child: Column(
        children: [
          // Desktop Title Bar for window dragging, minimize, maximize, close
          if (isDesktopPlatform)
            ValkeryDesktopTitleBar(
              title: '${widget.media.name} - Reproductor Valkery',
            ),
          Expanded(
            child: SafeArea(
              top: !isDesktopPlatform,
              bottom: true,
              child: Column(
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.media.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.season != null && widget.episode != null)
                                Text(
                                  'Temporada ${widget.season} • Episodio ${widget.episode}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF8B5CF6)),
                          ),
                          child: Text(
                            widget.stream.quality,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Playback Error Banner if any
                  if (_playbackError != null)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Error de reproducción: $_playbackError\nVerifica que el motor Stremio esté activo o prueba con otra fuente.',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Elegir otra', style: TextStyle(color: Colors.amberAccent)),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),
                  // Center Play/Pause & Seek buttons
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? true;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 36,
                            color: Colors.white,
                            icon: const Icon(IconsaxPlusLinear.backward_10_seconds),
                            onPressed: () {
                              _resetHideControlsTimer();
                              final pos = _player.state.position - const Duration(seconds: 10);
                              _player.seek(pos < Duration.zero ? Duration.zero : pos);
                            },
                          ),
                          const SizedBox(width: 28),
                          IconButton(
                            iconSize: 64,
                            color: const Color(0xFF8B5CF6),
                            icon: Icon(
                              isPlaying ? IconsaxPlusBold.pause : IconsaxPlusBold.play,
                            ),
                            onPressed: () {
                              _resetHideControlsTimer();
                              _player.playOrPause();
                            },
                          ),
                          const SizedBox(width: 28),
                          IconButton(
                            iconSize: 36,
                            color: Colors.white,
                            icon: const Icon(IconsaxPlusLinear.forward_10_seconds),
                            onPressed: () {
                              _resetHideControlsTimer();
                              final pos = _player.state.position + const Duration(seconds: 10);
                              _player.seek(pos);
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  // Bottom Bar Progress
                  StreamBuilder<Duration>(
                    stream: _player.stream.position,
                    builder: (context, posSnapshot) {
                      final position = posSnapshot.data ?? Duration.zero;
                      final duration = _player.state.duration;
                      final posSeconds = position.inSeconds.toDouble();
                      final totalSeconds = duration.inSeconds.toDouble();

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: totalSeconds > 0
                                    ? posSeconds.clamp(0.0, totalSeconds)
                                    : 0.0,
                                max: totalSeconds > 0 ? totalSeconds : 1.0,
                                activeColor: const Color(0xFF8B5CF6),
                                inactiveColor: Colors.white24,
                                onChanged: (val) {
                                  _resetHideControlsTimer();
                                  _player.seek(Duration(seconds: val.toInt()));
                                },
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
