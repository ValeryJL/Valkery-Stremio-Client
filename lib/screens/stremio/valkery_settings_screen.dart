import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/stremio_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/source_coordinator_provider.dart';
import '../../providers/stremio_providers.dart';
import '../../providers/user_provider.dart';

class ValkerySettingsScreen extends ConsumerStatefulWidget {
  const ValkerySettingsScreen({super.key});

  @override
  ConsumerState<ValkerySettingsScreen> createState() => _ValkerySettingsScreenState();
}

class _ValkerySettingsScreenState extends ConsumerState<ValkerySettingsScreen> {
  late final TextEditingController _stremioServerController;
  late final TextEditingController _jellyfinServerController;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _authKeyController = TextEditingController();
  final TextEditingController _addonUrlController = TextEditingController();

  int _stremioAuthTab = 0; // 0: Login, 1: Register, 2: AuthKey
  bool _isLoggingIn = false;
  bool _isInstallingAddon = false;
  bool _isTestingJellyfin = false;
  String? _jellyfinError;

  @override
  void initState() {
    super.initState();
    final coordinator = ref.read(sourceCoordinatorProvider);
    _stremioServerController = TextEditingController(text: coordinator.stremioServerUrl);
    _jellyfinServerController = TextEditingController(text: coordinator.jellyfinServerUrl);
  }

