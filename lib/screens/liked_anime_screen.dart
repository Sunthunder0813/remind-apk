import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/anime_like_service.dart';
import '../widgets/anime_detail_sheet.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/alphabet_index.dart';
import 'notes_screen.dart';

void _showAnimeDetailDialog(BuildContext context, Anime anime) {
  showAnimeDetailSheet(context, anime);
}

// Shows everything the user liked on Discover as one flat grid. Genre
// filtering is multi-select via a Discover-style bottom sheet (reached
// through the filter icon), sourced from the FULL genre catalog for the
// current source filter — not just genres present on liked items — so
// genres like "Isekai" show up even with zero liked items in that genre.
// Long-press a card opens an actions menu: move it to the Watchlist (a
// separate persisted list, reached via the center FAB) or remove it from
// Liked entirely.
class LikedAnimeScreen extends StatefulWidget {
  final String sourceFilter;
  // Multi-select now, mirroring Discover's genre filter UX.
  final Set<String> selectedGenres;
  // Full genre catalog for the current source (Anime/Movie/All), owned by
  // the parent (HomeScreen) — same pattern Discover uses for its own
  // genre lists.
  final List<String> availableGenres;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<Set<String>> onGenresChanged;

  const LikedAnimeScreen({
    super.key,
    required this.sourceFilter,
    required this.selectedGenres,
    required this.availableGenres,
    required this.onSourceChanged,
    required this.onGenresChanged,
  });

  @override
  State<LikedAnimeScreen> createState() => _LikedAnimeScreenState();
}

class _LikedAnimeScreenState extends State<LikedAnimeScreen> {
  List<Anime> _filtered(List<Anime> liked) {
    return liked.where((a) {
      final matchesSource = widget.sourceFilter == 'All'
          ? true
          : widget.sourceFilter == 'Movie'
              ? a.isMovie
              : !a.isMovie;
      final matchesGenre = widget.selectedGenres.isEmpty
          ? true
          : widget.selectedGenres.contains('Other')
              ? (a.genres.isEmpty || a.genres.any((g) => widget.selectedGenres.contains(g)))
              : a.genres.any((g) => widget.selectedGenres.contains(g));
      return matchesSource && matchesGenre;
    }).toList();
  }

  // Compact label for the status-row chip, e.g. "Action", "Action +1" —
  // mirrors DiscoverScreen's _genreSummaryLabel.
  String get _genreSummaryLabel {
    final selected = widget.selectedGenres.toList();
    if (selected.isEmpty) return '';
    if (selected.length == 1) return selected.first;
    return '${selected.first} +${selected.length - 1}';
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

  // Discover-style genre filter bottom sheet — multi-select checkboxes
  // over the FULL catalog (widget.availableGenres), not just genres
  // present on liked items. Includes the same A-Z quick-jump rail as
  // Discover's filter sheet, with iOS-style press-and-drag support.
  Future<void> _openGenreFilterSheet() async {
    var working = {...widget.selectedGenres};
    final scrollController = ScrollController();
    const double rowHeight = 56;

    final Map<String, double> letterOffsets = {};
    for (int i = 0; i < widget.availableGenres.length; i++) {
      final name = widget.availableGenres[i];
      if (name.isEmpty) continue;
      final letter = name[0].toUpperCase();
      if (!letterOffsets.containsKey(letter)) {
        letterOffsets[letter] = i * rowHeight;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filter by genre',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          if (working.isNotEmpty)
                            TextButton(
                              onPressed: () => setSheetState(() => working.clear()),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: widget.availableGenres.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'No genres available yet.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    controller: scrollController,
                                    itemExtent: rowHeight,
                                    itemCount: widget.availableGenres.length,
                                    itemBuilder: (context, index) {
                                      final genre = widget.availableGenres[index];
                                      final isSelected = working.contains(genre);
                                      return CheckboxListTile(
                                        value: isSelected,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        activeColor: Theme.of(context).colorScheme.primary,
                                        title: Text(genre),
                                        onChanged: (checked) {
                                          setSheetState(() {
                                            if (checked == true) {
                                              working.add(genre);
                                            } else {
                                              working.remove(genre);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                                AlphabetIndex(
                                  letterOffsets: letterOffsets,
                                  onLetterTap: (offset) {
                                    if (!scrollController.hasClients) return;
                                    final maxScroll =
                                        scrollController.position.maxScrollExtent;
                                    scrollController.jumpTo(
                                      offset.clamp(0.0, maxScroll),
                                    );
                                  },
                                ),
                              ],
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            working.isEmpty
                                ? 'Show all liked'
                                : 'Apply (${working.length} selected)',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(scrollController.dispose);

    widget.onGenresChanged(working);
  }

  @override
  Widget build(BuildContext context) {
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

        return Column(
          children: [
            // ── Slim status row — liked count + genre filter chip + layout ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} liked',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  if (widget.selectedGenres.isNotEmpty)
                    InputChip(
                      label: Text(_genreSummaryLabel),
                      visualDensity: VisualDensity.compact,
                      onPressed: _openGenreFilterSheet,
                      onDeleted: () => widget.onGenresChanged({}),
                      deleteIcon: const Icon(Icons.close, size: 14),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.filter_alt_outlined),
                    tooltip: 'Filter by genre',
                    onPressed: _openGenreFilterSheet,
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Layout settings',
                    onPressed: () => _openColumnSettings(context),
                  ),
                ],
              ),
            ),

            if (filtered.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 56, color: Colors.grey.shade500),
                      const SizedBox(height: 12),
                      Text(
                        'No liked items match this filter',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else
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