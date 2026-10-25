import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/account_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/source_coordinator_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/views_provider.dart';
import '../dashboard/dashboard_screen.dart';

class ValkeryJellyfinView extends ConsumerStatefulWidget {
  const ValkeryJellyfinView({super.key});

  @override
  ConsumerState<ValkeryJellyfinView> createState() => _ValkeryJellyfinViewState();
}

class _ValkeryJellyfinViewState extends ConsumerState<ValkeryJellyfinView> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadServerPublicInfo();
    });
  }

  Future<void> _loadServerPublicInfo() async {
    final coordinator = ref.read(sourceCoordinatorProvider);
    if (coordinator.isJellyfinActive) {
      await ref.read(authProvider.notifier).setServer(coordinator.jellyfinServerUrl);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login([String? overrideUsername]) async {
    final username = overrideUsername ?? _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Por favor ingresa un nombre de usuario');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ref.read(authProvider.notifier).authenticateByName(username, password);
      if (res?.body != null) {
        // Authenticated successfully! Refresh Jellyfin views and dashboard
        await ref.read(viewsProvider.notifier).fetchViews();
        await ref.read(dashboardProvider.notifier).fetchNextUpAndResume();
      } else {
        setState(() {
          _errorMessage = 'Usuario o contraseña incorrectos';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de autenticación: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(userProvider);
    final coordinator = ref.watch(sourceCoordinatorProvider);

    if (currentUser != null) {
      // User is logged into Jellyfin: Show the full Jellyfin dashboard with a top bar
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
          elevation: 0,
          title: Row(
            children: [
              const Icon(IconsaxPlusBold.video_square, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              Text(
                coordinator.jellyfinServerName ?? 'Jellyfin',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 8),
              Text(
                '(${currentUser.name})',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar biblioteca',
              onPressed: () async {
                await ref.read(viewsProvider.notifier).fetchViews();
                await ref.read(dashboardProvider.notifier).fetchNextUpAndResume();
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión de Jellyfin',
              onPressed: () async {
                await ref.read(authProvider.notifier).logOutUser();
              },
            ),
          ],
        ),
        body: const DashboardScreen(),
      );
    }

    // User is NOT logged into Jellyfin: Show an elegant in-shell login view
    final authState = ref.watch(authProvider);
    final publicAccounts = authState.serverLoginModel?.accounts ?? <AccountModel>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    IconsaxPlusBold.video_square,
                    color: Color(0xFF8B5CF6),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Iniciar Sesión en Jellyfin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Servidor: ${coordinator.jellyfinServerName ?? 'Jellyfin'} (${coordinator.jellyfinServerUrl})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (publicAccounts.isNotEmpty) ...[
                    const Text(
                      'Usuarios del servidor:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: publicAccounts.map((account) {
                        return ActionChip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text(account.name),
                          onPressed: () {
                            _usernameController.text = account.name;
                            _login(account.name);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Iniciar Sesión'),
                    onPressed: _isLoading ? null : () => _login(),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Desconectar este servidor'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white60),
                    onPressed: () async {
                      await ref.read(sourceCoordinatorProvider.notifier).disconnectJellyfin();
                      await ref.read(authProvider.notifier).logOutUser();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
