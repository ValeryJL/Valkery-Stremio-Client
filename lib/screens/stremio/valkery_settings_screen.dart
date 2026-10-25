import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';

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
  bool _isLoggingIn = false;
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
    super.dispose();
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
                  'El servidor local (11470) gestiona torrents y buffer en segundo plano.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: 'Cuenta de Stremio',
            icon: IconsaxPlusBold.user,
            child: currentUser != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sesión activa: ${currentUser.email}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${storage.addons.length} addons sincronizados',
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () async {
                          await ref.read(stremioApiServiceProvider).logout();
                          setState(() {});
                        },
                        child: const Text('Cerrar Sesión Stremio'),
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email de Stremio',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                        ),
                        icon: _isLoggingIn
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: const Text('Iniciar Sesión en Stremio'),
                        onPressed: _isLoggingIn
                            ? null
                            : () async {
                                setState(() => _isLoggingIn = true);
                                try {
                                  await ref
                                      .read(stremioApiServiceProvider)
                                      .login(
                                        _emailController.text,
                                        _passwordController.text,
                                      );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Sesión iniciada con éxito'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _isLoggingIn = false);
                                }
                              },
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: 'Reproductor Preferido',
            icon: IconsaxPlusBold.video_play,
            child: Column(
              children: [
                RadioListTile<ValkeryPlayerType>(
                  title: const Text('MediaKit Interno (Aceleración Hardware + PiP)'),
                  subtitle: const Text('Recomendado: fluido, con subtítulos y miniatura.'),
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
                  subtitle: const Text('Lanza la aplicación VLC instalada en el sistema.'),
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
          const SizedBox(height: 16),
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
                            style: const TextStyle(fontSize: 12, color: Color(0xFF8B5CF6)),
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
