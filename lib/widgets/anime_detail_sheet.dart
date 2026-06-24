import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as ypf;
import '../models/anime.dart';
import '../services/anime_like_service.dart';
import '../services/trailer_service.dart';

// Shared detail bottom sheet used by both LikedAnimeScreen and
// WatchlistedScreen. Replaces the old duplicated _showAnimeDetailDialog.
void showAnimeDetailSheet(BuildContext context, Anime anime) {
  // Guard against stacking sheets: if one is already open (e.g. the user
  // tapped a card while a previous sheet was still closing/animating),
  // pop it first so we never end up with multiple _AnimeDetailSheet
  // instances alive at once.
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.popUntil((route) => route is! PopupRoute);
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnimeDetailSheet(anime: anime),
  );
}

class _AnimeDetailSheet extends StatefulWidget {
  final Anime anime;
  const _AnimeDetailSheet({required this.anime});

  @override
  State<_AnimeDetailSheet> createState() => _AnimeDetailSheetState();
}

class _AnimeDetailSheetState extends State<_AnimeDetailSheet> {
  String? _trailerKey;
  bool _trailerLoading = true;
  bool _trailerVisible = false;
  ypf.YoutubePlayerController? _ytController;

  @override
  void initState() {
    super.initState();
    _loadTrailer();
  }

  // Builds the controller only once the user taps "Watch Trailer". Starts
  // unmuted immediately, since this is a direct user-gesture response —
  // the most reliable way to get the WebView to allow sound right away.
  void _showTrailer() {
    debugPrint('[Trailer] _showTrailer TAPPED. trailerKey=$_trailerKey');
    if (_trailerKey == null) {
      debugPrint('[Trailer] _showTrailer bailed: no trailerKey.');
      return;
    }
    if (_ytController == null) {
      _ytController = ypf.YoutubePlayerController.fromVideoId(
        videoId: _trailerKey!,
        autoPlay: true,
        params: const ypf.YoutubePlayerParams(
          mute: false,
          showControls: false,
          showFullscreenButton: false,
          strictRelatedVideos: true,
          playsInline: true,
          loop: true,
          enableJavaScript: true,
        ),
      );
      _ytController!.listen((value) {
        debugPrint('[Trailer] controller state update: playerState=${value.playerState} error=${value.error}');
      });
      debugPrint('[Trailer] _showTrailer: created controller $_ytController');
    } else {
      // Already built once before (e.g. user closed and reopened) — just
      // resume playback with sound.
      _ytController!.unMute();
      _ytController!.playVideo();
    }
    setState(() => _trailerVisible = true);
  }

  void _hideTrailer() {
    debugPrint('[Trailer] _hideTrailer TAPPED.');
    _ytController?.pauseVideo();
    setState(() => _trailerVisible = false);
  }

  @override
  void dispose() {
    _ytController?.close();
    super.dispose();
  }

  Future<void> _loadTrailer() async {
    debugPrint('[Trailer] _loadTrailer start for malId=${widget.anime.malId} isMovie=${widget.anime.isMovie} (sheet hash=$hashCode)');
    final key = await TrailerService.instance.fetchTrailerKey(
      malId: widget.anime.malId,
      isMovie: widget.anime.isMovie,
      isAnilist: widget.anime.source == AnimeSource.anilist,
    );
    debugPrint('[Trailer] fetchTrailerKey resolved: $key (sheet hash=$hashCode)');
    if (!mounted) {
      debugPrint('[Trailer] _loadTrailer: widget unmounted before setState, aborting. (sheet hash=$hashCode)');
      return;
    }
    setState(() {
      _trailerKey = key;
      _trailerLoading = false;
    });
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Streaming suggestions — search links so users can find it regardless
  // of region availability. These open the platform's search for the title.
  List<_StreamingLink> get _streamingLinks {
    final title = Uri.encodeComponent(widget.anime.title);
    if (widget.anime.isMovie) {
      return [
        _StreamingLink('Netflix', 'https://www.netflix.com/search?q=$title', const Color(0xFFE50914)),
        _StreamingLink('Prime Video', 'https://www.amazon.com/s?k=$title&i=instant-video', const Color(0xFF00A8E1)),
        _StreamingLink('Disney+', 'https://www.disneyplus.com/search?q=$title', const Color(0xFF113CCF)),
        _StreamingLink('Apple TV+', 'https://tv.apple.com/search?term=$title', const Color(0xFF555555)),
      ];
    } else {
      return [
        _StreamingLink('Crunchyroll', 'https://www.crunchyroll.com/search?q=$title', const Color(0xFFF47521)),
        _StreamingLink('Netflix', 'https://www.netflix.com/search?q=$title', const Color(0xFFE50914)),
        _StreamingLink('Funimation', 'https://www.funimation.com/search/?q=$title', const Color(0xFF410099)),
        _StreamingLink('Prime Video', 'https://www.amazon.com/s?k=$title&i=instant-video', const Color(0xFF00A8E1)),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final anime = widget.anime;
    final remark = AnimeLikeService.instance.getRemark(anime.uniqueKey);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2C2831),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Poster / trailer player ──────────────────────
                      Stack(
                        children: [
                          // Poster image (always present underneath)
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              anime.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.white10,
                                child: const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.white30,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                          if (_ytController != null && _trailerVisible)
                            Builder(
                              builder: (_) {
                                debugPrint('[Trailer] BUILD: mounting YoutubePlayerScaffold, controller=$_ytController');
                                return AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: ypf.YoutubePlayerScaffold(
                                    controller: _ytController!,
                                    builder: (context, player) => player,
                                  ),
                                );
                              },
                            ),
                          // Close trailer button
                          if (_trailerVisible)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: _hideTrailer,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          // Watch Trailer button — centered over the poster
                          if (!_trailerVisible)
                            Positioned.fill(
                              child: Center(
                                child: _trailerLoading
                                    ? const SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white54,
                                        ),
                                      )
                                    : _trailerKey != null
                                        ? GestureDetector(
                                            onTap: _showTrailer,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.65),
                                                borderRadius: BorderRadius.circular(30),
                                                border: Border.all(
                                                  color: Colors.white30,
                                                ),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.play_circle_outline,
                                                    color: Colors.white,
                                                    size: 22,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Watch Trailer',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black45,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Text(
                                              'No trailer available',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                              ),
                            ),
                        ],
                      ),

                      // ── Info section ─────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              anime.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            if (anime.score != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      size: 16, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    anime.score!.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      anime.isMovie ? 'Movie' : 'Anime',
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (anime.genres.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final genre in anime.genres)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: colorScheme.primary.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        genre,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              anime.synopsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Colors.white70,
                                height: 1.5,
                              ),
                            ),

                            // ── Remark (Watchlisted only) ─────────────
                            if (remark != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.primary.withOpacity(0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.sticky_note_2_outlined,
                                            size: 14, color: colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Your remark',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      remark,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        color: Colors.white,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // ── Where to watch ────────────────────────
                            const SizedBox(height: 20),
                            const Text(
                              'Where to watch',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Search on these platforms — availability varies by region.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white38,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final link in _streamingLinks)
                                  GestureDetector(
                                    onTap: () => _launch(link.url),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: link.color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: link.color.withOpacity(0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.open_in_new,
                                            size: 13,
                                            color: link.color,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            link.name,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: link.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StreamingLink {
  final String name;
  final String url;
  final Color color;
  const _StreamingLink(this.name, this.url, this.color);
}