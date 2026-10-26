import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:media_kit/media_kit.dart' as mpv;
import 'package:media_kit_video/media_kit_video.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';

import '../../models/stremio/media_item.dart' as stremio_model;
import '../../models/stremio/stream_candidate.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/stremio_providers.dart';
import '../../util/external_player_launcher.dart';
import 'valkery_desktop_title_bar.dart';
import '../../providers/source_coordinator_provider.dart';

class StremioPlayerScreen extends ConsumerStatefulWidget {
  final stremio_model.MediaItem media;
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
  late final mpv.Player _player;
  late final VideoController _controller;

  StreamSubscription? _errorSubscription;
  StreamSubscription? _tracksSubscription;
  Timer? _progressSyncTimer;
  Timer? _hideControlsTimer;

  bool _isControlsVisible = true;
  String? _playbackError;
  bool _isRetrying = false;

  // Video Fit
  BoxFit _videoFit = BoxFit.contain;

  // Audio & Subtitles
  List<mpv.SubtitleTrack> _embeddedSubtitles = [];
  List<stremio_model.SubtitleTrack> _externalSubtitles = [];
  bool _isLoadingExternalSubs = false;
  mpv.SubtitleTrack _currentSubtitleTrack = mpv.SubtitleTrack.no();

  List<mpv.AudioTrack> _audioTracks = [];
  mpv.AudioTrack _currentAudioTrack = mpv.AudioTrack.auto();

  double _playbackRate = 1.0;
  double _volume = 100.0;
  bool _isMuted = false;
  double _volumeBeforeMute = 100.0;

  // Quick on-screen notification badge (e.g. "Adelantar 10s", "Velocidad: 1.5x")
  String? _temporaryIndicatorText;
  IconData? _temporaryIndicatorIcon;
  Timer? _indicatorTimer;

  // Focus node for keyboard shortcuts
  final FocusNode _focusNode = FocusNode();

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;

