import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

class ExternalPlayerLauncher {
  static Future<bool> openInVlc(String streamUrl) async {
    if (kIsWeb) {
      try {
        // 1. Copy URL to clipboard for manual paste in VLC (Media > Open Network Stream)
        await Clipboard.setData(ClipboardData(text: streamUrl));

        // 2. Generate and trigger download of an M3U playlist file
        final m3uContent = '#EXTM3U\n#EXTINF:-1,Valkery Stream\n$streamUrl\n';
        final blob = html.Blob([utf8.encode(m3uContent)], 'audio/x-mpegurl');
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: blobUrl)
          ..setAttribute('download', 'valkery_stream.m3u')
          ..click();
        html.Url.revokeObjectUrl(blobUrl);

        // 3. Try to open via custom VLC protocol scheme
        try {
          final vlcUri = Uri.parse('vlc://$streamUrl');
          await launchUrl(vlcUri, mode: LaunchMode.externalApplication);
        } catch (_) {}

        return true;
      } catch (_) {
        return false;
      }
    }

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
