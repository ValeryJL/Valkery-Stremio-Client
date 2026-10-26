import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../../models/stremio/media_item.dart';
import '../../models/stremio/stream_candidate.dart';
import '../../models/stremio/watch_history_item.dart';
import '../../providers/source_coordinator_provider.dart';
import '../../providers/stremio_providers.dart';
import '../../util/web_image_helper.dart';
import 'stremio_player_screen.dart';
import 'valkery_desktop_title_bar.dart';

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
  bool _isOverviewExpanded = false;
  bool _onlyWebCompatible = kIsWeb;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _streamsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _isSeries = widget.media.isSeries;
    if (widget.media.episodes.isNotEmpty) {
      _selectedSeason = widget.media.seasons.firstOrNull ?? 1;
      final eps = widget.media.episodesForSeason(_selectedSeason);
      _selectedEpisode = eps.firstOrNull?.episode ?? 1;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToStreams() {
    final context = _streamsKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinator = ref.watch(sourceCoordinatorProvider);
    final isDesktopPlatform =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;

    // Watch full media details (synopsis, cast, director, runtime, episodes)
    final detailsAsync = ref.watch(
      stremioMediaDetailsProvider((
        id: widget.media.id,
        type: widget.media.type,
      )),
    );

    final media = detailsAsync.value ?? widget.media;
    final isSeries = media.isSeries || _isSeries;

    // Keep selected season/episode synced when full details load
    if (isSeries && media.episodes.isNotEmpty) {
      final availableSeasons = media.seasons;
      if (!availableSeasons.contains(_selectedSeason) && availableSeasons.isNotEmpty) {
        _selectedSeason = availableSeasons.first;
      }
      final episodesInSeason = media.episodesForSeason(_selectedSeason);
      if (!episodesInSeason.any((e) => e.episode == _selectedEpisode) && episodesInSeason.isNotEmpty) {
        _selectedEpisode = episodesInSeason.first.episode;
      }
    }

    final streamsAsync = ref.watch(
      stremioStreamsProvider((
        id: media.id,
        type: media.type,
        season: isSeries ? _selectedSeason : null,
        episode: isSeries ? _selectedEpisode : null,
      )),
    );

    var posterUrl = media.poster;
    if (posterUrl.isEmpty && media.id.startsWith('tt')) {
      posterUrl = 'https://images.metahub.space/poster/medium/${media.id}/img.jpg';
    }
    final bgUrl = media.background.isNotEmpty ? media.background : posterUrl;

    // Check watch history and library favorites
    final storage = ref.watch(stremioStorageProvider);
    final watchState = storage.getWatchState(media.id);
    final isFavorite = storage.isFavorite(media.id);
    final isPlayed = watchState != null && watchState.flaggedWatched > 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0D15),
      body: Column(
        children: [
          if (isDesktopPlatform)
            ValkeryDesktopTitleBar(title: '${media.name} - Valkery'),
          Expanded(
            child: Stack(
              children: [
                // 1. Full-bleed hero background with progressive vertical gradient fade (Fladder DetailScaffold style)
                if (bgUrl.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 520,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          resolveWebSafeImageUrl(bgUrl),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                        // Glass blur
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                        ),
                        // Progressive gradient into surface
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                const Color(0xFF0F0D15).withValues(alpha: 0.15),
                                const Color(0xFF0F0D15).withValues(alpha: 0.55),
                                const Color(0xFF0F0D15).withValues(alpha: 0.90),
                                const Color(0xFF0F0D15),
                              ],
                              stops: const [0.0, 0.30, 0.60, 0.85, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 2. Scrollable Content
                SafeArea(
                  top: !isDesktopPlatform,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(left: 28, right: 28, top: 12, bottom: 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top Navigation & Action Row (Fladder style)
                        _buildTopActionRow(context, media, isFavorite, isPlayed),
                        const SizedBox(height: 20),

                        // OverviewHeader (Poster, Title, Badges, Action Buttons)
                        _buildOverviewHeader(
                          context,
                          theme,
                          media,
                          posterUrl,
                          isSeries,
                          isCompact,
                          streamsAsync,
                          isFavorite,
                          isPlayed,
                        ),
                        const SizedBox(height: 28),

                        // Sinopsis / ExpandingText (Fladder style)
                        if (media.description.isNotEmpty) ...[
                          _buildSynopsisSection(media.description),
                          const SizedBox(height: 28),
                        ],

                        // Seasons & Episodes (Fladder's EpisodePosters carousel)
                        if (isSeries) ...[
                          _buildSeasonsAndEpisodesSection(media),
                          const SizedBox(height: 28),
                        ],

                        // Cast & Crew (Fladder's PeopleRow horizontal cards)
                        if (media.cast.isNotEmpty) ...[
                          _buildCastSection(media.cast),
                          const SizedBox(height: 28),
                        ],

                        // Directors & Writers
                        if (media.director.isNotEmpty) ...[
                          _buildCrewSection(media.director),
                          const SizedBox(height: 28),
                        ],

                        // Available Streams Section
                        Container(
                          key: _streamsKey,
                          child: _buildStreamsSection(streamsAsync, coordinator, media, isSeries),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Top Row with Back Button and Quick Action Buttons
  Widget _buildTopActionRow(
    BuildContext context,
    MediaItem media,
    bool isFavorite,
    bool isPlayed,
  ) {
    return Row(
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            media.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
        // Action buttons pill (Fladder style)
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  isFavorite ? IconsaxPlusBold.heart : IconsaxPlusLinear.heart,
                  size: 18,
                  color: isFavorite ? const Color(0xFF8B5CF6) : Colors.white70,
                ),
                tooltip: isFavorite ? 'En Biblioteca de Stremio' : 'Añadir a Biblioteca',
                onPressed: () => _toggleFavorite(media),
              ),
              IconButton(
                icon: Icon(
                  isPlayed ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.tick_circle,
                  size: 18,
                  color: isPlayed ? Colors.greenAccent : Colors.white70,
                ),
                tooltip: isPlayed ? 'Marcado como Visto' : 'Marcar como Visto',
                onPressed: () => _togglePlayed(media, isPlayed),
              ),
              IconButton(
                icon: const Icon(IconsaxPlusLinear.refresh, size: 18, color: Colors.white70),
                tooltip: 'Actualizar Datos',
                onPressed: () {
                  ref.invalidate(stremioMediaDetailsProvider((
                    id: widget.media.id,
                    type: widget.media.type,
                  )));
                  ref.invalidate(stremioStreamsProvider((
                    id: widget.media.id,
                    type: widget.media.type,
                    season: _isSeries ? _selectedSeason : null,
                    episode: _isSeries ? _selectedEpisode : null,
                  )));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// OverviewHeader (Poster with shadow, Title, Badges, Large Play Button)
  Widget _buildOverviewHeader(
    BuildContext context,
    ThemeData theme,
    MediaItem media,
    String posterUrl,
    bool isSeries,
    bool isCompact,
    AsyncValue<List<StreamCandidate>> streamsAsync,
    bool isFavorite,
    bool isPlayed,
  ) {
    final posterWidget = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        resolveWebSafeImageUrl(posterUrl),
        width: isCompact ? 130 : 180,
        height: isCompact ? 195 : 270,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: isCompact ? 130 : 180,
          height: isCompact ? 195 : 270,
          color: Colors.white12,
          child: const Icon(IconsaxPlusLinear.image, size: 48, color: Colors.white30),
        ),
      ),
    );

    final infoWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          media.name,
          style: TextStyle(
            fontSize: isCompact ? 22 : 30,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),

        // Badges row (Type, Year, Rating, Runtime)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Media Type Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.6)),
              ),
              child: Text(
                media.type == 'series' || media.type == 'anime' ? 'SERIE' : 'PELÍCULA',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFFC4B5FD),
                ),
              ),
            ),
            // Release Info / Year
            if (media.releaseInfo.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text(
                      media.releaseInfo,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            // IMDb Rating
            if (media.imdbRating.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 13, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      media.imdbRating,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
              ),
            // Runtime
            if (media.runtime.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 12, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text(
                      media.runtime,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Genres wrapped
        if (media.genres.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: media.genres.map((g) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Text(
                  g,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 20),

        // Main Action Buttons Row (Reproducir, Fuentes, Favoritos, Visto)
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Big Primary "Reproducir" button (Fladder MediaPlayButton style)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 6,
                shadowColor: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
              ),
              icon: const Icon(IconsaxPlusBold.play, size: 20),
              label: Text(
                isSeries ? 'Reproducir T$_selectedSeason E$_selectedEpisode' : 'Reproducir',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              onPressed: () {
                final streams = streamsAsync.value;
                if (streams != null && streams.isNotEmpty) {
                  // Direct play best available stream
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StremioPlayerScreen(
                        media: media,
                        stream: streams.first,
                        season: isSeries ? _selectedSeason : null,
                        episode: isSeries ? _selectedEpisode : null,
                      ),
                    ),
                  );
                } else {
                  // Scroll down to streams section
                  _scrollToStreams();
                }
              },
            ),

            // Secondary "Ver Fuentes" button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(IconsaxPlusLinear.link_circle, size: 18),
              label: const Text('Fuentes y Calidad'),
              onPressed: _scrollToStreams,
            ),
          ],
        ),
      ],
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              posterWidget,
              const SizedBox(width: 16),
              Expanded(child: infoWidget),
            ],
          ),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          posterWidget,
          const SizedBox(width: 28),
          Expanded(child: infoWidget),
        ],
      );
    }
  }

  /// Synopsis Section with Expandable Text (Fladder ExpandingText style)
  Widget _buildSynopsisSection(String synopsis) {
    const maxChars = 240;
    final canExpand = synopsis.length > maxChars;
    final displayText = (!_isOverviewExpanded && canExpand)
        ? '${synopsis.substring(0, maxChars)}...'
        : synopsis;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(IconsaxPlusLinear.document_text, size: 18, color: Color(0xFF8B5CF6)),
              SizedBox(width: 8),
              Text(
                'Sinopsis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.topLeft,
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.55,
              ),
            ),
          ),
          if (canExpand) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _isOverviewExpanded = !_isOverviewExpanded),
              child: Text(
                _isOverviewExpanded ? 'Mostrar menos' : 'Mostrar más',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC4B5FD),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Seasons and Episodes Section (Fladder's EpisodePosters style)
  Widget _buildSeasonsAndEpisodesSection(MediaItem media) {
    final seasons = media.seasons;
    final sortedSeasons = seasons.isNotEmpty ? seasons : [1];
    final episodes = media.episodesForSeason(_selectedSeason);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(IconsaxPlusBold.folder_2, size: 20, color: Color(0xFF8B5CF6)),
                SizedBox(width: 8),
                Text(
                  'Episodios',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Text(
              '${episodes.length} episodios en Temporada $_selectedSeason',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Season Selector Chips
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sortedSeasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final s = sortedSeasons[index];
              final isSelected = s == _selectedSeason;
              final label = s == 0 ? 'Especiales' : 'Temporada $s';

              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                selectedColor: const Color(0xFF8B5CF6),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF8B5CF6)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedSeason = s;
                      final eps = media.episodesForSeason(s);
                      if (eps.isNotEmpty) {
                        _selectedEpisode = eps.first.episode;
                      } else {
                        _selectedEpisode = 1;
                      }
                    });
                  }
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Horizontal Carousel of Episode Cards (Fladder EpisodePosters style)
        if (episodes.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: episodes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final ep = episodes[index];
                final isSelected = ep.episode == _selectedEpisode;
                return _buildEpisodeCard(ep, isSelected, media);
              },
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'No hay episodios listados para esta temporada.',
                style: TextStyle(color: Colors.white60),
              ),
            ),
          ),
      ],
    );
  }

  /// Individual Episode Card (16:9 thumbnail, badge, title, overview snippet, play button)
  Widget _buildEpisodeCard(EpisodeItem ep, bool isSelected, MediaItem media) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedEpisode = ep.episode);
      },
      child: Container(
        width: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF8B5CF6)
                : Colors.white.withValues(alpha: 0.12),
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 16:9 Thumbnail with Overlay Badge & Play Icon
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ep.thumbnail.isNotEmpty)
                    Image.network(
                      resolveWebSafeImageUrl(ep.thumbnail),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildEpisodePlaceholder(ep),
                    )
                  else
                    _buildEpisodePlaceholder(ep),
                  // Gradient shadow on thumbnail
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                  // Episode Tag Pill (Top Left)
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
                        ep.code,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Play button hover/action (Center)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF8B5CF6)
                            : Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        IconsaxPlusBold.play,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Episode Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ep.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFFC4B5FD) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (ep.overview.isNotEmpty)
                    Text(
                      ep.overview,
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

  Widget _buildEpisodePlaceholder(EpisodeItem ep) {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined, size: 28, color: Colors.white38),
            const SizedBox(height: 4),
            Text(
              ep.code,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  /// Cast Section (Fladder's PeopleRow horizontal cards)
  Widget _buildCastSection(List<String> cast) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(IconsaxPlusBold.profile_2user, size: 20, color: Color(0xFF8B5CF6)),
            SizedBox(width: 8),
            Text(
              'Reparto Principal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final actor = cast[index];
              final initials = _getInitials(actor);

              return SizedBox(
                width: 90,
                child: Column(
                  children: [
                    // Avatar Card (Fladder style)
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFC4B5FD),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      actor,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Directors Section
  Widget _buildCrewSection(List<String> directors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(IconsaxPlusLinear.video, size: 18, color: Color(0xFF8B5CF6)),
            SizedBox(width: 8),
            Text(
              'Dirección y Creación',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: directors.map((dir) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                dir,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Streams Section with Source, Resolution, Seeders, Size, Play & Download
  Widget _buildStreamsSection(
    AsyncValue<List<StreamCandidate>> asyncStreams,
    SourceCoordinatorState coordinator,
    MediaItem media,
    bool isSeries,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              IconsaxPlusBold.link_circle,
              size: 20,
              color: Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSeries
                    ? 'Fuentes para Temporada $_selectedSeason • Episodio $_selectedEpisode'
                    : 'Fuentes y Streams Disponibles',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Filter chips: Web Ready vs All
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilterChip(
              selected: !_onlyWebCompatible,
              avatar: const Icon(Icons.playlist_play, size: 14, color: Colors.white70),
              label: const Text('Todas las fuentes (VLC)'),
              labelStyle: TextStyle(
                fontSize: 12,
                color: !_onlyWebCompatible ? Colors.white : Colors.white70,
              ),
              backgroundColor: Colors.white10,
              selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
              checkmarkColor: Colors.white,
              onSelected: (val) {
                if (val) setState(() => _onlyWebCompatible = false);
              },
            ),
            FilterChip(
              selected: _onlyWebCompatible,
              avatar: const Icon(Icons.language, size: 14, color: Colors.greenAccent),
              label: const Text('Solo Web Ready (Navegador)'),
              labelStyle: TextStyle(
                fontSize: 12,
                color: _onlyWebCompatible ? Colors.white : Colors.white70,
              ),
              backgroundColor: Colors.white10,
              selectedColor: Colors.green.withValues(alpha: 0.35),
              checkmarkColor: Colors.greenAccent,
              onSelected: (val) {
                if (val) setState(() => _onlyWebCompatible = true);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        asyncStreams.when(
          loading: () => Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                  SizedBox(height: 14),
                  Text(
                    'Buscando fuentes en Torrentio y Addons...',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          error: (e, _) => Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'Error al consultar fuentes: $e',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
          data: (streams) {
            if (streams.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.wifi_off_outlined, size: 36, color: Colors.white38),
                      SizedBox(height: 10),
                      Text(
                        'No se encontraron streams disponibles para este contenido.',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Verifica que el motor Stremio esté activo o configura más addons en Ajustes.',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              );
            }

            final displayStreams = _onlyWebCompatible
                ? streams.where((s) => s.isWebCompatible).toList()
                : streams;

            if (displayStreams.isEmpty && _onlyWebCompatible) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.info_outline, size: 32, color: Colors.orangeAccent),
                      const SizedBox(height: 10),
                      const Text(
                        'No hay fuentes con códec nativo para navegador (MP4/H.264) para este contenido.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hay ${streams.length} fuentes en alta definición (MKV / 4K / HDR) que puedes abrir con VLC.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.playlist_play, size: 16),
                        label: const Text('Ver todas las fuentes (VLC)'),
                        onPressed: () => setState(() => _onlyWebCompatible = false),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayStreams.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final stream = displayStreams[index];
                return _buildStreamTile(stream, coordinator, media);
              },
            );
          },
        ),
      ],
    );
  }

  /// Individual Stream Card
  Widget _buildStreamTile(
    StreamCandidate stream,
    SourceCoordinatorState coordinator,
    MediaItem media,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF8B5CF6)),
                      ),
                      child: Text(
                        stream.addonName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFC4B5FD),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stream.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  stream.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Quality badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stream.quality,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Web compatibility badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: stream.isWebCompatible
                            ? Colors.green.withValues(alpha: 0.22)
                            : Colors.orange.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: stream.isWebCompatible ? Colors.greenAccent : Colors.orangeAccent,
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            stream.isWebCompatible ? Icons.check_circle_outline : Icons.open_in_new,
                            size: 10,
                            color: stream.isWebCompatible ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            stream.isWebCompatible ? 'Web Ready' : 'VLC / Ext',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: stream.isWebCompatible ? Colors.greenAccent : Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Seeders
                    if (stream.seeders > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people, size: 12, color: Colors.greenAccent),
                          const SizedBox(width: 3),
                          Text(
                            '${stream.seeders} seeds',
                            style: const TextStyle(fontSize: 11, color: Colors.greenAccent),
                          ),
                        ],
                      ),
                    // File Size
                    if (stream.size.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sd_storage, size: 12, color: Colors.white60),
                          const SizedBox(width: 3),
                          Text(
                            stream.size,
                            style: const TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Download Offline Button
          IconButton(
            tooltip: 'Descargar Offline',
            icon: const Icon(IconsaxPlusLinear.document_download, color: Colors.white70),
            onPressed: () async {
              try {
                final serverUrl = ref.read(sourceCoordinatorProvider).stremioServerUrl;
                await ref.read(stremioOfflineDownloadManagerProvider).startDownload(
                  media: media,
                  stream: stream,
                  serverUrl: serverUrl,
                  season: _isSeries ? _selectedSeason : null,
                  episode: _isSeries ? _selectedEpisode : null,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Descarga iniciada: ${media.name}'),
                      backgroundColor: const Color(0xFF8B5CF6),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al iniciar descarga: $e')),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 6),
          // Play Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(IconsaxPlusBold.play, size: 16),
            label: const Text('Ver'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StremioPlayerScreen(
                    media: media,
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
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.substring(0, (parts.first.length >= 2 ? 2 : 1)).toUpperCase();
    }
    return 'AC';
  }

  Future<void> _toggleFavorite(MediaItem media) async {
    final storage = ref.read(stremioStorageProvider);
    final api = ref.read(stremioApiServiceProvider);
    final authKey = storage.authKey ?? '';
    final wasInLib = storage.isInLibrary(media.id);

    if (wasInLib) {
      await api.removeFromLibrary(authKey, media.id);
    } else {
      await api.addToLibrary(authKey, media);
    }
    ref.invalidate(stremioWatchHistoryProvider);

    if (mounted) {
      final isNowInLib = storage.isInLibrary(media.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNowInLib
                ? 'Añadido a la biblioteca de Stremio'
                : 'Quitado de la biblioteca de Stremio',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {});
    }
  }

  Future<void> _togglePlayed(MediaItem media, bool currentStatus) async {
    final storage = ref.read(stremioStorageProvider);
    final api = ref.read(stremioApiServiceProvider);
    final key = storage.authKey;

    final existing = storage.getWatchState(media.id);
    final videoId = (_isSeries && media.episodes.isNotEmpty)
        ? '${media.id}:$_selectedSeason:$_selectedEpisode'
        : media.id;

    final updated = (existing ??
        LibraryWatchState(
          id: media.id,
          name: media.name,
          type: media.type,
          poster: media.poster,
          videoId: videoId,
          lastWatched: DateTime.now().toUtc(),
        ))
        .copyWith(flaggedWatched: currentStatus ? 0 : 1);

    if (key != null && key.isNotEmpty) {
      await api.syncWatchState(key, updated);
    } else {
      await storage.upsertWatchState(updated);
    }
    setState(() {});
  }
}
