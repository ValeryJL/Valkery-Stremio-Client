import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
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

    final isServerOnline = serverStatusAsync.value?.isOnline ?? false;

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
                ref.invalidate(stremioTopMoviesProvider);
                ref.invalidate(stremioTopSeriesProvider);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    item.poster,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black26,
                      child: const Center(
                        child: Icon(IconsaxPlusLinear.image, size: 36),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.type.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
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
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.releaseInfo.isNotEmpty
                        ? item.releaseInfo
                        : (item.genres.isNotEmpty ? item.genres.first : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
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

  Widget _buildSearchResults(AsyncValue<List<MediaItem>> asyncResults) {
    return asyncResults.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      ),
      error: (e, _) => Center(child: Text('Error en la búsqueda: $e')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No se encontraron resultados'));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.62,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => _buildPosterCard(items[index]),
        );
      },
    );
  }
}
