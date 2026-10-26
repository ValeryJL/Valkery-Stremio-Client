import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/stremio_providers.dart';
import 'stremio_detail_screen.dart';

class StremioDiscoverScreen extends ConsumerStatefulWidget {
  const StremioDiscoverScreen({super.key});

  @override
  ConsumerState<StremioDiscoverScreen> createState() => _StremioDiscoverScreenState();
}

class _StremioDiscoverScreenState extends ConsumerState<StremioDiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stremioApiServiceProvider).syncAccountData().then((_) {
        if (mounted) {
          ref.invalidate(stremioWatchHistoryProvider);
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topMoviesAsync = ref.watch(stremioTopMoviesProvider);
    final topSeriesAsync = ref.watch(stremioTopSeriesProvider);
    final searchResultsAsync = ref.watch(stremioSearchResultsProvider);
    final serverStatusAsync = ref.watch(stremioServerStatusStreamProvider);
    final watchHistoryAsync = ref.watch(stremioWatchHistoryProvider);

    final isServerOnline = serverStatusAsync.value?.isOnline ?? false;
    final historyItems = watchHistoryAsync.value ?? <LibraryWatchState>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.75),
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar películas, series o anime en Stremio...',
                  border: InputBorder.none,
                ),
                onSubmitted: (query) {
                  ref.read(stremioSearchQueryProvider.notifier).state = query;
                },
              )
            : Row(
                children: [
                  Image.asset(
                    'assets/icons/valkery_icon.png',
                    height: 28,
                    width: 28,
                    errorBuilder: (_, __, ___) => const Icon(
                      IconsaxPlusBold.video_play,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Valkery Stremio',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isServerOnline
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isServerOnline ? Colors.green : Colors.orange,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 3.5,
                          backgroundColor:
                              isServerOnline ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isServerOnline ? 'Engine Online' : 'Engine Standby',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isServerOnline ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : IconsaxPlusLinear.search_normal_1),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  ref.read(stremioSearchQueryProvider.notifier).state = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isSearching
          ? _buildSearchResults(searchResultsAsync)
          : RefreshIndicator(
              color: const Color(0xFF8B5CF6),
              onRefresh: () async {
                await ref.read(stremioApiServiceProvider).syncAccountData();
                ref.invalidate(stremioWatchHistoryProvider);
                ref.invalidate(stremioTopMoviesProvider);
                ref.invalidate(stremioTopSeriesProvider);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  if (historyItems.isNotEmpty) ...[
                    _buildSectionHeader('Continuar Viendo / Recientes', IconsaxPlusBold.clock),
                    _buildWatchHistoryCarousel(historyItems),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionHeader('Películas Populares', IconsaxPlusBold.video),
                  _buildMediaCarousel(topMoviesAsync),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Series Populares', IconsaxPlusBold.play_circle),
                  _buildMediaCarousel(topSeriesAsync),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF8B5CF6)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchHistoryCarousel(List<LibraryWatchState> items) {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          var poster = item.poster;
          if (poster.isEmpty && item.id.startsWith('tt')) {
            poster = 'https://images.metahub.space/poster/medium/${item.id}/img.jpg';
          }

          final media = MediaItem(
            id: item.id,
            type: item.type,
            name: item.name,
            poster: poster,
          );

          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StremioDetailScreen(media: media),
                ),
              );
            },
            child: Container(
              width: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (poster.isNotEmpty)
                          Image.network(
                            poster,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          )
                        else
                          _buildPlaceholder(),
                        if (item.currentSeason != null && item.currentEpisode != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'T${item.currentSeason} E${item.currentEpisode}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        if (item.progressRatio > 0 && !item.isCompleted)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              value: item.progressRatio,
                              minHeight: 4,
                              backgroundColor: Colors.black54,
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaCarousel(AsyncValue<List<MediaItem>> asyncItems) {
    return asyncItems.when(
      loading: () => const SizedBox(
        height: 230,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
      ),
      error: (e, _) => SizedBox(
        height: 120,
        child: Center(
          child: Text('Error al cargar catálogo: $e'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text('No hay contenido disponible')),
          );
        }

        return SizedBox(
          height: 250,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildPosterCard(item);
            },
          ),
        );
      },
    );
  }

  Widget _buildPosterCard(MediaItem item) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StremioDetailScreen(media: item),
          ),
        );
      },
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.poster.isNotEmpty)
                    Image.network(
                      item.poster,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  else
                    _buildPlaceholder(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.type.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.releaseInfo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Center(
        child: Icon(IconsaxPlusLinear.video, color: Colors.white30, size: 36),
      ),
    );
  }

  Widget _buildSearchResults(AsyncValue<List<MediaItem>> asyncResults) {
    return asyncResults.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      ),
      error: (e, _) => Center(child: Text('Error en búsqueda: $e')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No se encontraron resultados'));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.62,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _buildPosterCard(items[index]);
          },
        );
      },
    );
  }
}
