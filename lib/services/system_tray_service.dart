import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'stremio/stremio_server_process_manager.dart';

class SystemTrayService with TrayListener {
  static final SystemTrayService instance = SystemTrayService._();
  SystemTrayService._();

  StremioServerProcessManager? _processManager;
  bool _isInitialized = false;

  Future<void> init(StremioServerProcessManager processManager) async {
    _processManager = processManager;
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) return;
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      trayManager.addListener(this);
      final iconPath = Platform.isWindows
          ? 'assets/icons/valkery_icon.ico'
          : 'assets/icons/valkery_icon.png';
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Valkery Stremio Client');
      await _updateContextMenu();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SystemTrayService] Failed to initialize system tray: $e');
      }
    }
  }

  Future<void> _updateContextMenu() async {
    try {
      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_valkery',
            label: 'Mostrar Valkery',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: 'Salir (Cerrar Valkery y Stream Service)',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SystemTrayService] Failed to set context menu: $e');
      }
    }
  }

  @override
  void onTrayIconMouseDown() {
    _showApp();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_valkery') {
      _showApp();
    } else if (menuItem.key == 'exit_app') {
      await exitApp();
    }
  }

  Future<void> _showApp() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  /// Detiene completamente el motor local stream-server y finaliza el proceso de Valkery.
  Future<void> exitApp() async {
    try {
      await _processManager?.stopLocalServer();
    } catch (_) {}
    exit(0);
  }

  void dispose() {
    if (_isInitialized) {
      trayManager.removeListener(this);
      _isInitialized = false;
    }
  }
}