  @override
  void initState() {
    super.initState();

    _player = mpv.Player(
      configuration: const mpv.PlayerConfiguration(
        title: 'Valkery',
        bufferSize: 64 * 1024 * 1024,
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _errorSubscription = _player.stream.error.listen((err) {
      if (mounted) {
        setState(() {
          _playbackError = err;
          _isControlsVisible = true;
        });
      }
    });

    _tracksSubscription = _player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() {
          _embeddedSubtitles = tracks.subtitle;
          _audioTracks = tracks.audio;
          _currentSubtitleTrack = _player.state.track.subtitle;
          _currentAudioTrack = _player.state.track.audio;
        });
      }
    });

    _playingSubscription = _player.stream.playing.listen((isPlaying) {
      if (!isPlaying) {
        _savePlaybackProgress();
      }
    });

    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) {
        _savePlaybackProgress(isCompleted: true);
      }
    });

    // Auto-resume from saved playback progress
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = ref.read(stremioStorageProvider).getWatchState(widget.media.id);
      if (saved != null && saved.timeOffset > 10 && saved.duration > 0 && (saved.timeOffset < (saved.duration * 0.92))) {
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted && _player.state.duration.inSeconds > 0) {
            _player.seek(Duration(seconds: saved.timeOffset));
            final min = saved.timeOffset ~/ 60;
            final sec = saved.timeOffset % 60;
            _showIndicator(
              'Reanudando en ${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}',
              IconsaxPlusBold.play,
            );
          }
        });
      }
    });

    _initMpvPropertiesAndPlay();
    _startProgressSyncTimer();
    _loadExternalSubtitles();
    _resetHideControlsTimer();
  }

  Future<void> _initMpvPropertiesAndPlay() async {
    setState(() {
      _playbackError = null;
      _isRetrying = false;
    });

    try {
      if (_player.platform is mpv.NativePlayer) {
        final np = _player.platform as dynamic;
        await np.setProperty('hwdec', 'auto-safe');
        await np.setProperty('demuxer-max-bytes', '256M');
        await np.setProperty('network-timeout', '120');
        await np.setProperty('cache', 'yes');
      }
    } catch (_) {}

    final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
    final url = widget.localFilePath ??
        ((kIsWeb && !widget.stream.isWebCompatible && widget.stream.isTorrent)
            ? widget.stream.hlsPlaybackUrlFor(serverUrl)
            : widget.stream.playbackUrlFor(serverUrl));

    await _player.open(mpv.Media(url));
  }

  Future<void> _loadExternalSubtitles() async {
    setState(() => _isLoadingExternalSubs = true);
    try {
      final catalogService = ref.read(catalogAndStreamServiceProvider);
      final subs = await catalogService.fetchSubtitles(
        widget.media.id,
        widget.media.type,
        season: widget.season,
        episode: widget.episode,
      );
      if (mounted) {
        setState(() {
          _externalSubtitles = subs;
          _isLoadingExternalSubs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingExternalSubs = false);
    }
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isControlsVisible) {
      _hideControlsTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted && _playbackError == null && _player.state.playing) {
          setState(() => _isControlsVisible = false);
        }
      });
    }
  }

  void _showControls() {
    if (!_isControlsVisible) {
      setState(() => _isControlsVisible = true);
    }
    _resetHideControlsTimer();
  }

  void _toggleControls() {
    setState(() => _isControlsVisible = !_isControlsVisible);
    if (_isControlsVisible) {
      _resetHideControlsTimer();
    }
  }

  void _showIndicator(String text, IconData icon) {
    _indicatorTimer?.cancel();
    setState(() {
      _temporaryIndicatorText = text;
      _temporaryIndicatorIcon = icon;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _temporaryIndicatorText = null;
          _temporaryIndicatorIcon = null;
        });
      }
    });
  }

  void _seekRelative(int seconds) {
    final current = _player.state.position;
    final total = _player.state.duration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > total ? total : target);

    _player.seek(clamped);
    _showIndicator(
      seconds > 0 ? '+$seconds s' : '$seconds s',
      seconds > 0 ? IconsaxPlusLinear.forward_10_seconds : IconsaxPlusLinear.backward_10_seconds,
    );
    _showControls();
  }

  void _adjustVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _setVolume(newVol);
  }

  void _setVolume(double val) {
    setState(() {
      _volume = val;
      _isMuted = val == 0.0;
    });
    _player.setVolume(val);
    _showIndicator(
      '${val.round()}%',
      _isMuted
          ? IconsaxPlusLinear.volume_cross
          : (val > 50 ? IconsaxPlusLinear.volume_high : IconsaxPlusLinear.volume_low_1),
    );
    _showControls();
  }

  void _toggleMute() {
    if (_isMuted) {
      _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 50.0);
    } else {
      _volumeBeforeMute = _volume;
      _setVolume(0.0);
    }
  }

  void _setPlaybackRate(double rate) {
    setState(() => _playbackRate = rate);
    _player.setRate(rate);
    _showIndicator('${rate}x', IconsaxPlusLinear.speedometer);
    _showControls();
  }

  void _cycleVideoFit() {
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
        _showIndicator('Ajuste: Rellenar (Zoom)', Icons.aspect_ratio);
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.fill;
        _showIndicator('Ajuste: Estirar', Icons.aspect_ratio);
      } else {
        _videoFit = BoxFit.contain;
        _showIndicator('Ajuste: Contener (Original)', Icons.aspect_ratio);
      }
    });
    _showControls();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _player.playOrPause();
      _showControls();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-5);
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      fullScreenHelper.toggleFullScreen(ref);
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _savePlaybackProgress({bool isCompleted = false}) async {
    final position = _player.state.position.inSeconds;
    final duration = _player.state.duration.inSeconds;

    if (position > 0 && duration > 0) {
      final storage = ref.read(stremioStorageProvider);
      final api = ref.read(stremioApiServiceProvider);
      final authKey = storage.authKey;

      final videoId = (widget.season != null && widget.episode != null)
          ? '${widget.media.id}:${widget.season}:${widget.episode}'
          : widget.media.id;

      final completed = isCompleted || (position / duration) >= 0.9;
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
        timeOffset: completed ? 0 : position,
        duration: duration,
        timesWatched: completed
            ? ((existing?.timesWatched ?? 0) + 1)
            : (existing?.timesWatched ?? 0),
        flaggedWatched: completed ? 1 : (existing?.flaggedWatched ?? 0),
        watchedEpisodes: watchedList,
        lastWatched: DateTime.now().toUtc(),
      );

      await storage.upsertWatchState(watchState);

      if (authKey != null && authKey.isNotEmpty) {
        try {
          await api.syncWatchState(authKey, watchState);
        } catch (_) {}
      }
    }
  }

  void _startProgressSyncTimer() {
    _progressSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _savePlaybackProgress();
    });
  }

  @override
  void dispose() {
    _savePlaybackProgress();
    _hideControlsTimer?.cancel();
    _progressSyncTimer?.cancel();
    _indicatorTimer?.cancel();
    _errorSubscription?.cancel();
    _tracksSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _savePlaybackProgress();
      },
      child: KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          cursor: _isControlsVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _showControls(),
          onEnter: (_) => _showControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (AdaptiveLayout.isDesktop(context) || kIsWeb) {
                // Single click on desktop/web toggles play/pause
                _player.playOrPause();
                _showControls();
              } else {
                _toggleControls();
              }
            },
            onDoubleTap: () {
              fullScreenHelper.toggleFullScreen(ref);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The Video Layer
                Positioned.fill(
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: _videoFit,
                  ),
                ),

                // Center temporary seek/volume/rate badge
                if (_temporaryIndicatorText != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 16,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_temporaryIndicatorIcon != null) ...[
                            Icon(_temporaryIndicatorIcon, color: const Color(0xFFC4B5FD), size: 28),
                            const SizedBox(width: 12),
                          ],
                          Text(
                            _temporaryIndicatorText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Center Animated Play Button when paused and controls are visible
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  builder: (context, playingSnap) {
                    final isPlaying = playingSnap.data ?? true;
                    return IgnorePointer(
                      ignoring: isPlaying || !_isControlsVisible,
                      child: Center(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 250),
                          scale: (!isPlaying && _isControlsVisible && _playbackError == null) ? 1.0 : 0.0,
                          curve: Curves.easeOutBack,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: IconButton(
                              iconSize: 64,
                              icon: const Icon(IconsaxPlusBold.play, color: Colors.white),
                              onPressed: () {
                                _player.play();
                                _showControls();
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Controls Layer (Fade In / Out)
                IgnorePointer(
                  ignoring: !_isControlsVisible,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _isControlsVisible ? 1.0 : 0.0,
                    child: _buildControlsOverlay(isDesktopPlatform),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildControlsOverlay(bool isDesktopPlatform) {
    final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
    final streamUrl = widget.localFilePath ?? widget.stream.playbackUrlFor(serverUrl);

    return Column(
      children: [
        // Desktop window Title Bar
        if (isDesktopPlatform)
          ValkeryDesktopTitleBar(
            title: '${widget.media.name} - Reproductor Valkery',
          ),

        // Top Gradient Bar
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.transparent,
              ],
            ),
          ),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: isDesktopPlatform ? 8 : (MediaQuery.of(context).padding.top + 8),
            bottom: 24,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Volver',
                icon: const Icon(IconsaxPlusLinear.arrow_left, color: Colors.white, size: 24),
                onPressed: () async {
                  await _savePlaybackProgress();
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.media.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (widget.season != null && widget.episode != null)
                          Text(
                            'Temporada ${widget.season} • Episodio ${widget.episode}  ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                            ),
                          ),
                        Text(
                          widget.stream.name.isNotEmpty ? widget.stream.name : widget.stream.addonName,
                          style: TextStyle(
                            color: const Color(0xFFC4B5FD).withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Quality Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8B5CF6)),
                ),
                child: Text(
                  widget.stream.quality,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Error message banner if playback failed
        if (_playbackError != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        kIsWeb && _playbackError.toString().contains('no supported source')
                            ? 'Este torrent está en contenedor MKV o códec 4K HDR no soportado por el navegador.'
                            : 'Error de reproducción: $_playbackError',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar búfer'),
                      onPressed: _isRetrying ? null : () => _initMpvPropertiesAndPlay(),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.play_circle_outline, size: 16),
                      label: const Text('Abrir en VLC'),
                      onPressed: () async {
                        final ok = await ExternalPlayerLauncher.openInVlc(streamUrl);
                        if (context.mounted) {
                          if (kIsWeb) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Descargando valkery_stream.m3u para abrir directo en VLC.'),
                              ),
                            );
                          } else if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('VLC no encontrado en el sistema.'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Elegir otra fuente', style: TextStyle(color: Color(0xFFC4B5FD))),
                    ),
                  ],
                ),
              ],
            ),
          ),

        const Spacer(),

        // Buffering Indicator in middle
        StreamBuilder<bool>(
          stream: _player.stream.buffering,
          builder: (context, buffSnap) {
            final isBuffering = buffSnap.data ?? false;
            if (isBuffering && _playbackError == null) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Cargando búfer...',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),

        const Spacer(),

        // Bottom Gradient Bar with Progress & Controls
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.90),
                Colors.transparent,
              ],
            ),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 14,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress Bar
              _buildProgressBar(),
              const SizedBox(height: 6),
              // Buttons Row
              _buildBottomControlsRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        final duration = _player.state.duration;
        final buffer = _player.state.buffer;

        final posSec = position.inSeconds.toDouble();
        final totalSec = duration.inSeconds.toDouble();
        final buffSec = buffer.inSeconds.toDouble();

        return Row(
          children: [
            Text(
              _formatDuration(position),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: const Color(0xFF8B5CF6),
                  inactiveTrackColor: Colors.white24,
                  secondaryActiveTrackColor: Colors.white38,
                  thumbColor: Colors.white,
                  overlayColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                ),
                child: Slider(
                  value: totalSec > 0 ? posSec.clamp(0.0, totalSec) : 0.0,
                  max: totalSec > 0 ? totalSec : 1.0,
                  secondaryTrackValue: totalSec > 0 ? buffSec.clamp(0.0, totalSec) : null,
                  onChanged: (val) {
                    _showControls();
                    _player.seek(Duration(seconds: val.toInt()));
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatDuration(duration),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomControlsRow() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      builder: (context, playingSnap) {
        final isPlaying = playingSnap.data ?? true;

        return Row(
          children: [
            // Play / Pause Button
            IconButton(
              tooltip: isPlaying ? 'Pausar (Espacio)' : 'Reproducir (Espacio)',
              iconSize: 32,
              color: Colors.white,
              icon: Icon(isPlaying ? IconsaxPlusBold.pause : IconsaxPlusBold.play),
              onPressed: () {
                _player.playOrPause();
                _showControls();
              },
            ),
            // Replay 10s
            IconButton(
              tooltip: 'Retroceder 10s (Flecha Izq)',
              iconSize: 24,
              color: Colors.white,
              icon: const Icon(IconsaxPlusLinear.backward_10_seconds),
              onPressed: () => _seekRelative(-10),
            ),
            // Forward 10s
            IconButton(
              tooltip: 'Adelantar 10s (Flecha Der)',
              iconSize: 24,
              color: Colors.white,
              icon: const Icon(IconsaxPlusLinear.forward_10_seconds),
              onPressed: () => _seekRelative(10),
            ),

            const SizedBox(width: 8),

            // Volume Controls (Hover or Slider)
            IconButton(
              tooltip: _isMuted ? 'Desmutear (M)' : 'Silenciar (M)',
              iconSize: 22,
              color: Colors.white,
              icon: Icon(
                _isMuted
                    ? IconsaxPlusLinear.volume_cross
                    : (_volume > 50 ? IconsaxPlusLinear.volume_high : IconsaxPlusLinear.volume_low_1),
              ),
              onPressed: _toggleMute,
            ),
            if (AdaptiveLayout.isDesktop(context) || kIsWeb)
              SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _isMuted ? 0.0 : _volume,
                    min: 0.0,
                    max: 100.0,
                    onChanged: (val) => _setVolume(val),
                  ),
                ),
              ),

            const Spacer(),

            // Subtitles Track Selector Button
            IconButton(
              tooltip: 'Subtítulos',
              iconSize: 22,
              color: _currentSubtitleTrack.id != 'no' ? const Color(0xFFC4B5FD) : Colors.white,
              icon: const Icon(IconsaxPlusLinear.subtitle),
              onPressed: _showSubtitlesSelectionDialog,
            ),

            // Audio Tracks Selector Button
            IconButton(
              tooltip: 'Pista de Audio',
              iconSize: 22,
              color: Colors.white,
              icon: const Icon(IconsaxPlusLinear.audio_square),
              onPressed: _showAudioTracksSelectionDialog,
            ),

            // Playback Speed Button
            PopupMenuButton<double>(
              tooltip: 'Velocidad de reproducción',
              initialValue: _playbackRate,
              color: const Color(0xFF1E1B2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: _setPlaybackRate,
              itemBuilder: (context) => [
                for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem(
                    value: speed,
                    child: Row(
                      children: [
                        if (speed == _playbackRate)
                          const Icon(Icons.check, size: 16, color: Color(0xFF8B5CF6))
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(
                          speed == 1.0 ? '1.0x (Normal)' : '${speed}x',
                          style: TextStyle(
                            color: speed == _playbackRate ? const Color(0xFF8B5CF6) : Colors.white,
                            fontWeight: speed == _playbackRate ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_playbackRate}x',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

            // Video Fit (Aspect Ratio) Button
            IconButton(
              tooltip: 'Ajuste de pantalla: ${_videoFit == BoxFit.contain ? "Original" : (_videoFit == BoxFit.cover ? "Zoom" : "Estirar")}',
              iconSize: 22,
              color: Colors.white,
              icon: const Icon(Icons.aspect_ratio),
              onPressed: _cycleVideoFit,
            ),

            // Player Options / Technical Settings
            IconButton(
              tooltip: 'Opciones de reproductor',
              iconSize: 22,
              color: Colors.white,
              icon: const Icon(IconsaxPlusLinear.setting_2),
              onPressed: _showPlayerOptionsSheet,
            ),

            // Fullscreen Button
            IconButton(
              tooltip: 'Pantalla completa (F)',
              iconSize: 22,
              color: Colors.white,
              icon: const Icon(IconsaxPlusLinear.maximize_3),
              onPressed: () => fullScreenHelper.toggleFullScreen(ref),
            ),
          ],
        );
      },
    );
  }

  // --- DIALOGS & OPTIONS SHEETS ---

  void _showSubtitlesSelectionDialog() {
    _showControls();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Icon(IconsaxPlusLinear.subtitle, color: Color(0xFF8B5CF6)),
                          const SizedBox(width: 10),
                          const Text(
                            'Subtítulos',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (_isLoadingExternalSubs)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12, height: 1),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          // Disable subtitles option
                          ListTile(
                            leading: Icon(
                              Icons.close,
                              color: _currentSubtitleTrack.id == 'no' ? const Color(0xFF8B5CF6) : Colors.white70,
                            ),
                            title: const Text('Desactivados', style: TextStyle(color: Colors.white)),
                            trailing: _currentSubtitleTrack.id == 'no'
                                ? const Icon(Icons.check, color: Color(0xFF8B5CF6))
                                : null,
                            onTap: () {
                              _player.setSubtitleTrack(mpv.SubtitleTrack.no());
                              setState(() => _currentSubtitleTrack = mpv.SubtitleTrack.no());
                              Navigator.pop(context);
                            },
                          ),

                          // Embedded Subtitles Section
                          if (_embeddedSubtitles.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Text(
                                'Subtítulos del video (Incrustados)',
                                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            for (final sub in _embeddedSubtitles)
                              if (sub.id != 'no' && sub.id != 'auto')
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    sub.title?.isNotEmpty == true ? sub.title! : (sub.language ?? 'Pista ${sub.id}'),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: sub.language != null
                                      ? Text(sub.language!, style: const TextStyle(color: Colors.white54, fontSize: 11))
                                      : null,
                                  trailing: _currentSubtitleTrack.id == sub.id
                                      ? const Icon(Icons.check, color: Color(0xFF8B5CF6))
                                      : null,
                                  onTap: () {
                                    _player.setSubtitleTrack(sub);
                                    setState(() => _currentSubtitleTrack = sub);
                                    Navigator.pop(context);
                                  },
                                ),
                          ],

                          // External Subtitles Section (OpenSubtitles / Addons)
                          if (_externalSubtitles.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Text(
                                'Subtítulos online (OpenSubtitles / Addons)',
                                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            for (final extSub in _externalSubtitles)
                              ListTile(
                                dense: true,
                                title: Text(
                                  extSub.displayTitle,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  extSub.addonName,
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                                trailing: _currentSubtitleTrack.title == extSub.displayTitle
                                    ? const Icon(Icons.check, color: Color(0xFF8B5CF6))
                                    : null,
                                onTap: () {
                                  final track = mpv.SubtitleTrack.uri(
                                    extSub.url,
                                    title: extSub.displayTitle,
                                    language: extSub.lang,
                                  );
                                  _player.setSubtitleTrack(track);
                                  setState(() => _currentSubtitleTrack = track);
                                  _showIndicator('Subtítulo: ${extSub.displayTitle}', IconsaxPlusLinear.subtitle);
                                  Navigator.pop(context);
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAudioTracksSelectionDialog() {
    _showControls();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(IconsaxPlusLinear.audio_square, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text(
                        'Pistas de Audio',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                if (_audioTracks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No se detectaron pistas de audio secundarias', style: TextStyle(color: Colors.white60)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final audio in _audioTracks)
                          if (audio.id != 'no' && audio.id != 'auto')
                            ListTile(
                              dense: true,
                              title: Text(
                                audio.title?.isNotEmpty == true ? audio.title! : (audio.language ?? 'Pista ${audio.id}'),
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: audio.language != null
                                  ? Text(audio.language!, style: const TextStyle(color: Colors.white54, fontSize: 11))
                                  : null,
                              trailing: _currentAudioTrack.id == audio.id
                                  ? const Icon(Icons.check, color: Color(0xFF8B5CF6))
                                  : null,
                              onTap: () {
                                _player.setAudioTrack(audio);
                                setState(() => _currentAudioTrack = audio);
                                _showIndicator('Audio: ${audio.title ?? audio.language ?? audio.id}', IconsaxPlusLinear.audio_square);
                                Navigator.pop(context);
                              },
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPlayerOptionsSheet() {
    _showControls();
    final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
    final streamUrl = widget.localFilePath ?? widget.stream.playbackUrlFor(serverUrl);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161426),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(IconsaxPlusLinear.setting_2, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 10),
                      Text(
                        'Configuración del Reproductor',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading: const Icon(Icons.aspect_ratio, color: Colors.white70),
                  title: const Text('Ajuste de pantalla', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _videoFit == BoxFit.contain
                        ? 'Contener (Aspect ratio original)'
                        : (_videoFit == BoxFit.cover ? 'Rellenar pantalla (Zoom)' : 'Estirar'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _cycleVideoFit();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline, color: Colors.orangeAccent),
                  title: const Text('Abrir en VLC Media Player', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Enviar stream directo o descargar lista M3U', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(context);
                    await ExternalPlayerLauncher.openInVlc(streamUrl);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.white70),
                  title: const Text('Detalles de la fuente', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Calidad: ${widget.stream.quality} • Addon: ${widget.stream.addonName}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
