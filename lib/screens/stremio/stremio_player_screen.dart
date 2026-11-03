import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:media_kit/media_kit.dart' as mpv;
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/stremio/media_item.dart' as stremio_model;
import '../../models/stremio/stream_candidate.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/stremio_providers.dart';
import '../../services/stremio/stremio_offline_download_manager.dart';
import '../../util/external_player_launcher.dart';
import '../../util/valkery_fullscreen_helper.dart';
import 'valkery_desktop_title_bar.dart';
import 'web_hls_bridge.dart';
import '../../providers/source_coordinator_provider.dart';

class StremioPlayerScreen extends ConsumerStatefulWidget {
  final stremio_model.MediaItem media;
  final StreamCandidate stream;
  final int? season;
  final int? episode;
  final String? localFilePath;
  final List<OfflineSubtitleTrack>? localSubtitles;

  const StremioPlayerScreen({
    super.key,
    required this.media,
    required this.stream,
    this.season,
    this.episode,
    this.localFilePath,
    this.localSubtitles,
  });

  @override
  ConsumerState<StremioPlayerScreen> createState() => _StremioPlayerScreenState();
}

class _StremioPlayerScreenState extends ConsumerState<StremioPlayerScreen> {
  mpv.Player? _player;
  VideoController? _controller;
  WebHlsBridge? _webBridge;

  StreamSubscription? _errorSubscription;
  StreamSubscription? _tracksSubscription;
  StreamSubscription? _webSubTracksSubscription;
  StreamSubscription? _webSubtitleCueSubscription;
  StreamSubscription? _webAutoMutedSubscription;
  Timer? _progressSyncTimer;
  Timer? _hideControlsTimer;

  bool _isControlsVisible = true;
  bool _isWebAutoMuted = false;
  String? _webSubtitleText;
  String? _playbackError;
  bool _isRetrying = false;
  bool _isInitialLoading = true;
  int _openRetryCount = 0;
  static const int _maxRetries = 20;
  bool _isMetadataReady = false;
  String _torrentStatusMessage = 'Conectando al enjambre de torrents...';
  Timer? _torrentStatsTimer;
  int _torrentPeers = 0;
  int _torrentDownloadSpeed = 0;
  int _torrentDownloadedBytes = 0;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription? _logSubscription;

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

  // Unified Player Helpers (WebHlsBridge on Web, media_kit on Native)
  Stream<bool> get _playingStream =>
      kIsWeb ? _webBridge!.playingStream : _player!.stream.playing;
  Stream<Duration> get _positionStream =>
      kIsWeb ? _webBridge!.positionStream : _player!.stream.position;
  bool get _isPlayingNow =>
      kIsWeb ? _webBridge!.isPlaying : _player!.state.playing;
  Duration get _currentPosition =>
      kIsWeb ? _webBridge!.position : _player!.state.position;
  Duration get _currentDuration =>
      kIsWeb ? _webBridge!.duration : _player!.state.duration;
  Duration get _currentBuffer =>
      kIsWeb ? _webBridge!.buffer : _player!.state.buffer;

  void _playUnified() {
    if (kIsWeb) {
      _webBridge?.play();
    } else {
      _player?.play();
    }
  }

  void _playOrPauseUnified() {
    if (kIsWeb) {
      if (_isWebAutoMuted) {
        _webBridge?.unmuteFromUserGesture(_volume);
        return;
      }
      _webBridge?.playOrPause();
    } else {
      _player?.playOrPause();
    }
  }

  void _seekUnified(Duration target) {
    if (kIsWeb) {
      _webBridge?.seek(target);
    } else {
      _player?.seek(target);
    }
  }

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      final bridge = WebHlsBridge();
      _webBridge = bridge;

      _errorSubscription = bridge.errorStream.listen(_handlePlayerError);

      _durationSubscription = bridge.durationStream.listen((dur) {
        if (dur > Duration.zero && mounted) {
          if (_isInitialLoading || _playbackError != null) {
            setState(() {
              _isInitialLoading = false;
              _playbackError = null;
            });
          }
        }
      });

      _positionSubscription = bridge.positionStream.listen((pos) {
        if (pos > Duration.zero && mounted) {
          if (_isInitialLoading || _playbackError != null) {
            setState(() {
              _isInitialLoading = false;
              _playbackError = null;
            });
          }
        }
      });

      _tracksSubscription = bridge.audioTracksStream.listen((tracks) {
        if (mounted && tracks.isNotEmpty) {
          setState(() {
            _audioTracks = tracks;
            if (_currentAudioTrack.id == 'auto' || _currentAudioTrack.id == 'no') {
              _currentAudioTrack = tracks.first;
            }
          });
        }
      });

      _webSubTracksSubscription = bridge.subtitleTracksStream.listen((subs) {
        if (mounted && subs.isNotEmpty) {
          setState(() {
            _embeddedSubtitles = subs;
          });
          // Auto-select embedded Spanish subtitle if external subtitles finished empty and no track active
          if (_currentSubtitleTrack.id == 'no' && !_isLoadingExternalSubs && _externalSubtitles.isEmpty) {
            final spanishEmbedded = subs.where((s) {
              final l = (s.language ?? '').toLowerCase();
              final t = (s.title ?? '').toLowerCase();
              return l.contains('spa') || l == 'es' || l.contains('lat') || t.contains('espa') || t.contains('spa');
            }).firstOrNull;
            if (spanishEmbedded != null) {
              _applySubtitleTrack(spanishEmbedded);
            }
          }
        }
      });

      _webSubtitleCueSubscription = bridge.subtitleCueTextStream.listen((cueText) {
        if (mounted && _webSubtitleText != cueText) {
          setState(() => _webSubtitleText = cueText);
        }
      });

      _webAutoMutedSubscription = bridge.autoMutedStream.listen((muted) {
        if (mounted) {
          setState(() => _isWebAutoMuted = muted);
        }
      });

