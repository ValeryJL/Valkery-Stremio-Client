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

  final List<StreamSubscription> _domSubscriptions = [];

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isAutoMuted = false;
  double _targetVolume = 1.0;
  String? _activeSubtitleBlobUrl;

  _RealWebHlsBridge() {
    _viewId = _nextViewId++;
    _viewType = 'com.valkery.stremio.web_hls_video_$_viewId';

    _videoElement = html.VideoElement()
      ..autoplay = true
      ..controls = false
      ..muted = false
      ..crossOrigin = 'anonymous'
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true')
      ..setAttribute('preload', 'auto')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000000'
      ..style.border = 'none'
      ..style.outline = 'none'
      ..style.display = 'block';

    _containerElement = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#000000'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
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
      }
      _updateBuffer();
    }));

    _domSubscriptions.add(_videoElement.onProgress.listen((_) {
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
          // Browser blocked unmuted autoplay because async torrent preparation exceeded transient activation.
          // Start playing muted immediately so video frames render, and show unmute indicator!
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
    final config = js_util.jsify({
      'enableWorker': true,
      'lowLatencyMode': false,
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

    // Immediately disable automatic subtitle track extraction on initial load so rivulet-engine
    // doesn't spawn an expensive full-file subtitle demux while seg0.ts is transcoding.
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

        // If bufferStalledError or bufferSeekOverHole, jump the PTS hole
        if (details == 'bufferStalledError' || details == 'bufferSeekOverHole' || details == 'bufferNudgeOnStall') {
          _jumpInitialPtsGapIfNeeded();
        }

        if (!isFatal) return;

        if (type == 'networkError') {
          if (_networkErrorRetries < 6) {
            _networkErrorRetries++;
            if (kDebugMode) {
              debugPrint('[ValkeryWebHls] Recovering fatal networkError (attempt $_networkErrorRetries)...');
            }
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (_disposed || _hlsInstance == null) return;
              try {
                // If manifest failed or session expired, reload source
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
            if (kDebugMode) {
              debugPrint('[ValkeryWebHls] Recovering fatal mediaError (attempt $_mediaErrorRetries)...');
            }
            try {
              if (_mediaErrorRetries == 2) {
                js_util.callMethod(hls, 'swapAudioCodec', const []);
              }
              js_util.callMethod(hls, 'recoverMediaError', const []);
              return;
            } catch (_) {}
          }
        }

        // If HLS completely failed and we have a direct URL fallback, try direct HTML5 playback
        if (!_triedDirectFallback && _fallbackDirectUrl != null && _fallbackDirectUrl != url) {
          _triedDirectFallback = true;
          if (kDebugMode) {
            debugPrint('[ValkeryWebHls] HLS exhausted retries; trying direct fallback: $_fallbackDirectUrl');
          }
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
      final rawList = js_util.getProperty<List<dynamic>?>(hls, 'subtitleTracks');
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
      // Fallback if still restricted
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
    _videoElement.currentTime = sec < 0 ? 0 : sec;
    _position = target;
    _positionController.add(target);
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

    // Clear existing <track> elements
    _clearDomSubtitleTracks();

    if (track.id == 'no') {
      if (_hlsInstance != null) {
        try {
          js_util.setProperty(_hlsInstance!, 'subtitleTrack', -1);
          js_util.setProperty(_hlsInstance!, 'subtitleDisplay', false);
        } catch (_) {}
      }
      return;
    }

    // Embedded HLS subtitle track
    if (track.id.startsWith('hls_sub_') && _hlsInstance != null) {
      final idx = int.tryParse(track.id.substring('hls_sub_'.length));
      if (idx != null && idx >= 0) {
        try {
          js_util.setProperty(_hlsInstance!, 'subtitleDisplay', true);
          js_util.setProperty(_hlsInstance!, 'subtitleTrack', idx);
        } catch (_) {}
      }
      return;
    }

    // External URI subtitle track (SRT or VTT from OpenSubtitles / Addons)
    final rawUrl = track.id;
    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) return;

    try {
      String fetchUrl = rawUrl;
      // Use rivulet-engine's /subtitles.vtt?from=... converter if available
      if (serverBaseUrl != null && serverBaseUrl.isNotEmpty) {
        final base = serverBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
        fetchUrl = '$base/subtitles.vtt?from=${Uri.encodeComponent(rawUrl)}';
      }

      String content = '';
      try {
        final res = await http.get(Uri.parse(fetchUrl)).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          content = utf8.decode(res.bodyBytes, allowMalformed: true);
        }
      } catch (_) {}

      if (content.isEmpty) {
        final res = await http.get(Uri.parse(rawUrl)).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          content = utf8.decode(res.bodyBytes, allowMalformed: true);
        }
      }

      if (content.isEmpty || _disposed) return;

      final vttContent = _ensureWebVttFormat(content);
      final blob = html.Blob([utf8.encode(vttContent)], 'text/vtt');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      _activeSubtitleBlobUrl = blobUrl;

      final trackEl = html.TrackElement()
        ..kind = 'subtitles'
        ..label = track.title ?? track.language ?? 'Subtítulos'
        ..srclang = track.language ?? 'es'
        ..src = blobUrl
        ..defaultValue = true;

      _videoElement.append(trackEl);

      // Force textTrack mode = 'showing'
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_disposed) return;
        try {
          final textTracks = _videoElement.textTracks;
          if (textTracks != null) {
            for (int i = 0; i < textTracks.length; i++) {
              final tt = textTracks[i];
              tt.mode = (i == textTracks.length - 1) ? 'showing' : 'disabled';
            }
          }
        } catch (_) {}
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ValkeryWebHls] Failed to load external subtitle: $e');
      }
    }
  }

  void _clearDomSubtitleTracks() {
    try {
      final textTracks = _videoElement.textTracks;
      if (textTracks != null) {
        for (int i = 0; i < textTracks.length; i++) {
          textTracks[i].mode = 'disabled';
        }
      }
      final children = _videoElement.children.whereType<html.TrackElement>().toList();
      for (final child in children) {
        child.remove();
      }
      if (_activeSubtitleBlobUrl != null) {
        html.Url.revokeObjectUrl(_activeSubtitleBlobUrl!);
        _activeSubtitleBlobUrl = null;
      }
    } catch (_) {}
  }

  /// Converts SRT subtitle text to valid WebVTT if it is not already WebVTT
  String _ensureWebVttFormat(String input) {
    final trimmed = input.trimLeft();
    if (trimmed.startsWith('WEBVTT')) return trimmed;

    final normalized = trimmed.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Convert SRT timestamps `00:01:23,456 --> 00:01:25,789` to WebVTT `00:01:23.456 --> 00:01:25.789`
    final vttBody = normalized.replaceAllMapped(
      RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}),(\d{3})'),
      (m) => '${m[1]}.${m[2]} --> ${m[3]}.${m[4]}',
    );
    return 'WEBVTT\n\n$vttBody\n';
  }

  @override
  Widget buildVideoWidget({required BoxFit fit}) {
    setVideoFit(fit);
    return HtmlElementView(viewType: _viewType);
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
    _clearDomSubtitleTracks();
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
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  Duration get buffer => _buffer;
  @override
  bool get isAutoMuted => _isAutoMuted;
}
