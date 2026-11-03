import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mpv;
import 'web_hls_bridge.dart';

WebHlsBridge createWebHlsBridge() => _StubWebHlsBridge();

class _StubWebHlsBridge implements WebHlsBridge {
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get bufferStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  Stream<String> get errorStream => const Stream.empty();
  @override
  Stream<List<mpv.AudioTrack>> get audioTracksStream => const Stream.empty();
  @override
  Stream<List<mpv.SubtitleTrack>> get subtitleTracksStream => const Stream.empty();
  @override
  Stream<bool> get autoMutedStream => const Stream.empty();
  @override
  Stream<String?> get subtitleCueTextStream => const Stream.empty();

  @override
  bool get isPlaying => false;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  Duration get buffer => Duration.zero;
  @override
  bool get isAutoMuted => false;
  @override
  String? get currentSubtitleCueText => null;

  @override
  Future<void> open(String hlsUrl, {String? fallbackDirectUrl}) async {}
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void playOrPause() {}
  @override
  void seek(Duration target) {}
  @override
  void setVolume(double volume0to100) {}
  @override
  void setRate(double rate) {}
  @override
  void setVideoFit(BoxFit fit) {}
  @override
  void setAudioTrack(mpv.AudioTrack track) {}
  @override
  void setSubtitleTrack(mpv.SubtitleTrack track, {String? serverBaseUrl}) {}
  @override
  void unmuteFromUserGesture(double volume0to100) {}
  @override
  Widget buildVideoWidget({required BoxFit fit}) => const SizedBox.shrink();
  @override
  void dispose() {}
}