      _playingSubscription = bridge.playingStream.listen((isPlaying) {
        if (isPlaying) {
          if (mounted && (_playbackError != null || _isInitialLoading)) {
            setState(() {
              _playbackError = null;
              _isInitialLoading = false;
            });
          }
        } else {
          _savePlaybackProgress();
        }
      });

      _completedSubscription = bridge.completedStream.listen((completed) {
        if (completed) {
          _savePlaybackProgress(isCompleted: true);
        }
      });
    } else {
      final player = mpv.Player(
        configuration: const mpv.PlayerConfiguration(
          title: 'Valkery',
          bufferSize: 128 * 1024 * 1024,
        ),
      );
      _player = player;

      _controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

      _errorSubscription = player.stream.error.listen(_handlePlayerError);

      _durationSubscription = player.stream.duration.listen((dur) {
        if (dur > Duration.zero && mounted) {
          if (_isInitialLoading || _playbackError != null) {
            setState(() {
              _isInitialLoading = false;
              _playbackError = null;
            });
          }
        }
      });

      _positionSubscription = player.stream.position.listen((pos) {
        if (pos > Duration.zero && mounted) {
          if (_isInitialLoading || _playbackError != null) {
            setState(() {
              _isInitialLoading = false;
              _playbackError = null;
            });
          }
        }
      });

      _logSubscription = player.stream.log.listen((event) {
        if (kDebugMode) {
          debugPrint('[ValkeryPlayer/mpv] [${event.level}] ${event.text}');
        }
      });

      _tracksSubscription = player.stream.tracks.listen((tracks) {
        if (mounted) {
          setState(() {
            _embeddedSubtitles = tracks.subtitle;
            _audioTracks = tracks.audio;
            _currentSubtitleTrack = player.state.track.subtitle;
            _currentAudioTrack = player.state.track.audio;
          });
        }
      });

      _playingSubscription = player.stream.playing.listen((isPlaying) {
        if (isPlaying) {
          if (mounted && _playbackError != null) {
            setState(() => _playbackError = null);
          }
          player.setVolume(_volume);
        } else {
          _savePlaybackProgress();
        }
      });

      _completedSubscription = player.stream.completed.listen((completed) {
        if (completed) {
          _savePlaybackProgress(isCompleted: true);
        }
      });
    }

    // Auto-resume from saved playback progress
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = ref.read(stremioStorageProvider).getWatchState(widget.media.id);
      final expectedVideoId = (widget.season != null && widget.episode != null)
          ? '${widget.media.id}:${widget.season}:${widget.episode}'
          : widget.media.id;
      final matchesVideoId = saved != null &&
          (saved.videoId.isEmpty ||
              saved.videoId == expectedVideoId ||
              widget.season == null);
      if (saved != null &&
          matchesVideoId &&
          saved.timeOffset > 10 &&
          saved.duration > 0 &&
          (saved.timeOffset < (saved.duration * 0.92))) {
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted && _currentDuration.inSeconds > 0) {
            _seekUnified(Duration(seconds: saved.timeOffset));
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
    HardwareKeyboard.instance.addHandler(_handleGlobalHardwareKey);
  }

  void _handlePlayerError(String err) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('[ValkeryPlayer/error] $err (loading: $_isInitialLoading, retry: $_openRetryCount)');
    }

    final errStr = err.toString().toLowerCase();
    final isAutoplayOrInterrupted = errStr.contains('notallowed') ||
        errStr.contains('user didn\'t interact') ||
        errStr.contains('gesture') ||
        errStr.contains('interrupted') ||
        errStr.contains('aborterror');

    if (isAutoplayOrInterrupted) {
      if (mounted) {
        setState(() {
          _playbackError = null;
          _isInitialLoading = false;
          _isControlsVisible = true;
        });
      }
      return;
    }

    final hasDecodedDuration = _currentDuration > Duration.zero;
    if (hasDecodedDuration) {
      if (kDebugMode) {
        debugPrint('[ValkeryPlayer] Non-fatal transient buffer alert while duration is known: $err');
      }
      return;
    }

    final bool hasActiveSwarm = _torrentPeers > 0 || _torrentDownloadedBytes > 0;
    final int effectiveMaxRetries = (kIsWeb || hasActiveSwarm) ? _maxRetries : 10;

    if (_isInitialLoading && _openRetryCount < effectiveMaxRetries) {
      _openRetryCount++;
      setState(() {
        _torrentStatusMessage = hasActiveSwarm
            ? 'Descargando búfer (${(_torrentDownloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB cacheados)...'
            : 'Conectando al búfer (reintentando conexión $_openRetryCount/$effectiveMaxRetries)...';
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && _isInitialLoading) {
          _openStreamInPlayer();
        }
      });
      return;
    }

    setState(() {
      _playbackError = err;
      _isInitialLoading = false;
      _isControlsVisible = true;
    });
    _torrentStatsTimer?.cancel();
  }

  Future<void> _initMpvPropertiesAndPlay() async {
    setState(() {
      _playbackError = null;
      _isRetrying = false;
      _isInitialLoading = true;
      _openRetryCount = 0;
      _isMetadataReady = !widget.stream.isTorrent || widget.stream.infoHash.isEmpty;
      _torrentStatusMessage = widget.stream.isTorrent
          ? 'Conectando al enjambre de torrents y rastreadores...'
          : 'Cargando búfer de video...';
    });

    _startTorrentStatsTimer();

    try {
      if (!kIsWeb && _player?.platform is mpv.NativePlayer) {
        final np = _player!.platform as dynamic;
        await np.setProperty('hwdec', 'auto-safe');
        await np.setProperty('demuxer-max-bytes', '256M');
        await np.setProperty('demuxer-readahead-secs', '30');
        await np.setProperty('network-timeout', '60');
        await np.setProperty('cache', 'yes');
        await np.setProperty('stream-lavf-o', 'reconnect_streamed=1,reconnect_delay_max=5');
      }
    } catch (_) {}

    if (widget.stream.isTorrent && widget.stream.infoHash.isNotEmpty) {
      _prepareTorrentAndPlay();
    } else {
      _openStreamInPlayer();
    }
  }

  Future<void> _prepareTorrentAndPlay() async {
    final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
    final ih = widget.stream.infoHash.toLowerCase();

    // 1. Proactively tell streaming engine to attach / start peer search for this torrent
    try {
      final createUri = Uri.parse('$serverUrl/$ih/create');
      final allSources = <String>{
        ...widget.stream.sources,
        ...StreamCandidate.defaultTrackers,
      }.toList();

      final body = jsonEncode({
        'peerSearch': {'sources': allSources},
      });

      http.post(createUri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 4))
          .catchError((_) => http.Response('', 500));
    } catch (_) {}

    // 2. Poll metadata readiness or wait up to 20s before opening media
    int checks = 0;
    while (mounted && !_isMetadataReady && checks < 35) {
      await Future.delayed(const Duration(milliseconds: 600));
      checks++;
      if (_isMetadataReady || !mounted) break;
    }

    if (mounted && _isInitialLoading) {
      _openStreamInPlayer();
    }
  }

  Future<void> _openStreamInPlayer() async {
    if (!mounted) return;
    final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
    final directUrl = widget.localFilePath ?? widget.stream.playbackUrlFor(serverUrl);
    final url = widget.localFilePath ??
        (kIsWeb
            ? widget.stream.hlsPlaybackUrlFor(serverUrl)
            : directUrl);

    if (kDebugMode) {
      debugPrint('[ValkeryPlayer] Opening stream (attempt ${_openRetryCount + 1}): $url');
    }

    // On Web, if using HLS, ensure transcode playlist is responsive before attaching to HTML5 video element
    if (kIsWeb && url.contains('/hlsv2/')) {
      try {
        final headRes = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 6));
        if (headRes.statusCode != 200 && headRes.statusCode != 206) {
          if (_openRetryCount < _maxRetries) {
            _openRetryCount++;
            setState(() {
              _torrentStatusMessage = 'Preparando transcodificación HLS (reintentando $_openRetryCount/$_maxRetries)...';
            });
            Future.delayed(const Duration(milliseconds: 2000), () {
              if (mounted && _isInitialLoading) {
                _openStreamInPlayer();
              }
            });
            return;
          }
        }
      } catch (_) {
        if (_openRetryCount < _maxRetries) {
          _openRetryCount++;
          setState(() {
            _torrentStatusMessage = 'Iniciando búfer HLS (reintentando $_openRetryCount/$_maxRetries)...';
          });
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (mounted && _isInitialLoading) {
              _openStreamInPlayer();
            }
          });
          return;
        }
      }
    }

    try {
      if (kIsWeb) {
        await _webBridge?.open(url, fallbackDirectUrl: directUrl);
        _webBridge?.setVolume(_isMuted ? 0.0 : _volume);
      } else {
        await _player?.open(mpv.Media(url));
        await _player?.setVolume(_isMuted ? 0.0 : _volume);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ValkeryPlayer] Player.open caught exception: $e');
      }
    }
  }

  void _startTorrentStatsTimer() {
    _torrentStatsTimer?.cancel();
    if (!widget.stream.isTorrent || widget.stream.infoHash.isEmpty) return;

    final ih = widget.stream.infoHash.trim().toLowerCase();

    _torrentStatsTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!mounted) {
        _torrentStatsTimer?.cancel();
        return;
      }
      try {
        final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
        final res = await http.get(Uri.parse('$serverUrl/stats.json')).timeout(const Duration(seconds: 2));
        if (res.statusCode == 200 && mounted) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) {
            dynamic ihData = decoded[ih];
            if (ihData == null) {
              for (final entry in decoded.entries) {
                if (entry.key.toString().toLowerCase() == ih) {
                  ihData = entry.value;
                  break;
                }
              }
            }
            if (ihData is Map<String, dynamic>) {
              final peers = (ihData['peers'] as num?)?.toInt() ??
                  (num.tryParse(ihData['peers']?.toString() ?? '0') ?? 0).toInt();
              final speed = (ihData['downloadSpeed'] as num?)?.toInt() ??
                  (num.tryParse(ihData['downloadSpeed']?.toString() ?? '0') ?? 0).toInt();
              final downloaded = (ihData['downloaded'] as num?)?.toInt() ??
                  (num.tryParse(ihData['downloaded']?.toString() ?? '0') ?? 0).toInt();
              final files = ihData['files'];
              final hasFiles = files is List && files.isNotEmpty;

              setState(() {
                _torrentPeers = peers;
                _torrentDownloadSpeed = speed;
                _torrentDownloadedBytes = downloaded;
                if (hasFiles && !_isMetadataReady) {
                  _isMetadataReady = true;
                  _torrentStatusMessage = 'Metadatos listos. Descargando búfer de video...';
                } else if (!_isMetadataReady) {
                  if (peers > 0) {
                    _torrentStatusMessage = '$peers pares conectados. Obteniendo metadatos...';
                  } else {
                    _torrentStatusMessage = 'Conectando al enjambre de torrents y rastreadores...';
                  }
                } else {
                  _torrentStatusMessage = peers > 0
                      ? '$peers pares activos • ${_formatSpeed(speed)}'
                      : 'Bifurcando búfer de video...';
                }
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '0 KB/s';
    final kb = bytesPerSec / 1024.0;
    if (kb >= 1024.0) {
      return '${(kb / 1024.0).toStringAsFixed(1)} MB/s';
    }
    return '${kb.toStringAsFixed(0)} KB/s';
  }

  void _applySubtitleTrack(mpv.SubtitleTrack track, {String? indicatorLabel}) {
    if (!mounted) return;
    setState(() {
      _currentSubtitleTrack = track;
      if (track.id == 'no') {
        _webSubtitleText = null;
      }
    });
    if (kIsWeb) {
      final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
      _webBridge?.setSubtitleTrack(track, serverBaseUrl: serverUrl);
    } else {
      _player?.setSubtitleTrack(track);
    }
    if (indicatorLabel != null && indicatorLabel.isNotEmpty) {
      _showIndicator('Subtítulo: $indicatorLabel', IconsaxPlusLinear.subtitle);
    }
  }

  Future<void> _loadExternalSubtitles() async {
    setState(() => _isLoadingExternalSubs = true);
    final localTracks = <stremio_model.SubtitleTrack>[];
    if (widget.localSubtitles != null && widget.localSubtitles!.isNotEmpty) {
      for (var i = 0; i < widget.localSubtitles!.length; i++) {
        final lt = widget.localSubtitles![i];
        if (lt.localPath.isEmpty) continue;
        localTracks.add(
          stremio_model.SubtitleTrack(
            id: 'offline_sub_$i',
            lang: lt.language,
            url: lt.localPath,
            label: 'Offline #${i + 1}',
            addonName: 'Local Offline',
          ),
        );
      }
    }

    try {
      final isOffline = ref.read(stremioOfflineModeProvider);
      final remoteSubs = isOffline
          ? const <stremio_model.SubtitleTrack>[]
          : await ref.read(catalogAndStreamServiceProvider).fetchSubtitles(
                widget.media.id,
                widget.media.type,
                season: widget.season,
                episode: widget.episode,
              );
      final subs = <stremio_model.SubtitleTrack>[
        ...localTracks,
        ...remoteSubs,
      ];
      if (mounted) {
        setState(() {
          _externalSubtitles = subs;
          _isLoadingExternalSubs = false;
        });
        // Auto-select first Spanish subtitle (or fallback to embedded Spanish) if none active yet
        if (_currentSubtitleTrack.id == 'no') {
          if (subs.isNotEmpty) {
            final preferred = subs.where((s) => s.isSpanish).firstOrNull ?? subs.first;
            final autoTrack = mpv.SubtitleTrack.uri(
              preferred.url,
              title: preferred.displayTitle,
              language: preferred.lang,
            );
            _applySubtitleTrack(autoTrack);
          } else if (_embeddedSubtitles.isNotEmpty) {
            final spanishEmbedded = _embeddedSubtitles.where((s) {
              final l = (s.language ?? '').toLowerCase();
              final t = (s.title ?? '').toLowerCase();
              return l.contains('spa') || l == 'es' || l.contains('lat') || t.contains('espa') || t.contains('spa');
            }).firstOrNull;
            if (spanishEmbedded != null) {
              _applySubtitleTrack(spanishEmbedded);
            }
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (localTracks.isNotEmpty) {
            _externalSubtitles = localTracks;
          }
          _isLoadingExternalSubs = false;
        });
      }
    }
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isControlsVisible) {
      _hideControlsTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted && _playbackError == null && _isPlayingNow) {
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
    final current = _currentPosition;
    final total = _currentDuration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (total > Duration.zero && target > total ? total : target);

    _seekUnified(clamped);
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
      if (val > 0) _isWebAutoMuted = false;
    });
    if (kIsWeb) {
      _webBridge?.setVolume(val);
    } else {
      _player?.setVolume(val);
    }
    _showIndicator(
      '${val.round()}%',
      _isMuted
          ? IconsaxPlusLinear.volume_cross
          : (val > 50 ? IconsaxPlusLinear.volume_high : IconsaxPlusLinear.volume_low_1),
    );
    _showControls();
  }

  void _toggleMute() {
    if (_isMuted || _isWebAutoMuted) {
      _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0);
    } else {
      _volumeBeforeMute = _volume;
      _setVolume(0.0);
    }
  }

  void _setPlaybackRate(double rate) {
    setState(() => _playbackRate = rate);
    if (kIsWeb) {
      _webBridge?.setRate(rate);
    } else {
      _player?.setRate(rate);
    }
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
      if (kIsWeb) {
        _webBridge?.setVideoFit(_videoFit);
      }
    });
    _showControls();
  }

  bool _handleGlobalHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;

    // Do not intercept keys if a modal bottom sheet/dialog is open or a TextField is focused
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) return false;

    final primaryContext = FocusManager.instance.primaryFocus?.context;
    if (primaryContext != null && primaryContext.widget is EditableText) {
      return false;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _playOrPauseUnified();
      _showControls();
      return true;
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
      _seekRelative(-10);
      return true;
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyL) {
      _seekRelative(10);
      return true;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(5);
      return true;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-5);
      return true;
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return true;
    } else if (key == LogicalKeyboardKey.keyA) {
      _showAudioTracksSelectionDialog();
      return true;
    } else if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.keyC) {
      _showSubtitlesSelectionDialog();
      return true;
    } else if (key == LogicalKeyboardKey.keyF) {
      fullScreenHelper.toggleFullScreen(ref);
      return true;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return true;
    }
    return false;
  }

  Future<void> _savePlaybackProgress({bool isCompleted = false}) async {
    final position = _currentPosition.inSeconds;
    final duration = _currentDuration.inSeconds;

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

      final isOffline = storage.isOfflineMode ||
          ref.read(stremioOfflineModeProvider) ||
          authKey == null ||
          authKey.isEmpty;

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
        isLibraryItem: existing?.isLibraryItem ?? false,
        pendingOfflineSync: isOffline,
      );

      if (isOffline) {
        await storage.enqueueOfflineWatchSync(watchState);
      } else {
        await storage.upsertWatchState(watchState, enqueueOfflineSync: false);
        try {
          await api.syncWatchState(authKey, watchState);
        } catch (_) {
          await storage.enqueueOfflineWatchSync(watchState);
        }
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
    HardwareKeyboard.instance.removeHandler(_handleGlobalHardwareKey);
    _savePlaybackProgress();
    _hideControlsTimer?.cancel();
    _progressSyncTimer?.cancel();
    _indicatorTimer?.cancel();
    _torrentStatsTimer?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _logSubscription?.cancel();
    _errorSubscription?.cancel();
    _tracksSubscription?.cancel();
    _webSubTracksSubscription?.cancel();
    _webSubtitleCueSubscription?.cancel();
    _webAutoMutedSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _focusNode.dispose();
    _webBridge?.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (kIsWeb) {
          _webBridge?.pause();
        } else {
          _player?.pause();
        }
        _savePlaybackProgress();
      },
      child: Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          cursor: _isControlsVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _showControls(),
          onEnter: (_) => _showControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!_focusNode.hasFocus) {
                _focusNode.requestFocus();
              }
              if (kIsWeb && _isWebAutoMuted) {
                _webBridge?.unmuteFromUserGesture(_volume);
                _showIndicator('Sonido activado', IconsaxPlusLinear.volume_high);
                _showControls();
                return;
              }
              if (fullScreenHelper.isDesktopPlatform || kIsWeb) {
                // Single click on desktop/web toggles play/pause
                _playOrPauseUnified();
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
                  child: kIsWeb
                      ? _webBridge!.buildVideoWidget(fit: _videoFit)
                      : Video(
                          controller: _controller!,
                          controls: NoVideoControls,
                          fit: _videoFit,
                        ),
                ),

                // Web Subtitle Overlay (renders parsed VTT/SRT cues above CanvasKit video layer)
                if (kIsWeb && _webSubtitleText != null && _webSubtitleText!.trim().isNotEmpty)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: 24,
                    right: 24,
                    bottom: _isControlsVisible ? 114 : 36,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 960),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _webSubtitleText!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1)),
                                Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Web Auto-Muted Unmute Banner (if browser blocked unmuted autoplay)
                if (kIsWeb && _isWebAutoMuted && !_isInitialLoading)
                  Positioned(
                    top: 86,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () {
                            _webBridge?.unmuteFromUserGesture(_volume);
                            _showIndicator('Sonido activado', IconsaxPlusLinear.volume_high);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(IconsaxPlusBold.volume_cross, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Tocá para activar el sonido',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Center Initial Loading Overlay with Live Torrent/Stream Metrics
                if (_isInitialLoading && _playbackError == null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black87,
                            blurRadius: 32,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            widget.media.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.stream.quality,
                              style: const TextStyle(
                                color: Color(0xFFC4B5FD),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.stream.isTorrent
                                ? (_torrentPeers > 0
                                    ? '$_torrentPeers pares activos • ${_formatSpeed(_torrentDownloadSpeed)}'
                                    : _torrentStatusMessage)
                                : 'Cargando búfer de video...',
                            style: TextStyle(
                              color: widget.stream.isTorrent && _torrentPeers > 0
                                  ? Colors.greenAccent
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (widget.stream.isTorrent && _torrentDownloadedBytes > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${(_torrentDownloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB en caché inicial',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orangeAccent,
                              side: const BorderSide(color: Colors.orangeAccent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Abrir directamente en VLC'),
                            onPressed: () async {
                              final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
                              final streamUrl = widget.localFilePath ?? widget.stream.playbackUrlFor(serverUrl);
                              await ExternalPlayerLauncher.openInVlc(streamUrl);
                            },
                          ),
                        ],
                      ),
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
                  stream: _playingStream,
                  builder: (context, playingSnap) {
                    final isPlaying = playingSnap.data ?? _isPlayingNow;
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
                                _playUnified();
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
              // Torrent Stats Badge (if playing torrent)
              if (widget.stream.isTorrent) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _torrentPeers > 0
                          ? const Color(0xFF10B981).withValues(alpha: 0.6)
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        IconsaxPlusLinear.arrow_down,
                        size: 13,
                        color: _torrentPeers > 0 ? const Color(0xFF34D399) : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _torrentPeers > 0
                            ? '$_torrentPeers P • ${_formatSpeed(_torrentDownloadSpeed)}'
                            : '0 P',
                        style: TextStyle(
                          color: _torrentPeers > 0 ? const Color(0xFF34D399) : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
              const SizedBox(width: 8),
              // Audio Track Quick Button
              IconButton(
                tooltip: 'Pista de Audio (A)',
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                color: _currentAudioTrack.id != 'no' && _currentAudioTrack.id != 'auto'
                    ? const Color(0xFFC4B5FD)
                    : Colors.white70,
                icon: const Icon(IconsaxPlusLinear.audio_square),
                onPressed: _showAudioTracksSelectionDialog,
              ),
              // Subtitles Quick Button
              IconButton(
                tooltip: 'Subtítulos (S)',
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                color: _currentSubtitleTrack.id != 'no'
                    ? const Color(0xFFC4B5FD)
                    : Colors.white70,
                icon: const Icon(IconsaxPlusLinear.subtitle),
                onPressed: _showSubtitlesSelectionDialog,
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
      stream: _positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? _currentPosition;
        final duration = _currentDuration;
        final buffer = _currentBuffer;

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
                    _seekUnified(Duration(seconds: val.toInt()));
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
      stream: _playingStream,
      builder: (context, playingSnap) {
        final isPlaying = playingSnap.data ?? _isPlayingNow;

        return Row(
          children: [
            // Play / Pause Button
            IconButton(
              tooltip: isPlaying ? 'Pausar (Espacio)' : 'Reproducir (Espacio)',
              iconSize: 32,
              color: Colors.white,
              icon: Icon(isPlaying ? IconsaxPlusBold.pause : IconsaxPlusBold.play),
              onPressed: () {
                _playOrPauseUnified();
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
            if (fullScreenHelper.isDesktopPlatform || kIsWeb)
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

  String _normalizeSubtitleLanguage(String? rawLang, String? rawTitle) {
    final l = (rawLang ?? '').trim().toLowerCase();
    final t = (rawTitle ?? '').trim().toLowerCase();

    if (l == 'spl' ||
        l == 'es-419' ||
        l == 'es-la' ||
        l == 'lat' ||
        l.contains('latino') ||
        t.contains('latino') ||
        t.contains('latam') ||
        t.contains('(spl)')) {
      return 'Español (Latino)';
    }
    if (l == 'spa' ||
        l == 'es' ||
        l == 'esp' ||
        l == 'es-es' ||
        l.startsWith('es-') ||
        l.contains('spanish') ||
        l.contains('español') ||
        t.contains('español') ||
        t.contains('spanish')) {
      return 'Español';
    }
    if (l == 'eng' ||
        l == 'en' ||
        l.startsWith('en-') ||
        l.contains('english') ||
        t.contains('inglés') ||
        t.contains('english')) {
      return 'Inglés';
    }
    if (l == 'pob' || l == 'pt-br' || l == 'pb' || t.contains('brasil')) {
      return 'Portugués (Brasil)';
    }
    if (l == 'por' || l == 'pt' || l.startsWith('pt-') || l.contains('portug')) {
      return 'Portugués';
    }
    if (l == 'fre' || l == 'fra' || l == 'fr' || l.startsWith('fr-')) return 'Francés';
    if (l == 'deu' || l == 'ger' || l == 'de' || l.startsWith('de-')) return 'Alemán';
    if (l == 'ita' || l == 'it' || l.startsWith('it-')) return 'Italiano';
    if (l == 'jpn' || l == 'ja') return 'Japonés';
    if (l == 'kor' || l == 'ko') return 'Coreano';
    if (l == 'rus' || l == 'ru') return 'Ruso';
    if (l == 'ara' || l == 'ar') return 'Árabe';
    if (l == 'zho' || l == 'chi' || l == 'zh' || l == 'zht' || l == 'zhs') return 'Chino';
    if (l == 'nld' || l == 'dut' || l == 'nl') return 'Neerlandés';
    if (l == 'pol' || l == 'pl') return 'Polaco';
    if (l == 'tur' || l == 'tr') return 'Turco';
    if (l == 'swe' || l == 'sv') return 'Sueco';
    if (l == 'dan' || l == 'da') return 'Danés';
    if (l == 'fin' || l == 'fi') return 'Finés';
    if (l == 'nor' || l == 'no' || l == 'nob') return 'Noruego';
    if (l == 'heb' || l == 'he') return 'Hebreo';
    if (l == 'hun' || l == 'hu') return 'Húngaro';
    if (l == 'ces' || l == 'cze' || l == 'cs') return 'Checo';
    if (l == 'ell' || l == 'gre' || l == 'el') return 'Griego';
    if (l == 'ron' || l == 'rum' || l == 'ro') return 'Rumano';
    if (l == 'ukr' || l == 'uk') return 'Ucraniano';
    if (l == 'ind' || l == 'id') return 'Indonesio';
    if (l == 'hin' || l == 'hi') return 'Hindi';
    if (l == 'cat' || l == 'ca') return 'Catalán';
    if (l == 'eus' || l == 'baq' || l == 'eu') return 'Euskera';
    if (l == 'glg' || l == 'gl') return 'Gallego';

    if (l.isNotEmpty) {
      return l.length <= 3 ? l.toUpperCase() : '${l[0].toUpperCase()}${l.substring(1)}';
    }
    return 'Otros idiomas';
  }

  int _languagePriorityRank(String langGroup) {
    switch (langGroup) {
      case 'Español (Latino)':
        return 0;
      case 'Español':
        return 1;
      case 'Inglés':
        return 2;
      case 'Portugués (Brasil)':
        return 3;
      case 'Portugués':
        return 4;
      case 'Otros idiomas':
        return 999;
      default:
        return 10;
    }
  }

  void _showSubtitlesSelectionDialog() {
    _showControls();
    String searchQuery = '';
    String selectedLangFilter = 'Todos';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Build unified list of subtitle options (Embedded + External)
            final entries = <_SubtitleOptionItem>[];

            // 1. Embedded tracks
            int embIdx = 1;
            for (final sub in _embeddedSubtitles) {
              if (sub.id == 'no' || sub.id == 'auto') continue;
              final group = _normalizeSubtitleLanguage(sub.language, sub.title);
              final rawTitle = (sub.title ?? '').trim();
              final display = rawTitle.isNotEmpty ? rawTitle : '$group (Pista #$embIdx)';
              entries.add(
                _SubtitleOptionItem(
                  id: sub.id,
                  languageGroup: group,
                  title: display,
                  subtitle: 'Pista integrada en el contenedor de video',
                  badge: 'Incrustado MKV',
                  isEmbedded: true,
                  track: sub,
                ),
              );
              embIdx++;
            }

            // 2. External addon tracks
            final Map<String, int> langCounter = {};
            for (final extSub in _externalSubtitles) {
              final group = _normalizeSubtitleLanguage(extSub.lang, extSub.label);
              final count = (langCounter[group] ?? 0) + 1;
              langCounter[group] = count;

              // Extract release/version suffix if present after '•'
              String versionTitle = extSub.displayTitle;
              if (versionTitle.contains('•')) {
                final parts = versionTitle.split('•');
                versionTitle = parts.sublist(1).join('•').trim();
              } else {
                // Distinguish multiple tracks of the same language by short URL/ID suffix or index
                final uriPath = Uri.tryParse(extSub.url)?.pathSegments.lastOrNull ?? '';
                final cleanFile = uriPath.replaceAll(RegExp(r'\.(srt|vtt)$', caseSensitive: false), '');
                if (cleanFile.isNotEmpty && cleanFile.length > 3 && !RegExp(r'^\d+$').hasMatch(cleanFile)) {
                  versionTitle = '$group #$count ($cleanFile)';
                } else {
                  versionTitle = '$group • Opción #$count';
                }
              }

              final track = mpv.SubtitleTrack.uri(
                extSub.url,
                title: extSub.displayTitle,
                language: extSub.lang,
              );

              entries.add(
                _SubtitleOptionItem(
                  id: extSub.url,
                  languageGroup: group,
                  title: versionTitle,
                  subtitle: extSub.addonName,
                  badge: extSub.addonName,
                  isEmbedded: false,
                  track: track,
                ),
              );
            }

            // Group counts across all entries (before search/chip filter)
            final Map<String, int> groupCounts = {};
            for (final e in entries) {
              groupCounts[e.languageGroup] = (groupCounts[e.languageGroup] ?? 0) + 1;
            }

            final sortedLanguages = groupCounts.keys.toList()
              ..sort((a, b) {
                final rA = _languagePriorityRank(a);
                final rB = _languagePriorityRank(b);
                if (rA != rB) return rA.compareTo(rB);
                return a.compareTo(b);
              });

            // Apply language chip & text search filter
            final q = searchQuery.trim().toLowerCase();
            final filteredEntries = entries.where((e) {
              if (selectedLangFilter != 'Todos' && e.languageGroup != selectedLangFilter) {
                return false;
              }
              if (q.isEmpty) return true;
              return e.languageGroup.toLowerCase().contains(q) ||
                  e.title.toLowerCase().contains(q) ||
                  e.subtitle.toLowerCase().contains(q) ||
                  e.badge.toLowerCase().contains(q);
            }).toList();

            // Group filtered entries by languageGroup
            final Map<String, List<_SubtitleOptionItem>> groupedFiltered = {};
            for (final lang in sortedLanguages) {
              final matching = filteredEntries.where((e) => e.languageGroup == lang).toList();
              if (matching.isNotEmpty) {
                groupedFiltered[lang] = matching;
              }
            }

            final isSubOff = _currentSubtitleTrack.id == 'no';

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.78,
                ),
                padding: EdgeInsets.only(
                  top: 18,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(IconsaxPlusLinear.subtitle, color: Color(0xFF8B5CF6), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Subtítulos',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${entries.length} disponibles',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isSubOff
                                      ? 'Desactivados actualmente'
                                      : 'Activo: ${_currentSubtitleTrack.title ?? _currentSubtitleTrack.language ?? "Subtítulo seleccionado"}',
                                  style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (_isLoadingExternalSubs)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Filtrar por idioma, versión o fuente (ej. Español, Latino, MKV)...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1, color: Colors.white54, size: 18),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                  onPressed: () => setModalState(() => searchQuery = ''),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                          ),
                        ),
                        onChanged: (val) => setModalState(() => searchQuery = val),
                      ),
                    ),

                    // Language Quick-Filter Chips
                    if (sortedLanguages.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('Todos (${entries.length})'),
                                selected: selectedLangFilter == 'Todos',
                                onSelected: (_) => setModalState(() => selectedLangFilter = 'Todos'),
                                selectedColor: const Color(0xFF8B5CF6),
                                backgroundColor: Colors.white.withValues(alpha: 0.07),
                                labelStyle: TextStyle(
                                  color: selectedLangFilter == 'Todos' ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: selectedLangFilter == 'Todos' ? FontWeight.bold : FontWeight.normal,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                side: BorderSide.none,
                                showCheckmark: false,
                              ),
                            ),
                            for (final lang in sortedLanguages)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('$lang (${groupCounts[lang]})'),
                                  selected: selectedLangFilter == lang,
                                  onSelected: (_) => setModalState(() {
                                    selectedLangFilter = selectedLangFilter == lang ? 'Todos' : lang;
                                  }),
                                  selectedColor: const Color(0xFF8B5CF6),
                                  backgroundColor: Colors.white.withValues(alpha: 0.07),
                                  labelStyle: TextStyle(
                                    color: selectedLangFilter == lang ? Colors.white : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: selectedLangFilter == lang ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  side: BorderSide.none,
                                  showCheckmark: false,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12, height: 1),

                    // Grouped Subtitle Tracks List
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          // Disable subtitles option
                          if (searchQuery.isEmpty && selectedLangFilter == 'Todos')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: isSubOff
                                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  leading: Icon(
                                    Icons.subtitles_off_outlined,
                                    color: isSubOff ? const Color(0xFFC4B5FD) : Colors.white60,
                                    size: 20,
                                  ),
                                  title: Text(
                                    'Desactivar subtítulos',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: isSubOff ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: isSubOff
                                      ? const Icon(IconsaxPlusBold.tick_circle, color: Color(0xFF8B5CF6), size: 20)
                                      : null,
                                  onTap: () {
                                    _applySubtitleTrack(mpv.SubtitleTrack.no(), indicatorLabel: 'Desactivados');
                                    Navigator.pop(context);
                                  },
                                ),
                              ),
                            ),

                          if (groupedFiltered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  _isLoadingExternalSubs
                                      ? 'Buscando subtítulos en addons...'
                                      : 'No se encontraron subtítulos para este filtro.',
                                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                              ),
                            ),

                          for (final entry in groupedFiltered.entries) ...[
                            // Language Group Header
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 6, left: 4, right: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.language, size: 15, color: Color(0xFFC4B5FD)),
                                  const SizedBox(width: 6),
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      color: Color(0xFFC4B5FD),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${entry.value.length}',
                                      style: const TextStyle(
                                        color: Color(0xFFC4B5FD),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Tracks inside this language group
                            for (final item in entry.value)
                              Builder(
                                builder: (context) {
                                  final isSelected = _currentSubtitleTrack.id == item.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: isSelected
                                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(12),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          _applySubtitleTrack(
                                            item.track,
                                            indicatorLabel: '${item.languageGroup} • ${item.title}',
                                          );
                                          Navigator.pop(context);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent,
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                item.isEmbedded
                                                    ? IconsaxPlusLinear.video_square
                                                    : IconsaxPlusLinear.subtitle,
                                                size: 18,
                                                color: isSelected ? const Color(0xFFC4B5FD) : Colors.white60,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.title,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13.5,
                                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: item.isEmbedded
                                                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                                                : Colors.white10,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            item.badge,
                                                            style: TextStyle(
                                                              color: item.isEmbedded
                                                                  ? const Color(0xFF34D399)
                                                                  : Colors.white60,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(
                                                  IconsaxPlusBold.tick_circle,
                                                  color: Color(0xFF8B5CF6),
                                                  size: 20,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
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
    ).whenComplete(() {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  String _formatAudioLanguage(String? lang) {
    if (lang == null || lang.trim().isEmpty) return 'Audio Principal';
    final l = lang.trim().toLowerCase();
    switch (l) {
      case 'spa':
      case 'es':
      case 'esp':
        return 'Español (Castellano)';
      case 'lat':
      case 'es-419':
      case 'es-la':
      case 'latin':
        return 'Español (Latino)';
      case 'eng':
      case 'en':
      case 'en-us':
      case 'en-gb':
        return 'Inglés';
      case 'jpn':
      case 'ja':
        return 'Japonés';
      case 'por':
      case 'pt':
      case 'pt-br':
        return 'Portugués';
      case 'fra':
      case 'fre':
      case 'fr':
        return 'Francés';
      case 'deu':
      case 'ger':
      case 'de':
        return 'Alemán';
      case 'ita':
      case 'it':
        return 'Italiano';
      case 'rus':
      case 'ru':
        return 'Ruso';
      case 'kor':
      case 'ko':
        return 'Coreano';
      case 'zho':
      case 'chi':
      case 'zh':
        return 'Chino';
      default:
        return l.length <= 4 ? l.toUpperCase() : (l[0].toUpperCase() + l.substring(1));
    }
  }

  String _formatAudioCodecAndChannels(mpv.AudioTrack audio) {
    final parts = <String>[];
    final title = (audio.title ?? '').toLowerCase();

    // Channels
    if (title.contains('7.1')) {
      parts.add('7.1 Surround');
    } else if (title.contains('5.1')) {
      parts.add('5.1 Surround');
    } else if (title.contains('stereo') || title.contains('2.0') || title.contains('estéreo')) {
      parts.add('Estéreo');
    }

    // Codecs
    if (title.contains('atmos')) {
      parts.add('Dolby Atmos');
    } else if (title.contains('truehd')) {
      parts.add('Dolby TrueHD');
    } else if (title.contains('eac3') || title.contains('ddp') || title.contains('dd+')) {
      parts.add('Dolby Digital+');
    } else if (title.contains('ac3') || title.contains('dd5.1') || title.contains('dolby digital')) {
      parts.add('Dolby Digital');
    } else if (title.contains('dts-hd')) {
      parts.add('DTS-HD');
    } else if (title.contains('dts')) {
      parts.add('DTS');
    } else if (title.contains('aac')) {
      parts.add('AAC');
    } else if (title.contains('flac')) {
      parts.add('FLAC');
    } else if (title.contains('opus')) {
      parts.add('Opus');
    }

    if (parts.isEmpty) {
      return audio.title?.isNotEmpty == true ? audio.title! : 'Pista ${audio.id}';
    }
    return parts.join(' • ');
  }

  void _showAudioTracksSelectionDialog() {
    _showControls();
    final validTracks = _audioTracks.where((a) => a.id != 'no').toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161426),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(IconsaxPlusLinear.audio_square, color: Color(0xFF8B5CF6), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pistas de Audio',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Selecciona el idioma o canal de doblaje deseado',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 12),

                // Track list or single track info
                if (validTracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(IconsaxPlusLinear.volume_high, color: Color(0xFF8B5CF6), size: 36),
                          const SizedBox(height: 12),
                          const Text(
                            'Audio Original Activo',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            kIsWeb
                                ? 'En navegador Web, el audio se procesa automáticamente a estéreo de alta fidelidad (AAC).'
                                : 'Este contenido cuenta con una única pista de audio principal activa.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: validTracks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final audio = validTracks[index];
                        final isSelected = _currentAudioTrack.id == audio.id ||
                            (audio.id == 'auto' && _currentAudioTrack.id.isEmpty);
                        final langName = _formatAudioLanguage(audio.language ?? audio.title);
                        final details = _formatAudioCodecAndChannels(audio);

                        return Material(
                          color: isSelected
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              if (kIsWeb) {
                                _webBridge?.setAudioTrack(audio);
                              } else {
                                _player?.setAudioTrack(audio);
                              }
                              setState(() => _currentAudioTrack = audio);
                              _showIndicator('Audio: $langName', IconsaxPlusLinear.audio_square);
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                                          : Colors.white.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      IconsaxPlusLinear.volume_high,
                                      size: 18,
                                      color: isSelected ? Colors.white : Colors.white60,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          langName,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          ),
                                        ),
                                        if (details.isNotEmpty && details != langName) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            details,
                                            style: TextStyle(
                                              color: isSelected ? const Color(0xFFC4B5FD) : Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      IconsaxPlusBold.tick_circle,
                                      color: Color(0xFF8B5CF6),
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
                  leading: const Icon(IconsaxPlusLinear.audio_square, color: Color(0xFF8B5CF6)),
                  title: const Text('Pistas de Audio', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _formatAudioLanguage(_currentAudioTrack.language ?? _currentAudioTrack.title),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showAudioTracksSelectionDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(IconsaxPlusLinear.subtitle, color: Color(0xFF8B5CF6)),
                  title: const Text('Subtítulos', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _currentSubtitleTrack.id == 'no'
                        ? 'Desactivados'
                        : (_currentSubtitleTrack.title?.isNotEmpty == true
                            ? _currentSubtitleTrack.title!
                            : (_currentSubtitleTrack.language ?? 'Activados')),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSubtitlesSelectionDialog();
                  },
                ),
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

class _SubtitleOptionItem {
  final String id;
  final String languageGroup;
  final String title;
  final String subtitle;
  final String badge;
  final bool isEmbedded;
  final mpv.SubtitleTrack track;

  const _SubtitleOptionItem({
    required this.id,
    required this.languageGroup,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.isEmbedded,
    required this.track,
  });
}
