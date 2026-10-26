import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/bootstrap/platform/platform_app_wrapper.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/localization_delegates.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/crash_log_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/stremio_providers.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/screens/stremio/valkery_main_shell.dart';
import 'package:fladder/services/stremio/stremio_storage_service.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/deep_link_helper.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/themes_data.dart';
import 'package:fladder/widgets/media_query_scaler.dart';
import 'package:fladder/widgets/pip_lifecycle_controller.dart';
import 'package:fladder/widgets/shared/adaptive_color.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final bootstrap = await bootstrapApplication(args);

  final storagePath = bootstrap.applicationDirectory.path.isNotEmpty
      ? p.join(bootstrap.applicationDirectory.path, 'valkery_stremio_state.json')
      : null;
  final stremioStorage = StremioStorageService(customFilePath: storagePath);
  await stremioStorage.init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => bootstrap.sharedPreferences),
        applicationInfoProvider.overrideWith((ref) => bootstrap.applicationInfo),
        crashLogProvider.overrideWith((ref) => bootstrap.crashProvider),
        argumentsStateProvider.overrideWith((ref) => bootstrap.argumentsModel),
        syncProvider.overrideWith((ref) => SyncNotifier(ref, bootstrap.applicationDirectory)),
        stremioStorageProvider.overrideWith((ref) => stremioStorage),
      ],
      child: AdaptiveLayoutBuilder(
        child: (context) => const Main(),
      ),
    ),
  );
}

class Main extends ConsumerWidget {
  const Main({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformAppWrapper(
      builder: (context, autoRouter) {
        return _FladderApp(
          autoRouter: autoRouter,
        );
      },
    );
  }
}

class _FladderApp extends ConsumerWidget {
  const _FladderApp({
    required this.autoRouter,
  });

  final AutoRouter autoRouter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(clientSettingsProvider.select((value) => value.themeMode));
    final amoledBlack = ref.watch(clientSettingsProvider.select((value) => value.amoledBlack));
    final mouseDrag = ref.watch(clientSettingsProvider.select((value) => value.mouseDragSupport));
    final language = ref.watch(clientSettingsProvider
        .select((value) => value.selectedLocale ?? WidgetsBinding.instance.platformDispatcher.locale));
    final scrollBehaviour = const MaterialScrollBehavior();
    final amoledOverwrite = amoledBlack ? Colors.black : null;

    return AdaptiveColor(
      child: (darkTheme, lightTheme) => ThemesData(
        light: lightTheme,
        dark: darkTheme,
        child: MaterialApp(
          title: 'Valkery',
          debugShowCheckedModeBanner: false,
          theme: darkTheme.copyWith(
            scaffoldBackgroundColor: amoledOverwrite ?? const Color(0xFF0F0E17),
            cardColor: amoledOverwrite ?? const Color(0xFF16152B),
            canvasColor: amoledOverwrite ?? const Color(0xFF0F0E17),
            colorScheme: darkTheme.colorScheme.copyWith(
              surface: amoledOverwrite ?? const Color(0xFF141326),
              surfaceContainerHighest: amoledOverwrite ?? const Color(0xFF1E1D38),
              surfaceContainerLow: amoledOverwrite ?? const Color(0xFF0F0E17),
            ),
          ),
          darkTheme: darkTheme.copyWith(
            scaffoldBackgroundColor: amoledOverwrite ?? const Color(0xFF0F0E17),
            cardColor: amoledOverwrite ?? const Color(0xFF16152B),
            canvasColor: amoledOverwrite ?? const Color(0xFF0F0E17),
            colorScheme: darkTheme.colorScheme.copyWith(
              surface: amoledOverwrite ?? const Color(0xFF141326),
              surfaceContainerHighest: amoledOverwrite ?? const Color(0xFF1E1D38),
              surfaceContainerLow: amoledOverwrite ?? const Color(0xFF0F0E17),
            ),
          ),
          themeMode: ThemeMode.dark,
          scrollBehavior: scrollBehaviour.copyWith(
            dragDevices: {
              ...scrollBehaviour.dragDevices,
              mouseDrag ? PointerDeviceKind.mouse : null,
            }.nonNulls.toSet(),
          ),
          localizationsDelegates: FladderLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: language,
          localeResolutionCallback: (locale, supportedLocales) {
            const fallback = Locale('en');
            if (locale == null) return fallback;
            if (supportedLocales.contains(locale)) {
              return locale;
            }
            final matchByLanguage = supportedLocales.firstWhere(
              (l) => l.languageCode == locale.languageCode,
              orElse: () => fallback,
            );

            return matchByLanguage;
          },
          builder: (context, child) => MediaQueryScaler(
            child: LocalizationContextWrapper(
              child: PipLifecycleController(child: child ?? const SizedBox.shrink()),
              currentLocale: language,
            ),
            enable: ref.read(argumentsStateProvider).leanBackMode,
          ),
          home: const ValkeryMainShell(),
        ),
      ),
    );
  }
}
