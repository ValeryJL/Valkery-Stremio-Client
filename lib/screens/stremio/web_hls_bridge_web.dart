// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mpv;

import 'web_hls_bridge.dart';

WebHlsBridge createWebHlsBridge() => _RealWebHlsBridge();

class _SubtitleCue {
  final double startSeconds;
  final double endSeconds;
  final String text;

  const _SubtitleCue({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });
}

class _RealWebHlsBridge implements WebHlsBridge {
  static int _nextViewId = 1;

  late final int _viewId;
  late final String _viewType;
  late final html.DivElement _containerElement;
  late final html.VideoElement _videoElement;

  Object? _hlsInstance;
  String? _currentUrl;
  String? _fallbackDirectUrl;
  bool _triedDirectFallback = false;
  int _networkErrorRetries = 0;
  int _mediaErrorRetries = 0;
  bool _disposed = false;

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferController = StreamController<Duration>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _audioTracksController = StreamController<List<mpv.AudioTrack>>.broadcast();
  final _subtitleTracksController = StreamController<List<mpv.SubtitleTrack>>.broadcast();
  final _autoMutedController = StreamController<bool>.broadcast();
  final _subtitleCueTextController = StreamController<String?>.broadcast();

  final List<StreamSubscription> _domSubscriptions = [];

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isAutoMuted = false;
  double _targetVolume = 1.0;

  List<_SubtitleCue> _parsedCues = [];
  String? _currentSubtitleCueText;
  int _subtitleLoadGeneration = 0;

  _RealWebHlsBridge() {
    _viewId = _nextViewId++;
    _viewType = 'com.valkery.stremio.web_hls_video_$_viewId';

    _videoElement = html.VideoElement()
      ..autoplay = true
      ..controls = false
      ..muted = false
      ..crossOrigin = 'anonymous'
      ..tabIndex = -1
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true')
      ..setAttribute('preload', 'auto')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000000'
      ..style.border = 'none'
      ..style.outline = 'none'
      ..style.display = 'block'
      ..style.pointerEvents = 'none';

    _containerElement = html.DivElement()
      ..tabIndex = -1
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#000000'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.pointerEvents = 'none'
      ..append(_videoElement);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _containerElement,
    );

