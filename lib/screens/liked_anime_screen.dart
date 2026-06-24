import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/anime_like_service.dart';
import '../widgets/skeleton_loader.dart';
import 'notes_screen.dart';

// Read-only anime detail popup — image, title, score, genres, synopsis.
// Duplicated identically in watchlisted_screen.dart so each screen is
// self-contained rather than depending on a shared host file for this.
void _showAnimeDetailDialog(BuildContext context, Anime anime) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: const Color(0xFF2C2831),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: AspectRatio(
                  aspectRatio: 0.7,
                  child: Image.network(
                    anime.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white10,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported, color: Colors.white30),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (anime.score != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            anime.score!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                genre,
                                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
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
                    ],
                ),
              ),
            ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Shows everything the user liked on Discover as one flat grid, with
// genre chips at the top to filter the view. Long-press a card to open
// an actions menu with two choices: move it to the Watchlist (a separate
// persisted list, reached via the center FAB) or remove it from Liked
// entirely.
class LikedAnimeScreen extends StatefulWidget {
  final String sourceFilter;
  final String? selectedGenre;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String?> onGenreChanged;

  const LikedAnimeScreen({
    super.key,
    required this.sourceFilter,
    required this.selectedGenre,
    required this.onSourceChanged,
    required this.onGenreChanged,
  });

  @override
  State<LikedAnimeScreen> createState() => _LikedAnimeScreenState();
}

class _LikedAnimeScreenState extends State<LikedAnimeScreen> {

  List<String> _allGenres(List<Anime> liked) {
    final set = <String>{};
    for (final anime in liked) {
      if (anime.genres.isEmpty) {
        set.add('Other');
      } else {
        set.addAll(anime.genres);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Anime> _filtered(List<Anime> liked) {
    return liked.where((a) {
      final matchesSource = widget.sourceFilter == 'All'
          ? true
          : widget.sourceFilter == 'Movie'
              ? a.isMovie
              : !a.isMovie;
      final matchesGenre = widget.selectedGenre == null
          ? true
          : widget.selectedGenre == 'Other'
              ? a.genres.isEmpty
              : a.genres.contains(widget.selectedGenre);
      return matchesSource && matchesGenre;
    }).toList();
  }

  void _openColumnSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final columns = AnimeLikeService.instance.gridColumns;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cards per row',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Drag to change the grid layout instantly',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: columns.toDouble(),
                          min: 2,
                          max: 5,
                          divisions: 3,
                          label: '$columns',
                          onChanged: (value) {
                            AnimeLikeService.instance.gridColumns = value.round();
                            setSheetState(() {});
                          },
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$columns',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Long-press opens a small actions menu with two choices.
  Future<void> _showAnimeActions(Anime anime) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF2C2831),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
                title: const Text('Add to Watchlist', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'watchlist'),
              ),
              ListTile(
                leading: const Icon(Icons.heart_broken_outlined, color: Colors.white),
                title: const Text('Remove from Liked', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'watchlist') {
      _moveToWatchlist(anime);
    } else if (action == 'remove') {
      _removeFromLiked(anime);
    }
  }

  // Removes the anime from Liked immediately, with an Undo toast
  // that re-likes it if tapped. No confirmation dialog — Undo is the
  // safety net.
  void _removeFromLiked(Anime anime) {
    AnimeLikeService.instance.unlike(anime.uniqueKey);

    if (!mounted) return;
    showUndoToast(
      context,
      '"${anime.title}" removed from Liked',
      onUndo: () {
        AnimeLikeService.instance.like(anime);
      },
    );
  }

  // Moves to Watchlist immediately, with an Undo toast. No
  // confirmation dialog — Undo is the safety net.
  void _moveToWatchlist(Anime anime) {
    AnimeLikeService.instance.moveToWatchlist(anime);

    if (!mounted) return;
    showUndoToast(
      context,
      '"${anime.title}" moved to Watchlist',
      onUndo: () {
        AnimeLikeService.instance.removeFromWatchlist(anime.uniqueKey);
        AnimeLikeService.instance.like(anime);
      },
    );
  }

  Widget _buildGenreChips(List<String> genres, ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: widget.selectedGenre == null,
              onSelected: (_) => widget.onGenreChanged(null),
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: widget.selectedGenre == null ? Colors.white : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
          for (final genre in genres)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(genre),
                selected: widget.selectedGenre == genre,
                onSelected: (_) => widget.onGenreChanged(
                  widget.selectedGenre == genre ? null : genre,
                ),
                selectedColor: colorScheme.primary,
                labelStyle: TextStyle(
                  color: widget.selectedGenre == genre ? Colors.white : Colors.black87,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: AnimeLikeService.instance,
      builder: (context, _) {
        final liked = AnimeLikeService.instance.liked;
        final columns = AnimeLikeService.instance.gridColumns;

        if (liked.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No liked items yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Swipe right on Discover to save anime or movies',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                ),
              ],
            ),
          );
        }

        final filtered = _filtered(liked);
        final genres = _allGenres(filtered);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    '${liked.length} liked',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Layout settings',
                    onPressed: () => _openColumnSettings(context),
                  ),
                ],
              ),
            ),

            _buildGenreChips(genres, colorScheme),
            const SizedBox(height: 8),

            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.62,
                ),
                itemBuilder: (context, i) {
                  final anime = filtered[i];
                  return GestureDetector(
                    onTap: () => _showAnimeDetailDialog(context, anime),
                    onLongPress: () => _showAnimeActions(anime),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Image.network(
                              anime.imageUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const SkeletonBox();
                              },
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Text(
                              anime.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}