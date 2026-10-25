import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../providers/source_coordinator_provider.dart';
import '../../providers/stremio_providers.dart';

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

  @override
  void initState() {
    super.initState();
    final coordinator = ref.read(sourceCoordinatorProvider);
    _stremioServerController = TextEditingController(text: coordinator.stremioServerUrl);
    _jellyfinServerController = TextEditingController();
  }

  @override
  void dispose() {
    _stremioServerController.dispose();
    _jellyfinServerController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinator = ref.watch(sourceCoordinatorProvider);
    final serverStatusAsync = ref.watch(stremioServerStatusStreamProvider);
    final storage = ref.watch(stremioStorageProvider);
    final isServerOnline = serverStatusAsync.value?.isOnline ?? false;
    final currentUser = storage.currentUser;

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
            title: 'Integración Jellyfin (Opcional)',
            icon: IconsaxPlusBold.cloud_connection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Habilitar Fuente Jellyfin'),
                  subtitle: const Text('Si está desactivado, la app solo muestra Stremio.'),
                  value: coordinator.jellyfinEnabled,
                  activeColor: const Color(0xFF8B5CF6),
                  onChanged: (val) {
                    ref.read(sourceCoordinatorProvider.notifier).setJellyfinEnabled(val);
                  },
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
