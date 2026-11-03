import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mpv;

import 'web_hls_bridge_stub.dart'
    if (dart.library.html) 'web_hls_bridge_web.dart';

abstract class WebHlsBridge {
  factory WebHlsBridge() => createWebHlsBridge();

  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;
  Stream<List<mpv.AudioTrack>> get audioTracksStream;
  Stream<List<mpv.SubtitleTrack>> get subtitleTracksStream;
  Stream<bool> get autoMutedStream;

  bool get isPlaying;
  Duration get position;
  Duration get duration;
  Duration get buffer;
  bool get isAutoMuted;

  Future<void> open(String hlsUrl, {String? fallbackDirectUrl});
  void play();
  void pause();
  void playOrPause();
  void seek(Duration target);
  void setVolume(double volume0to100);
  void setRate(double rate);
  void setVideoFit(BoxFit fit);
  void setAudioTrack(mpv.AudioTrack track);
  void setSubtitleTrack(mpv.SubtitleTrack track, {String? serverBaseUrl});
  void unmuteFromUserGesture(double volume0to100);
  Widget buildVideoWidget({required BoxFit fit});
  void dispose();
}
