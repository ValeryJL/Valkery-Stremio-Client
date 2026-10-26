import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../providers/source_coordinator_provider.dart';
import 'stremio_discover_screen.dart';
import 'stremio_library_screen.dart';
import 'stremio_offline_screen.dart';
import 'valkery_desktop_title_bar.dart';
import 'valkery_jellyfin_view.dart';
import 'valkery_settings_screen.dart';

class ValkeryMainShell extends ConsumerStatefulWidget {
  const ValkeryMainShell({super.key});

  @override
  ConsumerState<ValkeryMainShell> createState() => _ValkeryMainShellState();
}

class _ValkeryMainShellState extends ConsumerState<ValkeryMainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinator = ref.watch(sourceCoordinatorProvider);
    final isDesktop = MediaQuery.of(context).size.width > 768;
    final isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    final screens = <Widget>[
      const StremioDiscoverScreen(),
      StremioLibraryScreen(
        onExploreCatalog: () => setState(() => _currentIndex = 0),
      ),
      const StremioOfflineScreen(),
      if (coordinator.isJellyfinActive)
        const ValkeryJellyfinView(),
      const ValkerySettingsScreen(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.discover),
        selectedIcon: Icon(IconsaxPlusBold.discover, color: Color(0xFF8B5CF6)),
        label: 'Explorar',
      ),
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.folder_favorite),
        selectedIcon: Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
        label: 'Biblioteca',
      ),
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.document_download),
        selectedIcon: Icon(IconsaxPlusBold.document_download, color: Color(0xFF8B5CF6)),
        label: 'Offline',
      ),
      if (coordinator.isJellyfinActive)
        const NavigationDestination(
          icon: Icon(IconsaxPlusLinear.video_square),
          selectedIcon: Icon(IconsaxPlusBold.video_square, color: Color(0xFF8B5CF6)),
          label: 'Jellyfin',
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
            onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
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
              const NavigationRailDestination(
                icon: Icon(IconsaxPlusLinear.discover),
                selectedIcon: Icon(IconsaxPlusBold.discover, color: Color(0xFF8B5CF6)),
                label: Text('Explorar'),
              ),
              const NavigationRailDestination(
                icon: Icon(IconsaxPlusLinear.folder_favorite),
                selectedIcon:
                    Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
                label: Text('Biblioteca'),
              ),
              const NavigationRailDestination(
                icon: Icon(IconsaxPlusLinear.document_download),
                selectedIcon:
                    Icon(IconsaxPlusBold.document_download, color: Color(0xFF8B5CF6)),
                label: Text('Offline'),
              ),
              if (coordinator.isJellyfinActive)
                const NavigationRailDestination(
                  icon: Icon(IconsaxPlusLinear.video_square),
                  selectedIcon:
                      Icon(IconsaxPlusBold.video_square, color: Color(0xFF8B5CF6)),
                  label: Text('Jellyfin'),
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
                  onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
                  destinations: destinations,
                )
              : null,
        ),
      ),
    );
  }
}
