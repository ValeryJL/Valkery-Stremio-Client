import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/models/settings/arguments_model.dart';
import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/util/string_extensions.dart';

extension WindowHelperSetup on WindowManager {
  Future<void> setupFladderWindowChrome(
    ArgumentsModel startupArguments,
    ClientSettingsModel clientSettings,
    PackageInfo packageInfo,
  ) async {
    final isFullScreen = await windowManager.isFullScreen();
    final isMacDebug = defaultTargetPlatform == TargetPlatform.macOS && kDebugMode;
    final shouldResizeAndShow = !isMacDebug || !isFullScreen;

    final options = WindowOptions(
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: packageInfo.appName.capitalize(),
    );

    Future<void> applyWindowState() async {
      try {
        if (shouldResizeAndShow) {
          await windowManager.setSize(Size(clientSettings.size.x, clientSettings.size.y));
          await windowManager.center();
          await windowManager.show();
          await windowManager.focus();
        }

        if (startupArguments.htpcMode && !isFullScreen) {
          await windowManager.setFullScreen(true);
        }
      } catch (e) {
        debugPrint('Error applying window state: $e');
      }
    }

    if (isMacDebug) {
      try {
        await windowManager.setBackgroundColor(options.backgroundColor!);
        await windowManager.setSkipTaskbar(options.skipTaskbar ?? false);
        await windowManager.setTitleBarStyle(options.titleBarStyle!);
        await windowManager.setTitle(options.title ?? packageInfo.appName.capitalize());
      } catch (_) {}
      await applyWindowState();
    } else {
      try {
        await windowManager.waitUntilReadyToShow(options, applyWindowState);
      } catch (_) {
        await applyWindowState();
      }
    }
  }
}
