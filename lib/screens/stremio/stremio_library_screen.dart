import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/stremio_providers.dart';
import 'stremio_detail_screen.dart';

enum LibraryFilter {
  all('Todos'),
  inProgress('En curso'),
  movies('Películas'),
  series('Series'),
  completed('Vistos');

  final String label;
  const LibraryFilter(this.label);
}

class StremioLibraryScreen extends ConsumerStatefulWidget {
  final VoidCallback? onExploreCatalog;

  const StremioLibraryScreen({
    super.key,
    this.onExploreCatalog,
  });

  @override
  ConsumerState<StremioLibraryScreen> createState() => _StremioLibraryScreenState();
}

class _StremioLibraryScreenState extends ConsumerState<StremioLibraryScreen> {
  LibraryFilter _activeFilter = LibraryFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSyncing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    setState(() => _isSyncing = true);
    try {
      final api = ref.read(stremioApiServiceProvider);
      await api.syncAccountData();
      ref.invalidate(stremioWatchHistoryProvider);
    } catch (_) {}
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  List<LibraryWatchState> _filterItems(List<LibraryWatchState> items) {
    var result = items;

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      result = result.where((i) => i.name.toLowerCase().contains(q)).toList();
    }

    switch (_activeFilter) {
      case LibraryFilter.all:
        break;
      case LibraryFilter.inProgress:
        result = result
            .where((i) => i.progressRatio > 0.05 && !i.isCompleted)
            .toList();
        break;
      case LibraryFilter.movies:
        result = result.where((i) => i.type == 'movie').toList();
        break;
      case LibraryFilter.series:
        result = result.where((i) => i.type == 'series').toList();
        break;
      case LibraryFilter.completed:
        result = result.where((i) => i.isCompleted).toList();
        break;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(stremioLibraryItemsProvider);
    final allLibraryItems = libraryAsync.value ?? <LibraryWatchState>[];
    final filteredItems = _filterItems(allLibraryItems);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        elevation: 0,
        title: Row(
          children: [
            const Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6), size: 24),
            const SizedBox(width: 10),
            const Text(
              'Biblioteca',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${filteredItems.length}',
                style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar cuenta Stremio',
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                  )
                : const Icon(IconsaxPlusLinear.refresh),
            onPressed: _isSyncing ? null : _handleRefresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF8B5CF6),
        child: Column(
          children: [
            // Search & Filter header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  // Search Bar
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Filtrar biblioteca...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          IconsaxPlusLinear.search_normal_1,
                          size: 18,
                          color: Colors.white54,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(IconsaxPlusLinear.close_circle, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: LibraryFilter.values.map((filter) {
                        final isSelected = _activeFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(filter.label),
                            selected: isSelected,
                            onSelected: (_) => setState(() => _activeFilter = filter),
                            selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                            checkmarkColor: const Color(0xFF8B5CF6),
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            labelStyle: TextStyle(
                              color: isSelected ? const Color(0xFF8B5CF6) : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.white.withValues(alpha: 0.1),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Content Grid or Empty State
            Expanded(
              child: libraryAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                ),
                error: (e, _) => Center(
                  child: Text('Error al cargar biblioteca: $e', style: const TextStyle(color: Colors.white70)),
                ),
                data: (_) {
                  if (filteredItems.isEmpty) {
                    return _buildEmptyState();
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return _buildLibraryCard(item);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusLinear.folder_favorite,
                size: 56,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No se encontraron resultados para "$_searchQuery"'
                  : 'Tu biblioteca de Stremio está vacía',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Intenta con otro término o limpia los filtros.'
                  : 'Añade contenido a tu biblioteca de Stremio tocando el botón de biblioteca en su ficha.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            if (widget.onExploreCatalog != null)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(IconsaxPlusBold.discover, size: 18),
                label: const Text('Explorar Catálogo', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: widget.onExploreCatalog,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryCard(LibraryWatchState item) {
    final media = MediaItem(
      id: item.id,
      name: item.name,
      type: item.type,
      poster: item.poster,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StremioDetailScreen(media: media),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: item.poster.isNotEmpty
                      ? Image.network(
                          item.poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildFallbackPoster(),
                        )
                      : _buildFallbackPoster(),
                ),

                // Episode badge for series
                if (item.currentSeason != null && item.currentEpisode != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'S${item.currentSeason!.toString().padLeft(2, '0')}E${item.currentEpisode!.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Completed checkmark badge
                if (item.isCompleted)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 12, color: Colors.white),
                    ),
                  ),

                // Progress Bar at bottom of poster
                if (item.progressRatio > 0 && !item.isCompleted)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: LinearProgressIndicator(
                        value: item.progressRatio,
                        minHeight: 4,
                        backgroundColor: Colors.black54,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                      ),
                    ),
                  ),

                // Options action button (overflow menu)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_vert, size: 16, color: Colors.white70),
                    ),
                    color: const Color(0xFF1F1D36),
                    onSelected: (val) async {
                      final api = ref.read(stremioApiServiceProvider);
                      final storage = ref.read(stremioStorageProvider);
                      final authKey = storage.authKey ?? '';

                      if (val == 'remove') {
                        await api.removeFromLibrary(authKey, item.id);
                        ref.invalidate(stremioWatchHistoryProvider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"${item.name}" quitado de la biblioteca'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else if (val == 'mark_watched') {
                        final updated = item.copyWith(
                          flaggedWatched: item.isCompleted ? 0 : 1,
                          timeOffset: item.isCompleted ? 0 : item.duration,
                        );
                        await api.syncWatchState(authKey, updated);
                        ref.invalidate(stremioWatchHistoryProvider);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'mark_watched',
                        child: Row(
                          children: [
                            Icon(
                              item.isCompleted ? Icons.undo : Icons.check_circle_outline,
                              size: 18,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Text(item.isCompleted ? 'Marcar no visto' : 'Marcar como visto'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(IconsaxPlusLinear.trash, size: 18, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Quitar de Biblioteca', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Title
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          // Type badge
          Text(
            item.type == 'series' ? 'Serie' : 'Película',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackPoster() {
    return Container(
      color: const Color(0xFF1E1A33),
      child: const Center(
        child: Icon(IconsaxPlusLinear.video_play, size: 36, color: Colors.white24),
      ),
    );
  }
}
