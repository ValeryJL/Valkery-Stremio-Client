import 'dart:io';

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

class StremioOfflineScreen extends ConsumerStatefulWidget {
  const StremioOfflineScreen({super.key});

  @override
  ConsumerState<StremioOfflineScreen> createState() =>
      _StremioOfflineScreenState();
}

class _StremioOfflineScreenState extends ConsumerState<StremioOfflineScreen> {
  bool _isSyncing = false;

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

    // Group series by mediaId
    final groupedSeries = <String, List<OfflineMediaEntry>>{};
    for (final ep in seriesDownloads) {
      groupedSeries.putIfAbsent(ep.mediaId, () => []).add(ep);
    }

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

          // 4. Downloaded Series Section (Grouped by Series -> Seasons -> Episodes)
          if (groupedSeries.isNotEmpty) ...[
            _buildSectionHeader(
              icon: IconsaxPlusBold.video_play,
              title:
                  'Series descargadas (${groupedSeries.length} series • ${seriesDownloads.length} episodios)',
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 10),
            ...groupedSeries.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildSeriesGroupCard(
                  mediaId: entry.key,
                  episodes: entry.value,
                  watchState: storage.getWatchState(entry.key),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 5. Downloaded Movies Section
          if (movieDownloads.isNotEmpty) ...[
            _buildSectionHeader(
              icon: IconsaxPlusBold.video,
              title: 'Películas descargadas (${movieDownloads.length})',
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 10),
            ...movieDownloads.map(
              (movie) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildMovieCard(
                  movie,
                  storage.getWatchState(movie.mediaId),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 6. Empty Downloads State
          if (downloads.isEmpty) _buildEmptyDownloadsCard(),

          // 7. Cached Watch History for Offline Tracking
          if (watchHistory.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildSectionHeader(
              icon: IconsaxPlusBold.clock,
              title: 'Historial en caché local (${watchHistory.length})',
              color: const Color(0xFFC4B5FD),
            ),
            const SizedBox(height: 6),
            Text(
              'Podés marcar o desmarcar películas y capítulos como vistos aun estando sin internet; los cambios se encolan y se sincronizan automáticamente con Stremio Cloud al volver online.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            ...watchHistory.take(12).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildCachedHistoryTile(item),
                  ),
                ),
          ],
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

  Widget _buildSeriesGroupCard({
    required String mediaId,
    required List<OfflineMediaEntry> episodes,
    required LibraryWatchState? watchState,
  }) {
    final first = episodes.first;
    final seriesTitle = first.seriesTitle;
    final totalSeriesBytes = episodes.fold<int>(
      0,
      (sum, e) => sum + (e.totalBytes > 0 ? e.totalBytes : e.downloadedBytes),
    );

    // Group episodes by season
    final bySeason = <int, List<OfflineMediaEntry>>{};
    for (final ep in episodes) {
      final s = ep.season ?? 1;
      bySeason.putIfAbsent(s, () => []).add(ep);
    }
    final sortedSeasons = bySeason.keys.toList()..sort();
    for (final s in sortedSeasons) {
      bySeason[s]!.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: _buildPosterThumb(first, width: 48, height: 70),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  seriesTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (watchState?.pendingOfflineSync == true)
                _buildPendingSyncBadge(),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${episodes.length} ${episodes.length == 1 ? "episodio" : "episodios"} • ${sortedSeasons.length} ${sortedSeasons.length == 1 ? "temporada" : "temporadas"} • ${_formatBytes(totalSeriesBytes)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
          children: sortedSeasons.map((seasonNum) {
            final seasonEps = bySeason[seasonNum]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Temporada $seasonNum (${seasonEps.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC4B5FD),
                    ),
                  ),
                ),
                ...seasonEps.map(
                  (ep) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildEpisodeRow(ep, watchState),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEpisodeRow(
    OfflineMediaEntry ep,
    LibraryWatchState? watchState,
  ) {
    final epNum = ep.episode ?? 1;
    final seasonNum = ep.season ?? 1;
    final videoId = '${ep.mediaId}:$seasonNum:$epNum';
    final isWatched =
        watchState != null && watchState.watchedEpisodes.contains(videoId);
    final isCurrentVideo = watchState != null && watchState.videoId == videoId;
    final progressRatio = isCurrentVideo
        ? watchState.progressRatio
        : (isWatched ? 1.0 : 0.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWatched
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isWatched
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'E${epNum.toString().padLeft(2, "0")}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isWatched
                    ? const Color(0xFF10B981)
                    : const Color(0xFFC4B5FD),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ep.episodeTitle?.isNotEmpty == true
                            ? 'Episodio $epNum — ${ep.episodeTitle}'
                            : 'Temporada $seasonNum • Episodio $epNum',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isWatched)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Visto',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  children: [
                    Text(
                      _formatBytes(
                        ep.totalBytes > 0 ? ep.totalBytes : ep.downloadedBytes,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    if (ep.subtitles.isNotEmpty)
                      Text(
                        '${ep.subtitles.length} subtítulos offline',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFC4B5FD),
                        ),
                      ),
                  ],
                ),
                if (progressRatio > 0 && progressRatio < 1.0) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progressRatio,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFF8B5CF6),
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isWatched
                  ? IconsaxPlusBold.tick_circle
                  : IconsaxPlusLinear.tick_circle,
              size: 20,
              color: isWatched ? const Color(0xFF10B981) : Colors.white54,
            ),
            tooltip: isWatched ? 'Desmarcar visto' : 'Marcar como visto',
            onPressed: () => _toggleOfflineWatchedState(
              mediaId: ep.mediaId,
              name: ep.seriesTitle,
              type: 'series',
              poster: ep.posterUrl ?? '',
              season: seasonNum,
              episode: epNum,
            ),
          ),
          IconButton(
            icon: const Icon(
              IconsaxPlusLinear.trash,
              size: 18,
              color: Colors.redAccent,
            ),
            tooltip: 'Eliminar episodio',
            onPressed: () => _confirmSingleDelete(ep),
          ),
          IconButton(
            icon: const Icon(
              IconsaxPlusBold.play_circle,
              size: 28,
              color: Color(0xFF8B5CF6),
            ),
            tooltip: 'Reproducir sin conexión',
            onPressed: () => _openOfflinePlayer(ep),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieCard(
    OfflineMediaEntry item,
    LibraryWatchState? watchState,
  ) {
    final isWatched = watchState != null &&
        (watchState.flaggedWatched > 0 ||
            watchState.timesWatched > 0 ||
            watchState.progressRatio >= 0.9);
    final progressRatio = watchState?.progressRatio ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildPosterThumb(item, width: 56, height: 82),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.seriesTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (watchState?.pendingOfflineSync == true)
                      _buildPendingSyncBadge(),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  children: [
                    Text(
                      'Descargado • ${_formatBytes(item.totalBytes > 0 ? item.totalBytes : item.downloadedBytes)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    if (item.subtitles.isNotEmpty)
                      Text(
                        '• ${item.subtitles.length} subs offline',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFC4B5FD),
                        ),
                      ),
                  ],
                ),
                if (progressRatio > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progressRatio,
                    backgroundColor: Colors.white10,
                    color: isWatched
                        ? const Color(0xFF10B981)
                        : const Color(0xFF8B5CF6),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isWatched
                  ? IconsaxPlusBold.tick_circle
                  : IconsaxPlusLinear.tick_circle,
              size: 20,
              color: isWatched ? const Color(0xFF10B981) : Colors.white54,
            ),
            tooltip: isWatched ? 'Desmarcar visto' : 'Marcar como visto',
            onPressed: () => _toggleOfflineWatchedState(
              mediaId: item.mediaId,
              name: item.seriesTitle,
              type: item.type,
              poster: item.posterUrl ?? '',
            ),
          ),
          IconButton(
            icon: const Icon(
              IconsaxPlusLinear.trash,
              size: 20,
              color: Colors.redAccent,
            ),
            tooltip: 'Eliminar descarga',
            onPressed: () => _confirmSingleDelete(item),
          ),
          IconButton(
            icon: const Icon(
              IconsaxPlusBold.play_circle,
              size: 32,
              color: Color(0xFF8B5CF6),
            ),
            tooltip: 'Reproducir sin conexión',
            onPressed: () => _openOfflinePlayer(item),
          ),
        ],
      ),
    );
  }

  Widget _buildCachedHistoryTile(LibraryWatchState item) {
    final epParts = item.videoId.split(':');
    final isSeriesEp = epParts.length >= 3;
    final seasonNum = isSeriesEp ? int.tryParse(epParts[1]) : null;
    final epNum = isSeriesEp ? int.tryParse(epParts[2]) : null;
    final isWatched = isSeriesEp
        ? item.watchedEpisodes.contains(item.videoId)
        : (item.flaggedWatched > 0 ||
            item.timesWatched > 0 ||
            item.progressRatio >= 0.9);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.pendingOfflineSync
              ? Colors.amberAccent.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.poster.isNotEmpty
                ? Image.network(
                    item.poster,
                    width: 40,
                    height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 40,
                      height: 58,
                      color: Colors.white10,
                      child: const Icon(IconsaxPlusLinear.video, size: 18),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 58,
                    color: Colors.white10,
                    child: const Icon(IconsaxPlusLinear.video, size: 18),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StremioDetailScreen(
                      media: MediaItem(
                        id: item.id,
                        type: item.type,
                        name: item.name,
                        poster: item.poster,
                      ),
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.pendingOfflineSync) _buildPendingSyncBadge(),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isSeriesEp
                        ? 'Último: Temporada $seasonNum • Episodio $epNum (${item.watchedEpisodes.length} vistos)'
                        : (isWatched
                            ? 'Completado'
                            : 'Progreso: ${(item.progressRatio * 100).round()}%'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              isWatched
                  ? IconsaxPlusBold.tick_circle
                  : IconsaxPlusLinear.tick_circle,
              color: isWatched ? const Color(0xFF10B981) : Colors.white54,
              size: 20,
            ),
            tooltip: isWatched
                ? 'Desmarcar visto (encola sync offline si estás desconectado)'
                : 'Marcar visto (encola sync offline si estás desconectado)',
            onPressed: () => _toggleOfflineWatchedState(
              mediaId: item.id,
              name: item.name,
              type: item.type,
              poster: item.poster,
              season: seasonNum,
              episode: epNum,
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
