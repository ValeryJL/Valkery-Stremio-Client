import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../providers/stremio_providers.dart';
import '../../services/stremio/stremio_offline_download_manager.dart';
import 'stremio_player_screen.dart';

class StremioOfflineScreen extends ConsumerWidget {
  const StremioOfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final downloadsAsync = ref.watch(stremioOfflineDownloadsStreamProvider);
    final manager = ref.watch(stremioOfflineDownloadManagerProvider);

    final downloads = downloadsAsync.value ?? manager.allDownloads;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.75),
        elevation: 0,
        title: const Row(
          children: [
            Icon(IconsaxPlusBold.folder_favorite, color: Color(0xFF8B5CF6)),
            SizedBox(width: 10),
            Text(
              'Descargas Offline',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
      ),
      body: downloads.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    IconsaxPlusLinear.document_download,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No tienes contenido descargado',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Descarga películas o episodios para verlos sin conexión.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: downloads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = downloads[index];
                return _buildDownloadCard(context, ref, item);
              },
            ),
    );
  }

  Widget _buildDownloadCard(
    BuildContext context,
    WidgetRef ref,
    OfflineMediaEntry item,
  ) {
    final isCompleted = item.status == OfflineItemStatus.completed;

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
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: item.localPosterPath != null &&
                    File(item.localPosterPath!).existsSync()
                ? Image.file(
                    File(item.localPosterPath!),
                    width: 60,
                    height: 85,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 60,
                    height: 85,
                    color: Colors.white12,
                    child: const Icon(IconsaxPlusLinear.video),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  isCompleted
                      ? 'Descargado • ${(item.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                      : 'Descargando: ${(item.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCompleted
                        ? Colors.greenAccent
                        : const Color(0xFFC4B5FD),
                  ),
                ),
                if (!isCompleted) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: item.progress > 0 ? item.progress : null,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFF8B5CF6),
                    minHeight: 4,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(IconsaxPlusLinear.trash, size: 20, color: Colors.redAccent),
            tooltip: 'Eliminar descarga',
            onPressed: () {
              ref.read(stremioOfflineDownloadManagerProvider).deleteDownload(item.id);
            },
          ),
          if (isCompleted)
            IconButton(
              icon: const Icon(IconsaxPlusBold.play_circle,
                  size: 32, color: Color(0xFF8B5CF6)),
              tooltip: 'Reproducir sin conexión',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StremioPlayerScreen(
                      media: MediaItem(
                        id: item.id,
                        type: item.type,
                        name: item.title,
                        poster: '',
                      ),
                      stream: const StreamCandidate(
                        title: 'Archivo Local Offline',
                        name: 'Almacenamiento Local',
                        quality: 'Direct Disk',
                      ),
                      localFilePath: item.localVideoPath,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
