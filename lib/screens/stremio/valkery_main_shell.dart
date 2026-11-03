import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../providers/stremio_providers.dart';
import '../../services/system_tray_service.dart';
import 'stremio_discover_screen.dart';
import 'stremio_library_screen.dart';
import 'stremio_offline_screen.dart';
import 'valkery_desktop_title_bar.dart';
import 'valkery_settings_screen.dart';

class ValkeryMainShell extends ConsumerStatefulWidget {
  const ValkeryMainShell({super.key});

  @override
  ConsumerState<ValkeryMainShell> createState() => _ValkeryMainShellState();
}

class _ValkeryMainShellState extends ConsumerState<ValkeryMainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pm = ref.read(stremioServerProcessManagerProvider);
      SystemTrayService.instance.init(pm);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOfflineMode = ref.watch(stremioOfflineModeProvider);
    final pendingSyncCount = ref.watch(stremioPendingOfflineSyncProvider).length;
    final isDesktop = MediaQuery.of(context).size.width > 768;
    final isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    // If offline mode is active and user is on Explorar, redirect to Biblioteca
    if (isOfflineMode && _currentIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentIndex == 0) {
          setState(() => _currentIndex = 1);
        }
      });
    }

    void handleDestinationSelected(int idx) {
      if (idx == 0 && isOfflineMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(IconsaxPlusLinear.info_circle, color: Colors.amberAccent, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Modo Offline activo: La pestaña Explorar requiere internet.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1F1D36),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      setState(() => _currentIndex = idx);
    }

    final screens = <Widget>[
      const StremioDiscoverScreen(),
      StremioLibraryScreen(
        onExploreCatalog: isOfflineMode ? null : () => setState(() => _currentIndex = 0),
      ),
      if (!kIsWeb)
        const StremioOfflineScreen(),
      const ValkerySettingsScreen(),
    ];

    final offlineIcon = pendingSyncCount > 0
        ? Badge(
            label: Text('$pendingSyncCount'),
            backgroundColor: Colors.amber.shade700,
            textColor: Colors.white,
            child: const Icon(IconsaxPlusLinear.document_download),
          )
        : const Icon(IconsaxPlusLinear.document_download);

    final offlineSelectedIcon = pendingSyncCount > 0
        ? Badge(
            label: Text('$pendingSyncCount'),
            backgroundColor: Colors.amber.shade700,
            textColor: Colors.white,
            child: const Icon(IconsaxPlusBold.document_download, color: Color(0xFF8B5CF6)),
          )
        : const Icon(IconsaxPlusBold.document_download, color: Color(0xFF8B5CF6));

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: Icon(
          IconsaxPlusLinear.discover,
          color: isOfflineMode ? Colors.white30 : null,
        ),
        selectedIcon: Icon(
          IconsaxPlusBold.discover,
          color: isOfflineMode ? Colors.white30 : const Color(0xFF8B5CF6),
        ),
        label: isOfflineMode ? 'Explorar (Off)' : 'Explorar',
      ),
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.folder_favorite),
        selectedIcon: Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
        label: 'Biblioteca',
      ),
      if (!kIsWeb)
        NavigationDestination(
          icon: offlineIcon,
          selectedIcon: offlineSelectedIcon,
          label: 'Offline',
        ),
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.setting_2),
        selectedIcon: Icon(IconsaxPlusBold.setting_2, color: Color(0xFF8B5CF6)),
        label: 'Ajustes',
      ),
    ];

    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    Widget shellContent;
    if (isDesktop) {
      shellContent = Row(
        children: [
          NavigationRail(
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.6),
            selectedIndex: safeIndex,
            onDestinationSelected: handleDestinationSelected,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Image.asset(
                'assets/icons/valkery_icon.png',
                width: 36,
                height: 36,
                errorBuilder: (_, __, ___) => const Icon(
                  IconsaxPlusBold.video_play,
                  color: Color(0xFF8B5CF6),
                  size: 32,
                ),
              ),
            ),
            destinations: [
              NavigationRailDestination(
                icon: Icon(
                  IconsaxPlusLinear.discover,
                  color: isOfflineMode ? Colors.white30 : null,
                ),
                selectedIcon: Icon(
                  IconsaxPlusBold.discover,
                  color: isOfflineMode ? Colors.white30 : const Color(0xFF8B5CF6),
                ),
                label: Text(
                  'Explorar',
                  style: TextStyle(color: isOfflineMode ? Colors.white30 : null),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(IconsaxPlusLinear.folder_favorite),
                selectedIcon:
                    Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
                label: Text('Biblioteca'),
              ),
              if (!kIsWeb)
                NavigationRailDestination(
                  icon: offlineIcon,
                  selectedIcon: offlineSelectedIcon,
                  label: const Text('Offline'),
                ),
              const NavigationRailDestination(
                icon: Icon(IconsaxPlusLinear.setting_2),
                selectedIcon:
                    Icon(IconsaxPlusBold.setting_2, color: Color(0xFF8B5CF6)),
                label: Text('Ajustes'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: safeIndex,
              children: screens,
            ),
          ),
        ],
      );
    } else {
      shellContent = IndexedStack(
        index: safeIndex,
        children: screens,
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): () async {
          if (isDesktopPlatform) {
            final isFs = await windowManager.isFullScreen();
            await windowManager.setFullScreen(!isFs);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF0F0E17),
          body: SafeArea(
            top: !isDesktopPlatform,
            bottom: false,
            child: Column(
              children: [
                if (isDesktopPlatform) const ValkeryDesktopTitleBar(),
                Expanded(child: shellContent),
              ],
            ),
          ),
          bottomNavigationBar: !isDesktop
              ? NavigationBar(
                  backgroundColor: const Color(0xFF141326),
                  indicatorColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                  selectedIndex: safeIndex,
                  onDestinationSelected: handleDestinationSelected,
                  destinations: destinations,
                )
              : null,
        ),
      ),
    );
  }
}
