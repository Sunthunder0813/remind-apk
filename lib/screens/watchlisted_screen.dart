import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/anime_like_service.dart';
import '../widgets/skeleton_loader.dart';
import 'notes_screen.dart';

// Read-only anime detail popup — image, title, score, genres, synopsis.
// Duplicated identically in liked_anime_screen.dart so each screen is
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
                    if (AnimeLikeService.instance.getRemark(anime.uniqueKey) != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.sticky_note_2_outlined,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Your remark',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.primary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AnimeLikeService.instance.getRemark(anime.uniqueKey)!,
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

// Full-screen page showing everything moved to the Watchlist (reached via
// the center FAB on the Liked Anime tab). Mirrors LikedAnimeScreen's
// layout (genre chips + grid + column settings) but reads/writes the
// watchlisted list instead of the liked list, and long-press here removes
// from the watchlist entirely rather than moving it anywhere else.
class WatchlistedScreen extends StatefulWidget {
  const WatchlistedScreen({super.key});

  @override
  State<WatchlistedScreen> createState() => _WatchlistedScreenState();
}

class _WatchlistedScreenState extends State<WatchlistedScreen> {
  String? _selectedGenre; // null = "All"
  String _sourceFilter = 'All'; // 'All', 'Anime', 'Movie'

  List<String> _allGenres(List<Anime> list) {
    final set = <String>{};
    for (final anime in list) {
      if (anime.genres.isEmpty) {
        set.add('Other');
      } else {
        set.addAll(anime.genres);
      }
    }
    final result = set.toList()..sort();
    return result;
  }

  List<Anime> _filtered(List<Anime> list) {
    return list.where((a) {
      final matchesSource = _sourceFilter == 'All'
          ? true
          : _sourceFilter == 'Movie'
              ? a.isMovie
              : !a.isMovie;
      final matchesGenre = _selectedGenre == null
          ? true
          : _selectedGenre == 'Other'
              ? a.genres.isEmpty
              : a.genres.contains(_selectedGenre);
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

  // Long-press opens a small actions menu: edit remarks, or remove.
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
                leading: const Icon(Icons.edit_note, color: Colors.white),
                title: const Text('Add / Edit Remarks', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'remarks'),
              ),
              if (AnimeLikeService.instance.getRemark(anime.uniqueKey) != null)
                ListTile(
                  leading: const Icon(Icons.note_alt_outlined, color: Colors.white),
                  title: const Text('Clear Remarks', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, 'clear_remarks'),
                ),
              ListTile(
                leading: const Icon(Icons.favorite_outline, color: Colors.white),
                title: const Text('Move to Liked', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'remarks') {
      _editRemarks(anime);
    } else if (action == 'clear_remarks') {
      _clearRemarks(anime);
    } else if (action == 'remove') {
      _moveToLiked(anime);
    }
  }

  // Clears the remark immediately, with an Undo toast that restores it.
  void _clearRemarks(Anime anime) {
    final previousRemark = AnimeLikeService.instance.getRemark(anime.uniqueKey);
    AnimeLikeService.instance.setRemark(anime.uniqueKey, null);

    if (!mounted) return;
    showUndoToast(
      context,
      'Remark cleared',
      onUndo: () {
        AnimeLikeService.instance.setRemark(anime.uniqueKey, previousRemark);
      },
    );
  }

  // Opens a text field pre-filled with the current remark (if any) and
  // saves it via AnimeLikeService on confirm.
  Future<void> _editRemarks(Anime anime) async {
    final controller = TextEditingController(
      text: AnimeLikeService.instance.getRemark(anime.uniqueKey) ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remarks'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'e.g. Watch after finishing season 1',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      AnimeLikeService.instance.setRemark(anime.uniqueKey, controller.text);
    }
  }

  // Moves the anime back to Liked immediately, with an Undo toast.
  // No confirmation dialog — Undo is the safety net.
  void _moveToLiked(Anime anime) {
    AnimeLikeService.instance.moveToLiked(anime);

    if (!mounted) return;
    showUndoToast(
      context,
      '"${anime.title}" moved to Liked',
      onUndo: () {
        AnimeLikeService.instance.moveToWatchlist(anime);
      },
    );
  }

  Widget _buildSourceToggle(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final label in ['All', 'Anime', 'Movie'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _sourceFilter = label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _sourceFilter == label
                        ? colorScheme.primary
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _sourceFilter == label
                          ? Colors.white
                          : Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
              selected: _selectedGenre == null,
              onSelected: (_) => setState(() => _selectedGenre = null),
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: _selectedGenre == null ? Colors.white : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
          for (final genre in genres)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(genre),
                selected: _selectedGenre == genre,
                onSelected: (_) => setState(
                  () => _selectedGenre = _selectedGenre == genre ? null : genre,
                ),
                selectedColor: colorScheme.primary,
                labelStyle: TextStyle(
                  color: _selectedGenre == genre ? Colors.white : Colors.black87,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlisted'),
      ),
      body: ListenableBuilder(
        listenable: AnimeLikeService.instance,
        builder: (context, _) {
          final watchlisted = AnimeLikeService.instance.watchlisted;
          final columns = AnimeLikeService.instance.gridColumns;

          if (watchlisted.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No watchlisted items yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Long-press a liked item to add it here',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                ],
              ),
            );
          }

          final genres = _allGenres(watchlisted);
          final filtered = _filtered(watchlisted);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${watchlisted.length} watchlisted',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune),
                      tooltip: 'Layout settings',
                      onPressed: () => _openColumnSettings(context),
                    ),
                  ],
                ),
              ),

              _buildSourceToggle(colorScheme),
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
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
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
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Builder(
                                      builder: (context) {
                                        final hasRemark =
                                            AnimeLikeService.instance.getRemark(anime.uniqueKey) != null;
                                        return Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: hasRemark ? colorScheme.primary : Colors.black54,
                                            borderRadius: BorderRadius.circular(8),
                                            border: hasRemark
                                                ? Border.all(color: Colors.white, width: 1.5)
                                                : null,
                                            boxShadow: hasRemark
                                                ? [
                                                    BoxShadow(
                                                      color: colorScheme.primary.withOpacity(0.6),
                                                      blurRadius: 8,
                                                      spreadRadius: 1,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Icon(
                                            hasRemark ? Icons.sticky_note_2 : Icons.bookmark,
                                            size: hasRemark ? 15 : 14,
                                            color: Colors.white,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
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
      ),
    );
  }
}