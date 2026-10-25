import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../providers/source_coordinator_provider.dart';
import '../../providers/stremio_providers.dart';
import 'stremio_player_screen.dart';

class StremioDetailScreen extends ConsumerStatefulWidget {
  final MediaItem media;

  const StremioDetailScreen({super.key, required this.media});

  @override
  ConsumerState<StremioDetailScreen> createState() => _StremioDetailScreenState();
}

class _StremioDetailScreenState extends ConsumerState<StremioDetailScreen> {
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  bool _isSeries = false;

  @override
  void initState() {
    super.initState();
    _isSeries = widget.media.type == 'series' || widget.media.type == 'anime';
    if (widget.media.episodes.isNotEmpty) {
      _selectedSeason = widget.media.episodes.first.season;
      _selectedEpisode = widget.media.episodes.first.episode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinator = ref.watch(sourceCoordinatorProvider);

    final streamsAsync = ref.watch(
      stremioStreamsProvider((
        id: widget.media.id,
        type: widget.media.type,
        season: _isSeries ? _selectedSeason : null,
        episode: _isSeries ? _selectedEpisode : null,
      )),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Background blurred backdrop
          if (widget.media.background.isNotEmpty || widget.media.poster.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                widget.media.background.isNotEmpty
                    ? widget.media.background
                    : widget.media.poster,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                color: theme.colorScheme.surface.withValues(alpha: 0.82),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                _buildHeader(theme),
                const SizedBox(height: 20),
                if (_isSeries) _buildSeasonEpisodeSelectors(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(
                      IconsaxPlusBold.link_circle,
                      size: 20,
                      color: Color(0xFF8B5CF6),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Fuentes y Streams Disponibles',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildStreamsList(streamsAsync, coordinator),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            widget.media.poster,
            width: 125,
            height: 185,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 125,
              height: 185,
              color: Colors.white12,
              child: const Icon(IconsaxPlusLinear.image, size: 40),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.media.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      widget.media.type.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC4B5FD),
                      ),
                    ),
                  ),
                  if (widget.media.releaseInfo.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      widget.media.releaseInfo,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              if (widget.media.genres.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: widget.media.genres
                      .take(3)
                      .map(
                        (g) => Chip(
                          label: Text(g, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 8),
              Text(
                widget.media.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonEpisodeSelectors() {
    final seasons = <int>{};
    for (final ep in widget.media.episodes) {
      seasons.add(ep.season);
    }
    final sortedSeasons = seasons.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Temporada y Episodio',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (sortedSeasons.isNotEmpty)
              DropdownButton<int>(
                value: _selectedSeason,
                dropdownColor: const Color(0xFF1F1B2E),
                items: sortedSeasons
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text('Temporada $s'),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSeason = val;
                      _selectedEpisode = 1;
                    });
                  }
                },
              ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.media.episodes
                      .where((e) => e.season == _selectedSeason)
                      .length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final epNum = index + 1;
                    final isSel = epNum == _selectedEpisode;
                    return ChoiceChip(
                      label: Text('Ep $epNum'),
                      selected: isSel,
                      selectedColor: const Color(0xFF8B5CF6),
                      onSelected: (_) {
                        setState(() => _selectedEpisode = epNum);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStreamsList(
    AsyncValue<List<StreamCandidate>> asyncStreams,
    SourceCoordinatorState coordinator,
  ) {
    return asyncStreams.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(28.0),
          child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        ),
      ),
      error: (e, _) => Center(
        child: Text('No se pudieron obtener streams: $e'),
      ),
      data: (streams) {
        if (streams.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'No hay streams disponibles para este título o episodio.',
                style: TextStyle(fontSize: 14),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: streams.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final stream = streams[index];
            return _buildStreamTile(stream, coordinator);
          },
        );
      },
    );
  }

  Widget _buildStreamTile(
    StreamCandidate stream,
    SourceCoordinatorState coordinator,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(
          stream.name.isNotEmpty ? stream.name : stream.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4, right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                stream.quality,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC4B5FD),
                ),
              ),
            ),
            if (stream.seeders > 0)
              Text(
                '👤 ${stream.seeders} seeds   ',
                style: const TextStyle(fontSize: 11, color: Colors.greenAccent),
              ),
            if (stream.size.isNotEmpty)
              Text(
                '💾 ${stream.size}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Download Offline Button
            IconButton(
              icon: const Icon(IconsaxPlusLinear.document_download, size: 20),
              tooltip: 'Descargar Offline',
              onPressed: () async {
                final dlManager = ref.read(stremioOfflineDownloadManagerProvider);
                try {
                  await dlManager.startDownload(
                    media: widget.media,
                    stream: stream,
                    season: _isSeries ? _selectedSeason : null,
                    episode: _isSeries ? _selectedEpisode : null,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Descarga iniciada: ${widget.media.name}'),
                        backgroundColor: const Color(0xFF8B5CF6),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al descargar: $e')),
                    );
                  }
                }
              },
            ),
            // Play Button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(IconsaxPlusBold.play, size: 16),
              label: const Text('Ver'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StremioPlayerScreen(
                      media: widget.media,
                      stream: stream,
                      season: _isSeries ? _selectedSeason : null,
                      episode: _isSeries ? _selectedEpisode : null,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
