import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:window_manager/window_manager.dart';

class ValkeryDesktopTitleBar extends StatefulWidget {
  final String title;

  const ValkeryDesktopTitleBar({
    super.key,
    this.title = 'Valkery',
  });

  @override
  State<ValkeryDesktopTitleBar> createState() => _ValkeryDesktopTitleBarState();
}

class _ValkeryDesktopTitleBarState extends State<ValkeryDesktopTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.addListener(this);
      _checkWindowState();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _checkWindowState() async {
    final max = await windowManager.isMaximized();
    final fs = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {
        _isMaximized = max;
        _isFullScreen = fs;
      });
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Drag to move area spanning the title and center
          Expanded(
            child: GestureDetector(
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: DragToMoveArea(
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/icons/valkery_icon.png',
                        height: 18,
                        width: 18,
                        errorBuilder: (_, __, ___) => const Icon(
                          IconsaxPlusBold.video_play,
                          color: Color(0xFF8B5CF6),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: iconColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Window action buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Full Screen Toggle Button
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                splashRadius: 18,
                tooltip: _isFullScreen ? 'Salir de pantalla completa (F11)' : 'Pantalla completa (F11)',
                icon: Icon(
                  _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  size: 20,
                  color: iconColor,
                ),
                onPressed: () async {
                  final isFs = await windowManager.isFullScreen();
                  await windowManager.setFullScreen(!isFs);
                },
              ),
              // Minimize
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                splashRadius: 18,
                tooltip: 'Minimizar',
                icon: Icon(
                  Icons.minimize_rounded,
                  size: 18,
                  color: iconColor,
                ),
                onPressed: () => windowManager.minimize(),
              ),
              // Maximize / Restore
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                splashRadius: 18,
                tooltip: _isMaximized ? 'Restaurar' : 'Maximizar',
                icon: Icon(
                  _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
                  size: 16,
                  color: iconColor,
                ),
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
              ),
              // Close
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                splashRadius: 18,
                tooltip: 'Cerrar',
                style: IconButton.styleFrom(
                  hoverColor: Colors.red.withValues(alpha: 0.8),
                ),
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: iconColor,
                ),
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