  @override
  void dispose() {
    _stremioServerController.dispose();
    _jellyfinServerController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _authKeyController.dispose();
    _addonUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleStremioAuth() async {
    setState(() => _isLoggingIn = true);
    final api = ref.read(stremioApiServiceProvider);

    try {
      if (_stremioAuthTab == 0) {
        // Login
        if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
          throw 'Ingresa tu correo y contraseña';
        }
        await api.login(_emailController.text.trim(), _passwordController.text);
      } else if (_stremioAuthTab == 1) {
        // Register
        if (_emailController.text.trim().isEmpty || _passwordController.text.length < 5) {
          throw 'Ingresa un correo válido y una contraseña de al menos 5 caracteres';
        }
        await api.register(_emailController.text.trim(), _passwordController.text);
      } else {
        // AuthKey
        final key = _authKeyController.text.trim();
        if (key.isEmpty) throw 'Ingresa un AuthKey de Stremio válido';
        await api.getUser(key);
        await api.syncAccountData();
      }

      ref.invalidate(stremioWatchHistoryProvider);
      ref.invalidate(stremioTopMoviesProvider);
      ref.invalidate(stremioTopSeriesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesión de Stremio iniciada con éxito'),
            backgroundColor: Color(0xFF8B5CF6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _showInstallAddonDialog() async {
    _addonUrlController.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Instalar Addon de Stremio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pega la URL del manifest del addon (ej: https://torrentio.strem.fun/manifest.json):',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addonUrlController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            onPressed: () => Navigator.of(dialogCtx).pop(_addonUrlController.text.trim()),
            child: const Text('Instalar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isInstallingAddon = true);
      try {
        final api = ref.read(stremioApiServiceProvider);
        final addon = await api.installAddonFromManifestUrl(result);
        ref.invalidate(stremioTopMoviesProvider);
        ref.invalidate(stremioTopSeriesProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Addon instalado: ${addon.name}'),
              backgroundColor: const Color(0xFF8B5CF6),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al instalar addon: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isInstallingAddon = false);
      }
    }
  }

  Future<void> _testAndConnectJellyfin() async {
    final raw = _jellyfinServerController.text.trim();
    if (raw.isEmpty) {
      setState(() => _jellyfinError = 'Ingresa la URL del servidor Jellyfin');
      return;
    }

    var url = raw;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');

    setState(() {
      _isTestingJellyfin = true;
      _jellyfinError = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$url/System/Info/Public'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverName = (data is Map<String, dynamic>)
            ? data['ServerName']?.toString() ?? 'Jellyfin Server'
            : 'Jellyfin Server';
        final version = (data is Map<String, dynamic>)
            ? data['Version']?.toString() ?? ''
            : '';

        await ref.read(sourceCoordinatorProvider.notifier).setJellyfinServer(
          url: url,
          serverName: serverName,
          version: version,
        );

        await ref.read(authProvider.notifier).setServer(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Servidor conectado: $serverName ($version)'),
              backgroundColor: const Color(0xFF8B5CF6),
            ),
          );
        }
      } else {
        setState(() {
          _jellyfinError = 'El servidor respondió con código ${response.statusCode}';
        });
      }
    } catch (_) {
      setState(() {
        _jellyfinError = 'No se pudo conectar al servidor. Revisa la URL y que esté accesible.';
      });
    } finally {
      if (mounted) {
        setState(() => _isTestingJellyfin = false);
      }
    }
  }

  Future<void> _disconnectJellyfin() async {
    await ref.read(sourceCoordinatorProvider.notifier).disconnectJellyfin();
    await ref.read(authProvider.notifier).logOutUser();
    _jellyfinServerController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servidor Jellyfin desconectado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinator = ref.watch(sourceCoordinatorProvider);
    final serverStatusAsync = ref.watch(stremioServerStatusStreamProvider);
    final storage = ref.watch(stremioStorageProvider);
    final isServerOnline = serverStatusAsync.value?.isOnline ?? false;
    final currentUser = storage.currentUser;
    final jellyfinUser = ref.watch(userProvider);
    final addons = storage.addons;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.75),
        elevation: 0,
        title: const Row(
          children: [
            Icon(IconsaxPlusBold.setting_2, color: Color(0xFF8B5CF6)),
            SizedBox(width: 10),
            Text('Ajustes de Valkery', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Streaming Engine
          _buildCard(
            title: 'Motor de Streaming Stremio',
            icon: IconsaxPlusBold.cpu,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 5,
                      backgroundColor: isServerOnline ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isServerOnline
                          ? 'Estado: Online (Daemon Activo)'
                          : 'Estado: Standby / Offline',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isServerOnline ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stremioServerController,
                  decoration: InputDecoration(
                    labelText: 'URL del Streaming Server',
                    hintText: 'http://127.0.0.1:11470',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: () {
                        ref
                            .read(sourceCoordinatorProvider.notifier)
                            .setStremioServerUrl(_stremioServerController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Servidor Stremio actualizado')),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El servidor integrado gestiona la reproducción torrent y cache en segundo plano.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Stremio Account
          _buildCard(
            title: 'Cuenta de Stremio',
            icon: IconsaxPlusBold.user,
            child: currentUser != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0xFF8B5CF6),
                            child: Icon(Icons.person, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(currentUser.email,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(
                                  'AuthKey: ${currentUser.authKey.length > 12 ? "${currentUser.authKey.substring(0, 10)}..." : currentUser.authKey}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text('Sincronizar Datos'),
                            onPressed: () async {
                              await ref.read(stremioApiServiceProvider).syncAccountData();
                              ref.invalidate(stremioWatchHistoryProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Cuenta Stremio sincronizada')),
                                );
                              }
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                            icon: const Icon(Icons.logout, size: 16),
                            label: const Text('Cerrar Sesión'),
                            onPressed: () async {
                              await ref.read(stremioApiServiceProvider).logout();
                              ref.invalidate(stremioWatchHistoryProvider);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Modo Invitado Activo: puedes explorar y reproducir sin login.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      // Tabs: Login / Register / AuthKey
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Entrar')),
                          ButtonSegment(value: 1, label: Text('Registrarse')),
                          ButtonSegment(value: 2, label: Text('AuthKey')),
                        ],
                        selected: {_stremioAuthTab},
                        onSelectionChanged: (set) => setState(() => _stremioAuthTab = set.first),
                      ),
                      const SizedBox(height: 16),
                      if (_stremioAuthTab == 2) ...[
                        TextField(
                          controller: _authKeyController,
                          decoration: InputDecoration(
                            labelText: 'Stremio AuthKey / Token',
                            hintText: 'Pega tu token de autenticación...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Correo Electrónico',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                        icon: _isLoggingIn
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          _stremioAuthTab == 1
                              ? 'Crear Cuenta Stremio'
                              : (_stremioAuthTab == 2 ? 'Conectar con AuthKey' : 'Iniciar Sesión'),
                        ),
                        onPressed: _isLoggingIn ? null : _handleStremioAuth,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // 3. Stremio Addons Management
          _buildCard(
            title: 'Addons de Streaming (${addons.length})',
            icon: IconsaxPlusBold.category,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gestiona los proveedores de contenido y torrents.',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    FilledButton.tonalIcon(
                      icon: _isInstallingAddon
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 16),
                      label: const Text('Instalar Addon'),
                      onPressed: _isInstallingAddon ? null : _showInstallAddonDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: addons.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, idx) {
                    final addon = addons[idx];
                    return Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          child: const Icon(IconsaxPlusLinear.box, size: 18, color: Color(0xFF8B5CF6)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(addon.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(
                                'v${addon.version} • ${addon.catalogs.length} catálogos',
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                          tooltip: 'Desinstalar Addon',
                          onPressed: () async {
                            await ref.read(stremioApiServiceProvider).uninstallAddon(addon.id);
                            setState(() {});
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Preferred Video Player
          _buildCard(
            title: 'Reproductor Preferido',
            icon: IconsaxPlusBold.video_play,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  RadioListTile<ValkeryPlayerType>(
                    title: const Text('MediaKit Interno (Aceleración Hardware + PiP)'),
                    subtitle: const Text('Recomendado: fluido, con subtítulos integrados y reanudación.'),
                    value: ValkeryPlayerType.mediaKit,
                    groupValue: coordinator.preferredPlayer,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(sourceCoordinatorProvider.notifier).setPreferredPlayer(val);
                      }
                    },
                  ),
                  RadioListTile<ValkeryPlayerType>(
                    title: const Text('VLC Player Externo'),
                    subtitle: const Text('Lanza la aplicación VLC instalada en el sistema operativo.'),
                    value: ValkeryPlayerType.vlcExternal,
                    groupValue: coordinator.preferredPlayer,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(sourceCoordinatorProvider.notifier).setPreferredPlayer(val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 5. Jellyfin Integration
          _buildCard(
            title: 'Servidor Jellyfin (Opcional)',
            icon: IconsaxPlusBold.cloud_connection,
            child: coordinator.isJellyfinActive
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(radius: 5, backgroundColor: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              coordinator.jellyfinServerName ?? 'Servidor Jellyfin',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            if (coordinator.jellyfinServerVersion != null &&
                                coordinator.jellyfinServerVersion!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v${coordinator.jellyfinServerVersion}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          coordinator.jellyfinServerUrl,
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        if (jellyfinUser != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Sesión de usuario: ${jellyfinUser.name}',
                            style: const TextStyle(fontSize: 12, color: const Color(0xFF8B5CF6)),
                          ),
                        ],
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                          icon: const Icon(Icons.link_off, size: 16),
                          label: const Text('Desconectar Servidor'),
                          onPressed: _disconnectJellyfin,
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ingresa la dirección de tu servidor Jellyfin. Si la URL es accesible, se activará la sección de Jellyfin automáticamente.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _jellyfinServerController,
                        decoration: InputDecoration(
                          labelText: 'Dirección del Servidor Jellyfin',
                          hintText: 'http://192.168.1.100:8096',
                          prefixIcon: const Icon(IconsaxPlusLinear.global),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          errorText: _jellyfinError,
                        ),
                        onSubmitted: (_) => _testAndConnectJellyfin(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                        ),
                        icon: _isTestingJellyfin
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.link),
                        label: const Text('Probar y Conectar'),
                        onPressed: _isTestingJellyfin ? null : _testAndConnectJellyfin,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF8B5CF6), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }
}
