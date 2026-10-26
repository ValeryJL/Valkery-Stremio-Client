import 'dart:io';
import 'package:flutter/foundation.dart';

class ExternalPlayerLauncher {
  static Future<bool> openInVlc(String streamUrl) async {
    if (kIsWeb) return false;

    if (Platform.isWindows) {
      final candidates = [
        '${Platform.environment['ProgramFiles']}\\VideoLAN\\VLC\\vlc.exe',
        '${Platform.environment['ProgramFiles(x86)']}\\VideoLAN\\VLC\\vlc.exe',
        '${Platform.environment['LOCALAPPDATA']}\\Programs\\VLC\\vlc.exe',
      ];

      for (final p in candidates) {
        if (File(p).existsSync()) {
          try {
            await Process.start(p, [streamUrl], mode: ProcessStartMode.detached);
            return true;
          } catch (_) {}
        }
      }

      // Fallback: system command
      try {
        await Process.start('cmd', ['/c', 'start', 'vlc', streamUrl], mode: ProcessStartMode.detached);
        return true;
      } catch (_) {}

      // Fallback 2: open URL with default system handler
      try {
        await Process.start('cmd', ['/c', 'start', '', streamUrl], mode: ProcessStartMode.detached);
        return true;
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        await Process.start('open', ['-a', 'VLC', streamUrl], mode: ProcessStartMode.detached);
        return true;
      } catch (_) {
        try {
          await Process.start('open', [streamUrl], mode: ProcessStartMode.detached);
          return true;
        } catch (_) {}
      }
    } else if (Platform.isLinux) {
      try {
        await Process.start('vlc', [streamUrl], mode: ProcessStartMode.detached);
        return true;
      } catch (_) {
        try {
          await Process.start('xdg-open', [streamUrl], mode: ProcessStartMode.detached);
          return true;
        } catch (_) {}
      }
    }

    return false;
  }
}
