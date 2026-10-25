import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../providers/source_coordinator_provider.dart';
import 'stremio_discover_screen.dart';
import 'stremio_offline_screen.dart';
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

    final screens = <Widget>[
      const StremioDiscoverScreen(),
      const StremioOfflineScreen(),
      if (coordinator.isJellyfinActive)
        const ValkeryJellyfinView(),
      const ValkerySettingsScreen(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.discover),
        selectedIcon: Icon(IconsaxPlusBold.discover, color: Color(0xFF8B5CF6)),
        label: 'Stremio',
      ),
      const NavigationDestination(
        icon: Icon(IconsaxPlusLinear.folder_favorite),
        selectedIcon: Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
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

    if (isDesktop) {
      return Scaffold(
        body: Row(
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
                  label: Text('Stremio'),
                ),
                const NavigationRailDestination(
                  icon: Icon(IconsaxPlusLinear.folder_favorite),
                  selectedIcon:
                      Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
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
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
        selectedIndex: safeIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: destinations,
      ),
    );
  }
}