    _bindVideoEvents();
  }

  void _bindVideoEvents() {
    _domSubscriptions.add(_videoElement.onPlay.listen((_) {
      _isPlaying = true;
      if (!_disposed) _playingController.add(true);
    }));

    _domSubscriptions.add(_videoElement.onPlaying.listen((_) {
      _isPlaying = true;
      if (!_disposed) _playingController.add(true);
    }));

    _domSubscriptions.add(_videoElement.onPause.listen((_) {
      _isPlaying = false;
      if (!_disposed) _playingController.add(false);
    }));

    _domSubscriptions.add(_videoElement.onEnded.listen((_) {
      _isPlaying = false;
      if (!_disposed) {
        _playingController.add(false);
        _completedController.add(true);
      }
    }));

    _domSubscriptions.add(_videoElement.onDurationChange.listen((_) {
      _updateDuration();
    }));

    _domSubscriptions.add(_videoElement.onLoadedMetadata.listen((_) {
      _updateDuration();
      _jumpInitialPtsGapIfNeeded();
      _attemptAutoPlay();
    }));

    _domSubscriptions.add(_videoElement.onCanPlay.listen((_) {
      _updateDuration();
      _jumpInitialPtsGapIfNeeded();
      if (!_isPlaying) {
        _attemptAutoPlay();
      }
    }));

    _domSubscriptions.add(_videoElement.onTimeUpdate.listen((_) {
      final sec = _videoElement.currentTime;
      if (!sec.isNaN && !sec.isInfinite && sec >= 0) {
        _position = Duration(milliseconds: (sec * 1000).round());
        if (!_disposed) _positionController.add(_position);
        _updateActiveSubtitleCue(sec);
      }
      _updateBuffer();
    }));

    _domSubscriptions.add(_videoElement.on['progress'].listen((_) {
      _updateBuffer();
    }));

    _domSubscriptions.add(_videoElement.onError.listen((_) {
      final err = _videoElement.error;
      final code = err?.code ?? 0;
      final msg = err?.message ?? 'HTML5 Video Error ($code)';
      if (kDebugMode) {
        debugPrint('[ValkeryWebHls] videoElement.onError: code=$code msg=$msg');
      }
      if (_hlsInstance == null && !_triedDirectFallback && _fallbackDirectUrl != null) {
        _triedDirectFallback = true;
        _openDirectHtml5(_fallbackDirectUrl!);
        return;
      }
      if (!_disposed && _duration == Duration.zero) {
        _errorController.add(msg);
      }
    }));
  }

  void _updateActiveSubtitleCue(num currentTimeSec) {
    if (_parsedCues.isEmpty) {
      if (_currentSubtitleCueText != null) {
        _currentSubtitleCueText = null;
        if (!_disposed) _subtitleCueTextController.add(null);
      }
      return;
    }

    final matchingTexts = <String>[];
    for (final cue in _parsedCues) {
      if (currentTimeSec >= cue.startSeconds && currentTimeSec <= cue.endSeconds) {
        matchingTexts.add(cue.text);
      }
    }

    final combined = matchingTexts.isEmpty ? null : matchingTexts.join('\n');
    if (combined != _currentSubtitleCueText) {
      _currentSubtitleCueText = combined;
      if (!_disposed) _subtitleCueTextController.add(combined);
    }
  }

  void _updateDuration() {
    final dur = _videoElement.duration;
    if (!dur.isNaN && !dur.isInfinite && dur > 0) {
      _duration = Duration(milliseconds: (dur * 1000).round());
      if (!_disposed) _durationController.add(_duration);
    }
  }

  void _updateBuffer() {
    try {
      final buffered = _videoElement.buffered;
      if (buffered.length > 0) {
        final end = buffered.end(buffered.length - 1);
        if (!end.isNaN && !end.isInfinite && end >= 0) {
          _buffer = Duration(milliseconds: (end * 1000).round());
          if (!_disposed) _bufferController.add(_buffer);
        }
      }
    } catch (_) {}
  }

  /// Jumps the initial PTS gap (e.g. [0.000, 0.083333)) caused by `-mpegts_copyts 1` in rivulet-engine
  void _jumpInitialPtsGapIfNeeded() {
    try {
      final buffered = _videoElement.buffered;
      if (buffered.length > 0) {
        final start0 = buffered.start(0);
        final end0 = buffered.end(0);
        final cur = _videoElement.currentTime;
        if (start0 > 0.005 && cur < start0 && end0 > start0 + 0.05) {
          if (kDebugMode) {
            debugPrint('[ValkeryWebHls] Jumping initial PTS gap: $cur -> ${start0 + 0.02}');
          }
          _videoElement.currentTime = start0 + 0.02;
        }
      }
    } catch (_) {}
  }

  void _attemptAutoPlay() {
    if (_disposed) return;
    try {
      final playPromise = _videoElement.play();
      playPromise.then((_) {
        _isPlaying = true;
        if (!_disposed) _playingController.add(true);
      }).catchError((err) {
        final errStr = err.toString().toLowerCase();
        if (kDebugMode) {
          debugPrint('[ValkeryWebHls] Unmuted play() rejected ($err); falling back to muted autoplay');
        }
        if (errStr.contains('notallowed') ||
            errStr.contains('interact') ||
            errStr.contains('gesture') ||
            !_isPlaying) {
          _videoElement.muted = true;
          _isAutoMuted = true;
          if (!_disposed) _autoMutedController.add(true);
          _videoElement.play().then((_) {
            _isPlaying = true;
            if (!_disposed) _playingController.add(true);
          }).catchError((e2) {
            if (kDebugMode) {
              debugPrint('[ValkeryWebHls] Muted autoplay also rejected: $e2');
            }
          });
        }
      });
    } catch (_) {}
  }

  @override
  Future<void> open(String hlsUrl, {String? fallbackDirectUrl}) async {
    if (_disposed) return;
    _currentUrl = hlsUrl;
    _fallbackDirectUrl = fallbackDirectUrl;
    _triedDirectFallback = false;
    _networkErrorRetries = 0;
    _mediaErrorRetries = 0;

    _destroyHls();

    final isHlsUrl = hlsUrl.contains('.m3u8') || hlsUrl.contains('/hlsv2/');
    final hlsCtor = js_util.getProperty<Object?>(html.window, 'Hls');
    final isHlsSupported = hlsCtor != null &&
        (js_util.callMethod<bool?>(hlsCtor, 'isSupported', const []) ?? false);

    if (isHlsUrl && isHlsSupported) {
      _openWithHlsJs(hlsCtor, hlsUrl);
    } else {
      _openDirectHtml5(hlsUrl);
    }
  }

  void _openWithHlsJs(Object hlsCtor, String url) {
    // CRITICAL: renderTextTracksNatively: false + subtitleTrackController disabled on load
    // prevents hls.js from automatically requesting `sub0.vtt` on `DEFAULT=YES,AUTOSELECT=YES`
    // in master.m3u8, which otherwise causes rivulet-engine to launch a full-file ffmpeg
    // subtitle demux that stalls seg0.ts/seg1.ts!
    final config = js_util.jsify({
      'enableWorker': true,
      'lowLatencyMode': false,
      'renderTextTracksNatively': false,
      'enableWebVTT': false,
      'enableIMSC1': false,
      'enableCEA708Captions': false,
      'backBufferLength': 60,
      'maxBufferLength': 60,
      'maxMaxBufferLength': 120,
      'maxBufferSize': 60 * 1000 * 1000,
      'maxBufferHole': 2.5,
      'highBufferWatchdogPeriod': 2,
      'nudgeOffset': 0.2,
      'nudgeMaxRetry': 12,
      'maxFragLookUpTolerance': 0.25,
      'startFragPrefetch': true,
      'startPosition': 0,
      'manifestLoadingTimeOut': 45000,
      'manifestLoadingMaxRetry': 6,
      'manifestLoadingRetryDelay': 1500,
      'levelLoadingTimeOut': 45000,
      'levelLoadingMaxRetry': 6,
      'levelLoadingRetryDelay': 1500,
      'fragLoadingTimeOut': 65000,
      'fragLoadingMaxRetry': 8,
      'fragLoadingRetryDelay': 1500,
    });

    final hls = js_util.callConstructor<Object>(hlsCtor, [config]);
    _hlsInstance = hls;

    try {
      js_util.setProperty(hls, 'subtitleTrack', -1);
      js_util.setProperty(hls, 'subtitleDisplay', false);
    } catch (_) {}

    // Listen to MANIFEST_PARSED
    js_util.callMethod(hls, 'on', [
      'hlsManifestParsed',
      js_util.allowInterop((Object? event, Object? data) {
        if (_disposed) return;
        try {
          js_util.setProperty(hls, 'subtitleTrack', -1);
          js_util.setProperty(hls, 'subtitleDisplay', false);
        } catch (_) {}
        _extractHlsAudioTracks(hls, data);
        _extractHlsSubtitleTracks(hls, data);
        _attemptAutoPlay();
      }),
    ]);

    // Listen to AUDIO_TRACKS_UPDATED
    js_util.callMethod(hls, 'on', [
      'hlsAudioTracksUpdated',
      js_util.allowInterop((Object? event, Object? data) {
        if (_disposed) return;
        _extractHlsAudioTracks(hls, data);
      }),
    ]);

    // Listen to SUBTITLE_TRACKS_UPDATED
    js_util.callMethod(hls, 'on', [
      'hlsSubtitleTracksUpdated',
      js_util.allowInterop((Object? event, Object? data) {
        if (_disposed) return;
        try {
          js_util.setProperty(hls, 'subtitleTrack', -1);
          js_util.setProperty(hls, 'subtitleDisplay', false);
        } catch (_) {}
        _extractHlsSubtitleTracks(hls, data);
      }),
    ]);

    // Listen to FRAG_BUFFERED -> jump initial PTS gap and ensure playback starts
    js_util.callMethod(hls, 'on', [
      'hlsFragBuffered',
      js_util.allowInterop((Object? event, Object? data) {
        if (_disposed) return;
        _updateDuration();
        _updateBuffer();
        _jumpInitialPtsGapIfNeeded();
        if (!_isPlaying) {
          _attemptAutoPlay();
        }
      }),
    ]);

    // Listen to ERROR for automatic recovery
    js_util.callMethod(hls, 'on', [
      'hlsError',
      js_util.allowInterop((Object? event, Object? data) {
        if (_disposed || data == null) return;
        final isFatal = js_util.getProperty<bool?>(data, 'fatal') ?? false;
        final type = js_util.getProperty<String?>(data, 'type') ?? '';
        final details = js_util.getProperty<String?>(data, 'details') ?? '';

        if (kDebugMode) {
          debugPrint('[ValkeryWebHls] HLS event error: fatal=$isFatal type=$type details=$details');
        }

        if (details == 'bufferStalledError' || details == 'bufferSeekOverHole' || details == 'bufferNudgeOnStall') {
          _jumpInitialPtsGapIfNeeded();
        }

        if (!isFatal) return;

        if (type == 'networkError') {
          if (_networkErrorRetries < 6) {
            _networkErrorRetries++;
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (_disposed || _hlsInstance == null) return;
              try {
                if (details.contains('manifest') || details.contains('level')) {
                  js_util.callMethod(_hlsInstance!, 'loadSource', [url]);
                }
                js_util.callMethod(_hlsInstance!, 'startLoad', const []);
              } catch (_) {}
            });
            return;
          }
        } else if (type == 'mediaError') {
          if (_mediaErrorRetries < 4) {
            _mediaErrorRetries++;
            try {
              if (_mediaErrorRetries == 2) {
                js_util.callMethod(hls, 'swapAudioCodec', const []);
              }
              js_util.callMethod(hls, 'recoverMediaError', const []);
              return;
            } catch (_) {}
          }
        }

        if (!_triedDirectFallback && _fallbackDirectUrl != null && _fallbackDirectUrl != url) {
          _triedDirectFallback = true;
          _destroyHls();
          _openDirectHtml5(_fallbackDirectUrl!);
          return;
        }

        if (!_disposed && _duration == Duration.zero) {
          _errorController.add('HLS Error ($type: $details)');
        }
      }),
    ]);

    js_util.callMethod(hls, 'loadSource', [url]);
    js_util.callMethod(hls, 'attachMedia', [_videoElement]);
  }

  void _openDirectHtml5(String url) {
    _videoElement.src = url;
    _videoElement.load();
    _attemptAutoPlay();
  }

  void _extractHlsAudioTracks(Object hls, Object? data) {
    try {
      final rawList = js_util.getProperty<List<dynamic>?>(hls, 'audioTracks');
      if (rawList == null || rawList.isEmpty) return;

      final tracks = <mpv.AudioTrack>[];
      for (int i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item == null) continue;
        final name = js_util.getProperty<Object?>(item, 'name')?.toString() ?? 'Pista ${i + 1}';
        final lang = js_util.getProperty<Object?>(item, 'lang')?.toString() ?? '';
        final attrs = js_util.getProperty<Object?>(item, 'attrs');
        String channels = '';
        if (attrs != null) {
          channels = js_util.getProperty<Object?>(attrs, 'CHANNELS')?.toString() ?? '';
        }
        final title = channels.isNotEmpty ? '$name ($channels ch)' : name;
        tracks.add(mpv.AudioTrack(i.toString(), title, lang.isNotEmpty ? lang : name));
      }

      if (tracks.isNotEmpty && !_disposed) {
        _audioTracksController.add(tracks);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ValkeryWebHls] Error extracting audio tracks: $e');
      }
    }
  }

  void _extractHlsSubtitleTracks(Object hls, Object? data) {
    try {
      List<dynamic>? rawList = js_util.getProperty<List<dynamic>?>(hls, 'subtitleTracks');
      if ((rawList == null || rawList.isEmpty) && data != null) {
        rawList = js_util.getProperty<List<dynamic>?>(data, 'subtitleTracks');
      }
      if (rawList == null || rawList.isEmpty) return;

      final tracks = <mpv.SubtitleTrack>[];
      for (int i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item == null) continue;
        final name = js_util.getProperty<Object?>(item, 'name')?.toString() ?? 'Subtítulo ${i + 1}';
        final lang = js_util.getProperty<Object?>(item, 'lang')?.toString() ?? '';
        tracks.add(mpv.SubtitleTrack('hls_sub_$i', name, lang.isNotEmpty ? lang : name));
      }

      if (tracks.isNotEmpty && !_disposed) {
        _subtitleTracksController.add(tracks);
      }
    } catch (_) {}
  }

  @override
  void play() {
    if (_disposed) return;
    _jumpInitialPtsGapIfNeeded();
    if (_isAutoMuted) {
      _videoElement.muted = false;
      _videoElement.volume = _targetVolume;
      _isAutoMuted = false;
      _autoMutedController.add(false);
    }
    _videoElement.play().then((_) {
      _isPlaying = true;
      if (!_disposed) _playingController.add(true);
    }).catchError((_) {
      _videoElement.muted = true;
      _isAutoMuted = true;
      if (!_disposed) _autoMutedController.add(true);
      _videoElement.play();
    });
  }

  @override
  void pause() {
    if (_disposed) return;
    _videoElement.pause();
    _isPlaying = false;
    _playingController.add(false);
  }

  @override
  void playOrPause() {
    if (_videoElement.paused) {
      play();
    } else {
      pause();
    }
  }

  @override
  void unmuteFromUserGesture(double volume0to100) {
    if (_disposed) return;
    _targetVolume = (volume0to100 / 100.0).clamp(0.0, 1.0);
    _videoElement.muted = false;
    _videoElement.volume = _targetVolume;
    if (_isAutoMuted) {
      _isAutoMuted = false;
      _autoMutedController.add(false);
    }
    if (_videoElement.paused) {
      _jumpInitialPtsGapIfNeeded();
      _videoElement.play();
    }
  }

  @override
  void seek(Duration target) {
    if (_disposed) return;
    final sec = target.inMilliseconds / 1000.0;
    final clampedSec = sec < 0 ? 0.0 : sec;
    _videoElement.currentTime = clampedSec;
    _position = target;
    _positionController.add(target);
    _updateActiveSubtitleCue(clampedSec);
  }

  @override
  void setVolume(double volume0to100) {
    if (_disposed) return;
    final normalized = (volume0to100 / 100.0).clamp(0.0, 1.0);
    _targetVolume = normalized;
    _videoElement.volume = normalized;
    if (normalized == 0.0) {
      _videoElement.muted = true;
    } else {
      _videoElement.muted = false;
      if (_isAutoMuted) {
        _isAutoMuted = false;
        _autoMutedController.add(false);
      }
    }
  }

  @override
  void setRate(double rate) {
    if (_disposed) return;
    _videoElement.playbackRate = rate;
  }

  @override
  void setVideoFit(BoxFit fit) {
    if (_disposed) return;
    switch (fit) {
      case BoxFit.cover:
        _videoElement.style.objectFit = 'cover';
        break;
      case BoxFit.fill:
        _videoElement.style.objectFit = 'fill';
        break;
      default:
        _videoElement.style.objectFit = 'contain';
        break;
    }
  }

  @override
  void setAudioTrack(mpv.AudioTrack track) {
    if (_disposed || _hlsInstance == null) return;
    final idx = int.tryParse(track.id);
    if (idx != null && idx >= 0) {
      try {
        js_util.setProperty(_hlsInstance!, 'audioTrack', idx);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ValkeryWebHls] setAudioTrack error: $e');
        }
      }
    }
  }

  @override
  Future<void> setSubtitleTrack(mpv.SubtitleTrack track, {String? serverBaseUrl}) async {
    if (_disposed) return;
    final gen = ++_subtitleLoadGeneration;

    _parsedCues = [];
    _currentSubtitleCueText = null;
    if (!_disposed) _subtitleCueTextController.add(null);

    if (track.id == 'no') {
      return;
    }

    final urlsToTry = <String>[];

    // 1. Embedded HLS subtitle track (`hls_sub_<index>` -> `/hlsv2/<session>/sub<index>.vtt`)
    if (track.id.startsWith('hls_sub_') && _currentUrl != null) {
      final idx = int.tryParse(track.id.substring('hls_sub_'.length));
      if (idx != null && idx >= 0) {
        final baseHlsDir = _currentUrl!.split('?').first.replaceAll(RegExp(r'/[^/]+$'), '');
        urlsToTry.add('$baseHlsDir/sub$idx.vtt');
      }
    }

    // 2. External URI subtitle track (OpenSubtitles / Addons)
    if (track.id.startsWith('http://') || track.id.startsWith('https://')) {
      final rawUrl = track.id;
      if (serverBaseUrl != null && serverBaseUrl.isNotEmpty) {
        final base = serverBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
        urlsToTry.add('$base/subtitles.vtt?from=${Uri.encodeComponent(rawUrl)}');
      }
      urlsToTry.add(rawUrl);
    }

    for (final fetchUrl in urlsToTry) {
      try {
        final res = await http.get(Uri.parse(fetchUrl)).timeout(const Duration(seconds: 25));
        if (_disposed || gen != _subtitleLoadGeneration) return;
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final content = utf8.decode(res.bodyBytes, allowMalformed: true);
          final cues = _parseSubtitlesToCues(content);
          if (cues.isNotEmpty) {
            _parsedCues = cues;
            final curSec = _videoElement.currentTime;
            if (!curSec.isNaN && !curSec.isInfinite) {
              _updateActiveSubtitleCue(curSec);
            }
            if (kDebugMode) {
              debugPrint('[ValkeryWebHls] Loaded ${cues.length} subtitle cues from $fetchUrl');
            }
            return;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ValkeryWebHls] Subtitle fetch failed ($fetchUrl): $e');
        }
      }
    }
  }

  /// Parses SRT or WebVTT text into a sorted list of [_SubtitleCue]s.
  List<_SubtitleCue> _parseSubtitlesToCues(String rawText) {
    final normalized = rawText
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) return const [];

    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <_SubtitleCue>[];

    // Matches `00:01:23.456 --> 00:01:25.789` or `01:23,456 --> 01:25,789`
    final timeLineRegex = RegExp(
      r'(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{1,3})\s*-->\s*(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{1,3})',
    );

    for (final block in blocks) {
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;

      int timeLineIdx = -1;
      RegExpMatch? match;
      for (int i = 0; i < lines.length; i++) {
        final m = timeLineRegex.firstMatch(lines[i]);
        if (m != null) {
          timeLineIdx = i;
          match = m;
          break;
        }
      }

      if (timeLineIdx == -1 || match == null || timeLineIdx + 1 >= lines.length) {
        continue;
      }

      final startSec = _parseTimestampGroups(
        match.group(1),
        match.group(2)!,
        match.group(3)!,
        match.group(4)!,
      );
      final endSec = _parseTimestampGroups(
        match.group(5),
        match.group(6)!,
        match.group(7)!,
        match.group(8)!,
      );

      final textLines = lines
          .sublist(timeLineIdx + 1)
          .map(_cleanSubtitleTags)
          .where((l) => l.isNotEmpty)
          .toList();

      if (textLines.isNotEmpty && endSec > startSec) {
        cues.add(
          _SubtitleCue(
            startSeconds: startSec,
            endSeconds: endSec,
            text: textLines.join('\n'),
          ),
        );
      }
    }

    return cues;
  }

  double _parseTimestampGroups(String? hStr, String mStr, String sStr, String msStr) {
    final h = hStr != null ? (int.tryParse(hStr) ?? 0) : 0;
    final m = int.tryParse(mStr) ?? 0;
    final s = int.tryParse(sStr) ?? 0;
    final msPadded = msStr.padRight(3, '0').substring(0, 3);
    final ms = int.tryParse(msPadded) ?? 0;
    return h * 3600.0 + m * 60.0 + s + (ms / 1000.0);
  }

  String _cleanSubtitleTags(String line) {
    return line
        .replaceAll(RegExp(r'<[^>]*>'), '') // Strip <i>, <b>, <font>, <c.vtt>
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '') // Strip ASS/SSA override tags {\an8}
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  @override
  Widget buildVideoWidget({required BoxFit fit}) {
    setVideoFit(fit);
    return IgnorePointer(
      ignoring: true,
      child: HtmlElementView(viewType: _viewType),
    );
  }

  void _destroyHls() {
    if (_hlsInstance != null) {
      try {
        js_util.callMethod(_hlsInstance!, 'destroy', const []);
      } catch (_) {}
      _hlsInstance = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _domSubscriptions) {
      sub.cancel();
    }
    _domSubscriptions.clear();
    _parsedCues = [];
    _destroyHls();
    try {
      _videoElement.pause();
      _videoElement.removeAttribute('src');
      _videoElement.load();
      _videoElement.remove();
    } catch (_) {}
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _bufferController.close();
    _completedController.close();
    _errorController.close();
    _audioTracksController.close();
    _subtitleTracksController.close();
    _autoMutedController.close();
    _subtitleCueTextController.close();
  }

  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<Duration> get bufferStream => _bufferController.stream;
  @override
  Stream<bool> get completedStream => _completedController.stream;
  @override
  Stream<String> get errorStream => _errorController.stream;
  @override
  Stream<List<mpv.AudioTrack>> get audioTracksStream => _audioTracksController.stream;
  @override
  Stream<List<mpv.SubtitleTrack>> get subtitleTracksStream => _subtitleTracksController.stream;
  @override
  Stream<bool> get autoMutedStream => _autoMutedController.stream;
  @override
  Stream<String?> get subtitleCueTextStream => _subtitleCueTextController.stream;

  @override
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  Duration get buffer => _buffer;
  @override
  bool get isAutoMuted => _isAutoMuted;
  @override
  String? get currentSubtitleCueText => _currentSubtitleCueText;
}
