import 'package:flutter/material.dart';

// Vertical A-Z quick-jump index running down the right edge of a genre
// list, like the iOS Contacts list. Supports both:
//  - Tap a letter to jump straight to it
//  - Press and drag up/down the whole rail to continuously jump as the
//    finger moves, exactly like iOS Contacts' side index
// Letters with no matching genre are dimmed and not tappable/draggable to.
// Shared between DiscoverScreen and LikedAnimeScreen so both genre filter
// sheets feel consistent.
class AlphabetIndex extends StatefulWidget {
  final Map<String, double> letterOffsets;
  final void Function(double offset) onLetterTap;

  const AlphabetIndex({
    super.key,
    required this.letterOffsets,
    required this.onLetterTap,
  });

  static const List<String> letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  State<AlphabetIndex> createState() => _AlphabetIndexState();
}

class _AlphabetIndexState extends State<AlphabetIndex> {
  // Index of the letter currently pressed/dragged over, for the brief
  // highlight bubble (like iOS) — null when not touching the rail.
  int? _activeIndex;

  // Maps a local vertical position within the rail to a letter index,
  // by dividing the rail's height evenly across all 26 letters — mirrors
  // how the Column(spaceEvenly) below lays them out visually.
  int _indexForLocalY(double localY, double railHeight) {
    final slot = railHeight / AlphabetIndex.letters.length;
    final index = (localY / slot).floor();
    return index.clamp(0, AlphabetIndex.letters.length - 1);
  }

  void _handlePositionChange(Offset localPosition, double railHeight) {
    final index = _indexForLocalY(localPosition.dy, railHeight);
    final letter = AlphabetIndex.letters[index];
    final offset = widget.letterOffsets[letter];

    if (_activeIndex != index) {
      setState(() => _activeIndex = index);
    }
    if (offset != null) {
      widget.onLetterTap(offset);
    }
  }

  void _handleEnd() {
    setState(() => _activeIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) =>
              _handlePositionChange(details.localPosition, railHeight),
          onVerticalDragUpdate: (details) =>
              _handlePositionChange(details.localPosition, railHeight),
          onVerticalDragEnd: (_) => _handleEnd(),
          onVerticalDragCancel: _handleEnd,
          onTapDown: (details) =>
              _handlePositionChange(details.localPosition, railHeight),
          onTapUp: (_) => _handleEnd(),
          onTapCancel: _handleEnd,
          child: Container(
            width: 22,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (int i = 0; i < AlphabetIndex.letters.length; i++)
                  Builder(
                    builder: (context) {
                      final letter = AlphabetIndex.letters[i];
                      final isAvailable = widget.letterOffsets[letter] != null;
                      final isActive = _activeIndex == i && isAvailable;
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 100),
                        scale: isActive ? 1.4 : 1.0,
                        child: Text(
                          letter,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: !isAvailable
                                ? Colors.white24
                                : isActive
                                    ? activeColor
                                    : activeColor.withOpacity(0.85),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}