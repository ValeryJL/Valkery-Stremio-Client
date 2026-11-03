import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/stremio_providers.dart';
import '../../services/stremio/stremio_offline_download_manager.dart';
import 'stremio_detail_screen.dart';
import 'stremio_player_screen.dart';

class _OfflineMediaSummary {
  final String mediaId;
  final String title;
  final String type;
  final String posterUrl;
  final int totalBytes;
  final int episodeCount;
  final List<OfflineMediaEntry> entries;

  _OfflineMediaSummary({
    required this.mediaId,
    required this.title,
    required this.type,
    required this.posterUrl,
    required this.totalBytes,
    required this.episodeCount,
    required this.entries,
  });
}

class StremioOfflineScreen extends ConsumerStatefulWidget {
  const StremioOfflineScreen({super.key});

  @override
  ConsumerState<StremioOfflineScreen> createState() =>
      _StremioOfflineScreenState();
}

class _StremioOfflineScreenState extends ConsumerState<StremioOfflineScreen> {
  bool _isSyncing = false;
  String _selectedFilter = 'Todos';

  Future<void> _handleManualSync() async {
    if (_isSyncing) return;
    final storage = ref.read(stremioStorageProvider);
    final api = ref.read(stremioApiServiceProvider);
    final isOffline = ref.read(stremioOfflineModeProvider);
    final authKey = storage.authKey;

    if (authKey == null || authKey.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Iniciá sesión en tu cuenta de Stremio (Ajustes) para sincronizar el progreso con la nube.',
          ),
          backgroundColor: Color(0xFF1F1D36),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      if (isOffline) {
        await ref.read(stremioOfflineModeProvider.notifier).setOffline(false);
      }
      final pendingCount = storage.offlineSyncQueue.length;
      final flushed = await api.flushOfflineSyncQueue(authKey);
      await api.fetchWatchHistory(authKey);
      ref.invalidate(stremioWatchHistoryProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            flushed > 0
                ? 'Se sincronizaron $flushed progresos pendientes con Stremio Cloud.'
                : (pendingCount == 0
                    ? 'Historial actualizado y sincronizado con Stremio Cloud.'
                    : 'No se pudo conectar con Stremio Cloud. Quedan $pendingCount en cola.'),
          ),
          backgroundColor:
              flushed > 0 || pendingCount == 0 ? const Color(0xFF10B981) : Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _toggleOfflineWatchedState({
    required String mediaId,
    required String name,
    required String type,
    required String poster,
    int? season,
    int? episode,
  }) async {
    final storage = ref.read(stremioStorageProvider);
    final api = ref.read(stremioApiServiceProvider);
    final isOffline = ref.read(stremioOfflineModeProvider);
    final authKey = storage.authKey;

    final existing = storage.getWatchState(mediaId);
    final videoId = (season != null && episode != null)
        ? '$mediaId:$season:$episode'
        : mediaId;

    final isSeries = type == 'series' || (season != null && episode != null);
    final currentEpisodes = <String>{
      if (existing != null) ...existing.watchedEpisodes,
    };

    bool nowWatched;
    int flaggedWatched = existing?.flaggedWatched ?? 0;
    int timesWatched = existing?.timesWatched ?? 0;
    int timeOffset = existing?.timeOffset ?? 0;

    if (isSeries) {
      if (currentEpisodes.contains(videoId)) {
        currentEpisodes.remove(videoId);
        nowWatched = false;
      } else {
        currentEpisodes.add(videoId);
        nowWatched = true;
      }
    } else {
      final wasWatched = flaggedWatched > 0 ||
          timesWatched > 0 ||
          (existing != null && existing.progressRatio >= 0.9);
      nowWatched = !wasWatched;
      flaggedWatched = nowWatched ? 1 : 0;
      timesWatched = nowWatched ? 1 : 0;
      timeOffset = 0;
      if (nowWatched) {
        currentEpisodes.add(videoId);
      } else {
        currentEpisodes.remove(videoId);
      }
    }

    final shouldQueueOffline =
        isOffline || storage.isOfflineMode || authKey == null || authKey.isEmpty;

    final updated = LibraryWatchState(
      id: mediaId,
      name: name,
      type: type,
      poster: poster.isNotEmpty ? poster : (existing?.poster ?? ''),
      videoId: videoId,
      timeOffset: nowWatched ? 0 : timeOffset,
      duration: (existing?.duration ?? 0) > 0 ? existing!.duration : 3600,
      timesWatched: timesWatched,
      flaggedWatched: flaggedWatched,
      watchedEpisodes: currentEpisodes.toList(),
      lastWatched: DateTime.now().toUtc(),
      isLibraryItem: existing?.isLibraryItem ?? false,
      pendingOfflineSync: shouldQueueOffline,
    );

    if (shouldQueueOffline) {
      await storage.enqueueOfflineWatchSync(updated);
    } else {
      await storage.upsertWatchState(updated, enqueueOfflineSync: false);
      await api.syncWatchState(authKey, updated);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowWatched
              ? (shouldQueueOffline
                  ? 'Marcado como visto (en cola para sincronizar al volver online)'
                  : 'Marcado como visto y sincronizado con Stremio')
              : 'Desmarcado como visto',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1F1D36),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmSingleDelete(OfflineMediaEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18162B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Row(
          children: [
            Icon(IconsaxPlusLinear.trash, color: Colors.redAccent, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirmar eliminación',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Querés eliminar la descarga "${entry.title}" (${_formatBytes(entry.totalBytes > 0 ? entry.totalBytes : entry.downloadedBytes)}) del almacenamiento local?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(IconsaxPlusLinear.trash, size: 16),
            label: const Text('Eliminar archivo'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(stremioOfflineDownloadManagerProvider)
          .deleteDownload(entry.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se eliminó "${entry.title}".'),
          backgroundColor: const Color(0xFF1F1D36),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showDeleteWatchedApprovalDialog(
    List<OfflineMediaEntry> watchedCandidates,
  ) async {
    if (watchedCandidates.isEmpty) return;

    final selectedIds = <String>{
      for (final item in watchedCandidates) item.id,
    };

    final approvedIds = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedBytes = watchedCandidates
                .where((e) => selectedIds.contains(e.id))
                .fold<int>(
                  0,
                  (sum, e) =>
                      sum + (e.totalBytes > 0 ? e.totalBytes : e.downloadedBytes),
                );

            return AlertDialog(
              backgroundColor: const Color(0xFF18162B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
              ),
              title: const Row(
                children: [
                  Icon(
                    IconsaxPlusBold.shield_tick,
                    color: Color(0xFF8B5CF6),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Confirmar limpieza de vistos',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seleccioná qué contenidos ya vistos querés eliminar del disco (${_formatBytes(selectedBytes)} a liberar):',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: watchedCandidates.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: Colors.white10,
                        ),
                        itemBuilder: (context, idx) {
                          final entry = watchedCandidates[idx];
                          final checked = selectedIds.contains(entry.id);
                          final bytes = entry.totalBytes > 0
                              ? entry.totalBytes
                              : entry.downloadedBytes;
                          return CheckboxListTile(
                            value: checked,
                            dense: true,
                            activeColor: const Color(0xFF8B5CF6),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              entry.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              _formatBytes(bytes),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedIds.add(entry.id);
                                } else {
                                  selectedIds.remove(entry.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(ctx).pop(selectedIds),
                  icon: const Icon(IconsaxPlusLinear.trash, size: 16),
                  label: Text('Eliminar (${selectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (approvedIds != null && approvedIds.isNotEmpty && mounted) {
      final count = await ref
          .read(stremioOfflineDownloadManagerProvider)
          .deleteSelectedDownloads(approvedIds);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se eliminaron $count archivos vistos tras tu confirmación.',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openOfflinePlayer(OfflineMediaEntry item) {
    final isSeries =
        item.type == 'series' || (item.season != null && item.episode != null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StremioPlayerScreen(
          media: MediaItem(
            id: item.mediaId,
            type: isSeries ? 'series' : item.type,
            name: item.seriesTitle,
            poster: item.posterUrl ?? '',
          ),
          stream: StreamCandidate(
            title: item.title,
            name: 'Almacenamiento Offline',
            url: item.localVideoPath,
            quality: 'Local',
            behaviorHints: const {'notWebReady': false},
          ),
          season: item.season,
          episode: item.episode,
          localFilePath: item.localVideoPath,
          localSubtitles: item.subtitles,
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'Archivo local';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadsAsync = ref.watch(stremioOfflineDownloadsStreamProvider);
    final manager = ref.watch(stremioOfflineDownloadManagerProvider);
    final storage = ref.watch(stremioStorageProvider);
    final isOfflineMode = ref.watch(stremioOfflineModeProvider);
    final pendingSyncList = ref.watch(stremioPendingOfflineSyncProvider);
    final watchHistoryAsync = ref.watch(stremioWatchHistoryStreamProvider);
    final watchHistory = watchHistoryAsync.value ?? storage.watchHistory;

    final downloads = downloadsAsync.value ?? manager.allDownloads;

    final activeDownloads = downloads
        .where((d) =>
            d.status == OfflineItemStatus.downloading ||
            d.status == OfflineItemStatus.queued ||
            d.status == OfflineItemStatus.paused ||
            d.status == OfflineItemStatus.failed)
        .toList();

    final completedDownloads = downloads
        .where((d) => d.status == OfflineItemStatus.completed)
        .toList();

    final seriesDownloads = completedDownloads
        .where((d) =>
            d.type == 'series' || (d.season != null && d.episode != null))
        .toList();

    final movieDownloads = completedDownloads
        .where((d) =>
            d.type != 'series' && (d.season == null || d.episode == null))
        .toList();

    // Group completed downloads into unified media items
    final Map<String, _OfflineMediaSummary> mediaSummaries = {};
    for (final entry in completedDownloads) {
      final isSeries = entry.type == 'series' || (entry.season != null && entry.episode != null);
      final mediaId = entry.mediaId;
      final existing = mediaSummaries[mediaId];
      final bytes = entry.totalBytes > 0 ? entry.totalBytes : entry.downloadedBytes;
      if (existing == null) {
        mediaSummaries[mediaId] = _OfflineMediaSummary(
          mediaId: mediaId,
          title: isSeries ? entry.seriesTitle : entry.title,
          type: isSeries ? 'series' : 'movie',
          posterUrl: entry.posterUrl ?? '',
          totalBytes: bytes,
          episodeCount: 1,
          entries: [entry],
        );
      } else {
        mediaSummaries[mediaId] = _OfflineMediaSummary(
          mediaId: mediaId,
          title: existing.title,
          type: existing.type,
          posterUrl: existing.posterUrl.isNotEmpty ? existing.posterUrl : (entry.posterUrl ?? ''),
          totalBytes: existing.totalBytes + bytes,
          episodeCount: existing.episodeCount + 1,
          entries: [...existing.entries, entry],
        );
      }
    }

    final allSummaries = mediaSummaries.values.toList();
    final filteredSummaries = allSummaries.where((s) {
      if (_selectedFilter == 'Series') return s.type == 'series';
      if (_selectedFilter == 'Películas') return s.type != 'series';
      return true;
    }).toList();

    final totalBytesUsed = downloads.fold<int>(
      0,
      (sum, item) =>
          sum + (item.totalBytes > 0 ? item.totalBytes : item.downloadedBytes),
    );

    final watchedCandidates = manager.getWatchedCompletedDownloads(storage);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.78),
        elevation: 0,
        title: Row(
          children: [
            const Icon(
              IconsaxPlusBold.folder_favorite,
              color: Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Modo Offline y Descargas',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pendingSyncList.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      IconsaxPlusBold.cloud_notif,
                      size: 14,
                      color: Colors.amberAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${pendingSyncList.length} pend.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // 1. Storage & Offline Mode Control Header
          _buildOverviewCard(
            isOfflineMode: isOfflineMode,
            totalBytesUsed: totalBytesUsed,
            movieCount: movieDownloads.length,
            episodeCount: seriesDownloads.length,
            activeCount: activeDownloads.length,
            watchedCandidates: watchedCandidates,
          ),
          const SizedBox(height: 14),

          // 2. Offline Watch Progress Sync Queue Panel
          _buildSyncStatusCard(
            pendingSyncList: pendingSyncList,
            isOfflineMode: isOfflineMode,
            isLoggedIn:
                storage.authKey != null && storage.authKey!.trim().isNotEmpty,
          ),
          const SizedBox(height: 20),

          // 3. Active Downloads Section
          if (activeDownloads.isNotEmpty) ...[
            _buildSectionHeader(
              icon: IconsaxPlusBold.arrow_down,
              title: 'Descargando ahora (${activeDownloads.length})',
              color: const Color(0xFF38BDF8),
            ),
            const SizedBox(height: 10),
            ...activeDownloads.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildActiveDownloadTile(item),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 4. Downloaded Library Grid
          if (allSummaries.isNotEmpty) ...[
            _buildSectionHeader(
              icon: IconsaxPlusBold.folder_favorite,
              title: 'Descargas en tu dispositivo (${allSummaries.length})',
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in ['Todos', 'Series', 'Películas']) ...[
                    ChoiceChip(
                      label: Text(
                        tab == 'Todos'
                            ? 'Todos (${allSummaries.length})'
                            : (tab == 'Series'
                                ? 'Series (${allSummaries.where((s) => s.type == "series").length})'
                                : 'Películas (${allSummaries.where((s) => s.type != "series").length})'),
                      ),
                      selected: _selectedFilter == tab,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedFilter = tab);
                      },
                      selectedColor: const Color(0xFF8B5CF6),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      labelStyle: TextStyle(
                        color: _selectedFilter == tab ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: _selectedFilter == tab ? FontWeight.bold : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide.none,
                      showCheckmark: false,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (filteredSummaries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No hay descargas para el filtro "$_selectedFilter"',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 0.58,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                ),
                itemCount: filteredSummaries.length,
                itemBuilder: (context, index) {
                  final item = filteredSummaries[index];
                  final watchState = storage.getWatchState(item.mediaId);
                  return _buildOfflineMediaCard(item, watchState);
                },
              ),
            const SizedBox(height: 20),
          ],

          // 5. Empty Downloads State
          if (downloads.isEmpty) _buildEmptyDownloadsCard(),
        ],
      ),
    );
  }
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required bool isOfflineMode,
    required int totalBytesUsed,
    required int movieCount,
    required int episodeCount,
    required int activeCount,
    required List<OfflineMediaEntry> watchedCandidates,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOfflineMode
              ? [
                  const Color(0xFF4C1D95).withValues(alpha: 0.45),
                  const Color(0xFF1E1B2E).withValues(alpha: 0.85),
                ]
              : [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.03),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOfflineMode
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOfflineMode
                      ? Colors.amber.withValues(alpha: 0.2)
                      : const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOfflineMode
                      ? IconsaxPlusBold.wifi_square
                      : IconsaxPlusBold.cloud_connection,
                  color:
                      isOfflineMode ? Colors.amberAccent : const Color(0xFFC4B5FD),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOfflineMode
                          ? 'Modo Offline Activado'
                          : 'Modo Online Activo',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOfflineMode
                          ? 'Todo el progreso que veas o marques ahora se guardará en la cola local y se subirá a Stremio al reconectar.'
                          : 'Conectado a Stremio Cloud. Activá el Modo Offline para usar sólo caché local.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isOfflineMode,
                activeThumbColor: Colors.amberAccent,
                onChanged: (enabled) async {
                  await ref
                      .read(stremioOfflineModeProvider.notifier)
                      .setOffline(enabled);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        enabled
                            ? 'Modo Offline activado. Tus cambios de progreso se guardarán en cola.'
                            : 'Modo Online restaurado. Sincronizando cola pendiente con Stremio Cloud...',
                      ),
                      backgroundColor: const Color(0xFF1F1D36),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white12),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMetricChip(
                    icon: Icons.sd_storage_outlined,
                    label: totalBytesUsed > 0
                        ? _formatBytes(totalBytesUsed)
                        : '0 MB en disco',
                  ),
                  const SizedBox(width: 8),
                  _buildMetricChip(
                    icon: IconsaxPlusLinear.video,
                    label: '$movieCount pelis',
                  ),
                  const SizedBox(width: 8),
                  _buildMetricChip(
                    icon: IconsaxPlusLinear.video_play,
                    label: '$episodeCount caps',
                  ),
                  if (activeCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildMetricChip(
                      icon: IconsaxPlusLinear.arrow_down,
                      label: '$activeCount activas',
                    ),
                  ],
                ],
              ),
              if (watchedCandidates.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: BorderSide(
                      color: Colors.amberAccent.withValues(alpha: 0.5),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      _showDeleteWatchedApprovalDialog(watchedCandidates),
                  icon: const Icon(IconsaxPlusLinear.broom, size: 16),
                  label: Text(
                    'Liberar vistos (${watchedCandidates.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFC4B5FD)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusCard({
    required List<LibraryWatchState> pendingSyncList,
    required bool isOfflineMode,
    required bool isLoggedIn,
  }) {
    final hasPending = pendingSyncList.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: hasPending
            ? Colors.amber.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPending
              ? Colors.amberAccent.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPending
                    ? IconsaxPlusBold.refresh_circle
                    : IconsaxPlusBold.tick_circle,
                color: hasPending ? Colors.amberAccent : const Color(0xFF10B981),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPending
                          ? '${pendingSyncList.length} ${pendingSyncList.length == 1 ? 'elemento pendiente' : 'elementos pendientes'} de sincronizar con Stremio Cloud'
                          : 'Sincronización Offline al día',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !isLoggedIn
                          ? 'Iniciá sesión en Ajustes para respaldar estos progresos en tu cuenta oficial de Stremio.'
                          : (hasPending
                              ? (isOfflineMode
                                  ? 'Se enviarán automáticamente apenas desactives el Modo Offline o tocando "Sincronizar ahora".'
                                  : 'Listos para enviar a Stremio Cloud.')
                              : 'Todos tus tiempos de reproducción y episodios vistos están sincronizados.'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: hasPending
                      ? Colors.amber.shade700
                      : const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: _isSyncing ? null : _handleManualSync,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(IconsaxPlusLinear.cloud_change, size: 16),
                label: Text(
                  hasPending ? 'Sincronizar ahora' : 'Verificar Sync',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (hasPending) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: pendingSyncList.map((item) {
                final epParts = item.videoId.split(':');
                final epLabel = epParts.length >= 3
                    ? ' (T${epParts[1]}:E${epParts[2]})'
                    : '';
                final statusText = item.timeOffset > 0
                    ? '${(item.progressRatio * 100).round()}%'
                    : 'Visto';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        IconsaxPlusLinear.clock,
                        size: 13,
                        color: Colors.amberAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${item.name}$epLabel • $statusText',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveDownloadTile(OfflineMediaEntry item) {
    final isFailed = item.status == OfflineItemStatus.failed;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildPosterThumb(item, width: 48, height: 68),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  isFailed
                      ? 'Error: ${item.errorMessage ?? "Descarga interrumpida"}'
                      : 'Descargando: ${(item.progress * 100).toStringAsFixed(0)}% • ${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isFailed ? Colors.redAccent : const Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: item.progress > 0 ? item.progress : null,
                  backgroundColor: Colors.white10,
                  color: isFailed ? Colors.redAccent : const Color(0xFF38BDF8),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              IconsaxPlusLinear.close_circle,
              color: Colors.redAccent,
            ),
            tooltip: 'Cancelar descarga',
            onPressed: () => _confirmSingleDelete(item),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineMediaCard(
    _OfflineMediaSummary item,
    LibraryWatchState? watchState,
  ) {
    final isWatched = watchState != null &&
        (watchState.flaggedWatched > 0 ||
            watchState.timesWatched > 0 ||
            watchState.progressRatio >= 0.9);
    final progress = watchState?.progressRatio ?? 0.0;
    final isSeries = item.type == 'series';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StremioDetailScreen(
              media: MediaItem(
                id: item.mediaId,
                type: item.type,
                name: item.title,
                poster: item.posterUrl,
              ),
            ),
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
                  child: item.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _posterFallback(180, 270),
                          errorWidget: (_, __, ___) => _posterFallback(180, 270),
                        )
                      : _posterFallback(180, 270),
                ),

                // Top Left: DESCARGADO Pill
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          IconsaxPlusBold.document_download,
                          size: 10,
                          color: Colors.white,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'DESCARGADO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Right: Size / Episode Pill
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isSeries
                          ? '${item.episodeCount} ${item.episodeCount == 1 ? "ep." : "eps."}'
                          : _formatBytes(item.totalBytes),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Bottom Progress Bar or Watched Badge
                if (progress > 0 && progress < 0.95)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.black45,
                        color: const Color(0xFF8B5CF6),
                        minHeight: 4,
                      ),
                    ),
                  )
                else if (isWatched)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isSeries
                ? '${item.episodeCount} ${item.episodeCount == 1 ? "episodio" : "episodios"} • ${_formatBytes(item.totalBytes)}'
                : 'Película • ${_formatBytes(item.totalBytes)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSyncBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
      ),
      child: const Text(
        'Pendiente Sync',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.amberAccent,
        ),
      ),
    );
  }

  Widget _buildPosterThumb(
    OfflineMediaEntry item, {
    required double width,
    required double height,
  }) {
    if (!kIsWeb &&
        item.localPosterPath != null &&
        item.localPosterPath!.isNotEmpty &&
        File(item.localPosterPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(item.localPosterPath!),
          width: width,
          height: height,
          fit: BoxFit.cover,
        ),
      );
    }
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          item.posterUrl!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _posterFallback(width, height),
        ),
      );
    }
    return _posterFallback(width, height);
  }

  Widget _posterFallback(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(IconsaxPlusLinear.video, size: 22),
    );
  }

  Widget _buildEmptyDownloadsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(
            IconsaxPlusLinear.document_download,
            size: 52,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 14),
          const Text(
            'No tenés archivos descargados todavía',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Abrí cualquier película o capítulo de serie y tocá el botón de descarga junto a la fuente para guardarlo con sus subtítulos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
