import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;
import 'package:window_manager/window_manager.dart';

class ValkeryFullscreenHelper {
  bool _mobileImmersive = false;

  bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> toggleFullScreen([dynamic _]) async {
    if (kIsWeb) {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      } else {
        await html.document.documentElement?.requestFullscreen();
      }
      return;
    }

    if (isDesktopPlatform) {
      final isFull = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFull);
      return;
    }

    _mobileImmersive = !_mobileImmersive;
    if (_mobileImmersive) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> closeFullScreen([dynamic _]) async {
    if (kIsWeb) {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }
      return;
    }

    if (isDesktopPlatform) {
      final isFull = await windowManager.isFullScreen();
      if (isFull) {
        await windowManager.setFullScreen(false);
      }
      return;
    }

    if (_mobileImmersive) {
      _mobileImmersive = false;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}

final ValkeryFullscreenHelper fullScreenHelper = ValkeryFullscreenHelper();
