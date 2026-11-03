import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/stremio_providers.dart';
import 'screens/stremio/valkery_main_shell.dart';
import 'services/stremio/stremio_storage_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        minimumSize: Size(800, 560),
        center: true,
        backgroundColor: Color(0xFF0F0E17),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'Valkery',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {}
  }

  String? storagePath;
  if (!kIsWeb) {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (appDir.path.isNotEmpty) {
        storagePath = p.join(appDir.path, 'valkery_stremio_state.json');
      }
    } catch (_) {}
  }

  final stremioStorage = StremioStorageService(customFilePath: storagePath);
  await stremioStorage.init();

  runApp(
    ProviderScope(
      overrides: [
        stremioStorageProvider.overrideWith((ref) => stremioStorage),
      ],
      child: const ValkeryApp(),
    ),
  );
}

class ValkeryApp extends StatelessWidget {
  const ValkeryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const baseDark = Color(0xFF0F0E17);
    const cardDark = Color(0xFF16152B);
    const surfaceDark = Color(0xFF141326);
    const accentPurple = Color(0xFF8B5CF6);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentPurple,
      brightness: Brightness.dark,
      primary: accentPurple,
      surface: surfaceDark,
      surfaceContainerHighest: const Color(0xFF1E1D38),
      surfaceContainerLow: baseDark,
    );

    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: baseDark,
      cardColor: cardDark,
      canvasColor: baseDark,
    );

    return MaterialApp(
      title: 'Valkery',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      home: const ValkeryMainShell(),
    );
  }
}
