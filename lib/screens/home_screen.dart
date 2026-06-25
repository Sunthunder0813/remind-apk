  import 'dart:async';
  import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:home_widget/home_widget.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import '../main.dart' show checklistUpdateStream;
  import '../models/tmdb_genres.dart';
  import '../services/anime_api_service.dart';
  import 'notes_screen.dart';
  import 'discover_screen.dart';
  import 'liked_anime_screen.dart';
  import 'calendar_screen.dart';
  import 'watchlisted_screen.dart';

  class HomeScreen extends StatefulWidget {
    const HomeScreen({super.key});

    @override
    State<HomeScreen> createState() => _HomeScreenState();
  }

  class _HomeScreenState extends State<HomeScreen> {
    int _selectedIndex = 0;
    bool _widgetSetupDone = false;
    // Lifted from LikedAnimeScreen so the AppBar toggle can control them.
    String _likedSourceFilter = 'All';
    // Multi-select now, mirroring Discover's genre filter UX.
    Set<String> _likedGenreSelection = {};

    // Full genre catalogs (not just genres present on liked items) so the
    // Liked screen's filter sheet can offer every genre Discover offers,
    // e.g. "Isekai" even if the user has zero liked Isekai anime yet.
    List<String> _animeGenreCatalog = [];
    final List<String> _movieGenreCatalog = TmdbGenres.names;

    // New tab order: Notes, Discover, Liked Anime, Calendar
    final List<String> _titles = ['Notes', 'Discover', 'Liked Anime', 'Calendar'];

    final GlobalKey<NotesScreenState> _notesKey = GlobalKey<NotesScreenState>();
    final GlobalKey<DiscoverScreenState> _discoverKey = GlobalKey<DiscoverScreenState>();
    final GlobalKey<CalendarScreenState> _calendarKey = GlobalKey<CalendarScreenState>();
    StreamSubscription? _widgetSyncSubscription;

    late final List<Widget> _screens;

    @override
    void initState() {
      super.initState();
      _screens = [
        NotesScreen(key: _notesKey, onStateChanged: () => setState(() {})),
        DiscoverScreen(key: _discoverKey),
        // LikedAnimeScreen is intentionally NOT here — it needs sourceFilter
        // and selectedGenre to update on every HomeScreen rebuild, so it's
        // built inline in build() instead of being a fixed cached widget.
        CalendarScreen(key: _calendarKey),
      ];
      _widgetSyncSubscription = checklistUpdateStream.stream.listen((message) {
        if (!mounted) return;
        _calendarKey.currentState?.reloadFromStorage();
      });
      _loadWidgetSetupState();
      _loadAnimeGenreCatalog();
    }

    // Fetches the full Jikan anime genre list once, same source Discover
    // uses — so the Liked screen's filter sheet can show genres like
    // "Isekai" even when none of the user's liked anime have that tag yet.
    Future<void> _loadAnimeGenreCatalog() async {
      try {
        final genres = await AnimeApiService.instance.fetchGenres();
        if (!mounted) return;
        setState(() {
          _animeGenreCatalog = genres.map((g) => g.name).toList()..sort();
        });
      } catch (_) {
        // Leave it empty on failure — the filter sheet will just show
        // movie genres (if in Movie mode) or nothing (Anime/All), and
        // the user can still browse/filter by source.
      }
    }

    @override
    void dispose() {
      _widgetSyncSubscription?.cancel();
      super.dispose();
    }

    Future<void> _loadWidgetSetupState() async {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _widgetSetupDone = prefs.getBool('widget_setup_done') ?? false;
      });
    }

    // The FAB makes sense on every tab now: Notes (add note/folder),
    // Discover (open genre filter), Liked Anime (open the Watchlisted
    // page), and Calendar (add reminder for the selected day).
    bool get _showFab => true;

    IconData get _fabIcon {
      switch (_selectedIndex) {
        case 0:
          return Icons.add;
        case 1:
          return Icons.tune;
        case 2:
          return Icons.bookmark_outline;
        case 3:
          return Icons.add_alarm;
        default:
          return Icons.add;
      }
    }

    // Switches tabs, plus any tab-specific re-entry behavior. Discover's
    // State stays alive the whole session (it lives in an IndexedStack), so
    // its initState() only runs once — replaying the coaching overlay has to
    // be driven from here instead, every time the user taps back into it.
    void _selectTab(int index) {
      setState(() => _selectedIndex = index);
      if (index == 1) {
        _discoverKey.currentState?.replayCoachOverlay();
      }
    }

    Future<void> _showWidgetSetupDialog() async {
      try {
        final isPinSupported = await HomeWidget.isRequestPinWidgetSupported();
        if (isPinSupported == true) {
          // Android 8.0+ supports programmatic widget pinning —
          // this opens the system "Add widget to home screen?" prompt directly.
          await HomeWidget.requestPinWidget(
            name: 'TodoWidgetProvider',
            androidName: 'TodoWidgetProvider',
          );
        } else {
          // Older Android versions don't support pin requests — fall back
          // to a short manual instruction dialog.
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add Widget Manually'),
              content: const Text(
                'Long-press your home screen → Widgets → find "Remind" → drag it onto your home screen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        debugPrint('[Widget] pin request failed: $e');
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add Widget Manually'),
            content: const Text(
              'Long-press your home screen → Widgets → find "Remind" → drag it onto your home screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      }
    }

    void _onFabPressed() {
      if (_selectedIndex == 0) {
        _notesKey.currentState?.showAddOptions();
      } else if (_selectedIndex == 1) {
        _discoverKey.currentState?.openGenreFilter();
      } else if (_selectedIndex == 2) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WatchlistedScreen()),
        );
      } else if (_selectedIndex == 3) {
        _calendarKey.currentState?.addReminderForSelectedDay();
      }
    }

    // Resolves the same "asset:"/"file:" prefix scheme used by NotesScreen's
    // card backgrounds, so the AppBar can show the same image when browsing
    // inside a themed folder.
    ImageProvider _resolveBackgroundImage(String path) {
      if (path.startsWith('asset:')) {
        return AssetImage(path.substring('asset:'.length));
      }
      return FileImage(File(path.substring('file:'.length)));
    }

    @override
    Widget build(BuildContext context) {
      final colorScheme = Theme.of(context).colorScheme;

      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Builder(
            builder: (context) {
            final folderBackground = _selectedIndex == 0
                ? _notesKey.currentState?.currentFolderBackgroundPath
                : null;

            return AppBar(
              centerTitle: false,
              titleSpacing: 16,
              backgroundColor: folderBackground != null ? Colors.transparent : null,
              elevation: folderBackground != null ? 0 : null,
              flexibleSpace: folderBackground != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image(
                          image: _resolveBackgroundImage(folderBackground),
                          fit: BoxFit.cover,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.25),
                                Colors.black.withOpacity(0.55),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
              title: _selectedIndex == 0
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!(_notesKey.currentState?.isAtRoot ?? true)) ...[
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => _notesKey.currentState?.goBack(),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(_notesKey.currentState?.currentFolderName ?? 'Notes'),
                      ],
                    )
                  : Text(_titles[_selectedIndex]),
              leading: null,
              actions: _selectedIndex == 0
                  ? [
                      IconButton(
                        tooltip: (_notesKey.currentState?.isGridView ?? true)
                            ? 'List view'
                            : 'Grid view',
                        icon: Icon((_notesKey.currentState?.isGridView ?? true)
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded),
                        onPressed: () => _notesKey.currentState?.toggleGridView(),
                      ),
                      IconButton(
                        tooltip: (_notesKey.currentState?.isEditMode ?? false)
                            ? 'Done editing'
                            : 'Edit theme',
                        icon: Icon((_notesKey.currentState?.isEditMode ?? false)
                            ? Icons.checklist_rounded
                            : Icons.edit_outlined),
                        onPressed: () => _notesKey.currentState?.toggleEditMode(),
                      ),
                      IconButton(
                        tooltip: 'Archived',
                        icon: const Icon(Icons.archive_outlined),
                        onPressed: () => _notesKey.currentState?.openArchived(),
                      ),
                    ]
                : _selectedIndex == 1
                ? [
                    _ModeToggle(
                      isMovieMode: _discoverKey.currentState?.isMovieMode ?? false,
                      onToggle: (isMovie) {
                        _discoverKey.currentState?.switchMode(isMovie);
                        // switchMode calls setState inside DiscoverScreenState,
                        // but HomeScreen's AppBar reads isMovieMode directly —
                        // it needs its own rebuild to repaint the toggle pill.
                        setState(() {});
                      },
                    ),
                  ]
                : _selectedIndex == 2
                ? [
                    _LikedSourceToggle(
                      sourceFilter: _likedSourceFilter,
                      onChanged: (val) => setState(() {
                        _likedSourceFilter = val;
                        _likedGenreSelection = {};
                      }),
                    ),
                  ]
                : _selectedIndex == 3
                ? [
                      IconButton(
                        tooltip: _widgetSetupDone
                            ? 'Widget active'
                            : 'Add home screen widget',
                        icon: Icon(
                          _widgetSetupDone
                              ? Icons.widgets
                              : Icons.widgets_outlined,
                          color: _widgetSetupDone
                              ? colorScheme.primary
                              : Colors.white60,
                        ),
                        onPressed: () async {
                          setState(() => _widgetSetupDone = true);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('widget_setup_done', true);
                          _showWidgetSetupDialog();
                        },
                      ),
                    ]
                  : null,
            );
            },
          ),
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            // Index 0 — Notes
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _selectedIndex == 0 ? 1.0 : 0.0,
              child: _screens[0],
            ),
            // Index 1 — Discover
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _selectedIndex == 1 ? 1.0 : 0.0,
              child: _screens[1],
            ),
            // Index 2 — Liked Anime: rebuilt every time so sourceFilter
            // and selectedGenre props are always current.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _selectedIndex == 2 ? 1.0 : 0.0,
              child: LikedAnimeScreen(
                sourceFilter: _likedSourceFilter,
                selectedGenres: _likedGenreSelection,
                availableGenres: _likedSourceFilter == 'Movie'
                    ? _movieGenreCatalog
                    : _likedSourceFilter == 'Anime'
                        ? _animeGenreCatalog
                        : ({..._animeGenreCatalog, ..._movieGenreCatalog}.toList()..sort()),
                onSourceChanged: (val) => setState(() {
                  _likedSourceFilter = val;
                  _likedGenreSelection = {};
                }),
                onGenresChanged: (val) => setState(() => _likedGenreSelection = val),
              ),
            ),
            // Index 3 — Calendar
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _selectedIndex == 3 ? 1.0 : 0.0,
              child: _screens[2],
            ),
          ],
        ),
        // FAB docked in the notch cut into the bottom bar, centered and
        // raised — matches the reference layout instead of floating above
        // a flat nav bar.
        floatingActionButton: _showFab
            ? FloatingActionButton(
                onPressed: _onFabPressed,
                shape: const CircleBorder(),
                child: Icon(_fabIcon),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        extendBody: true,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: colorScheme.surface,
          height: 64,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBarIcon(
                icon: Icons.note_outlined,
                selectedIcon: Icons.note,
                selected: _selectedIndex == 0,
                onTap: () => _selectTab(0),
              ),
              _NavBarIcon(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                selected: _selectedIndex == 1,
                onTap: () => _selectTab(1),
              ),
              // Empty space in the middle — the docked FAB sits in the notch here.
              const SizedBox(width: 48),
              _NavBarIcon(
                icon: Icons.favorite_outline,
                selectedIcon: Icons.favorite,
                selected: _selectedIndex == 2,
                onTap: () => _selectTab(2),
              ),
              _NavBarIcon(
                icon: Icons.calendar_today_outlined,
                selectedIcon: Icons.calendar_month,
                selected: _selectedIndex == 3,
                onTap: () => _selectTab(3),
              ),
            ],
          ),
        ),
      );
    }
  }

  // A single icon-only nav button used inside the notched BottomAppBar.
  // No label, just an icon that swaps to its filled variant + tints purple
  // when selected — matches the reference layout's icon-only bottom bar.
  class _NavBarIcon extends StatelessWidget {
    final IconData icon;
    final IconData selectedIcon;
    final bool selected;
    final VoidCallback onTap;

    const _NavBarIcon({
      required this.icon,
      required this.selectedIcon,
      required this.selected,
      required this.onTap,
    });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        selected ? selectedIcon : icon,
        color: selected ? colorScheme.primary : Colors.white60,
      ),
    );
  }
}

// Anime | Movie toggle shown in the AppBar when the Discover tab is active.
// Animated Anime | Movie toggle with a sliding pill highlight.
// Uses a Stack so the pill slides smoothly between the two options
// rather than each chip individually fading in/out its own background.
class _ModeToggle extends StatelessWidget {
  final bool isMovieMode;
  final ValueChanged<bool> onToggle;

  const _ModeToggle({required this.isMovieMode, required this.onToggle});

  static const double _chipWidth = 64;
  static const double _chipHeight = 32;
  static const double _padding = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Pill slides from x=_padding (Anime) to x=_padding+_chipWidth (Movie)
    final pillX = isMovieMode ? _padding + _chipWidth : _padding;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: _chipHeight,
        width: _chipWidth * 2 + _padding * 2,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(_chipHeight / 2),
        ),
        child: Stack(
          children: [
            // Sliding pill — animates between the two positions
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: pillX,
              top: _padding,
              child: Container(
                width: _chipWidth,
                height: _chipHeight - _padding * 2,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular((_chipHeight - _padding * 2) / 2),
                ),
              ),
            ),
            // Labels sit above the pill in the Stack
            Row(
              children: [
                _ToggleLabel(
                  label: 'Anime',
                  width: _chipWidth,
                  selected: !isMovieMode,
                  onTap: () => onToggle(false),
                ),
                _ToggleLabel(
                  label: 'Movie',
                  width: _chipWidth,
                  selected: isMovieMode,
                  onTap: () => onToggle(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Text-only label that sits above the sliding pill.
// Does NOT have its own background — the pill beneath it provides color.
// Slim All | Anime | Movie sliding pill for the Liked Anime AppBar.
class _LikedSourceToggle extends StatelessWidget {
  final String sourceFilter;
  final ValueChanged<String> onChanged;

  const _LikedSourceToggle({
    required this.sourceFilter,
    required this.onChanged,
  });

  static const _labels = ['All', 'Anime', 'Movie'];
  static const double _chipWidth = 54;
  static const double _chipHeight = 30;
  static const double _pad = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedIndex = _labels.indexOf(sourceFilter);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: _chipHeight,
        width: _chipWidth * _labels.length + _pad * 2,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(_chipHeight / 2),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: _pad + selectedIndex * _chipWidth,
              top: _pad,
              child: Container(
                width: _chipWidth,
                height: _chipHeight - _pad * 2,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular((_chipHeight - _pad * 2) / 2),
                ),
              ),
            ),
            Row(
              children: [
                for (final label in _labels)
                  GestureDetector(
                    onTap: () => onChanged(label),
                    child: SizedBox(
                      width: _chipWidth,
                      height: _chipHeight,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sourceFilter == label
                                ? Colors.white
                                : Colors.white54,
                          ),
                          child: Text(label),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleLabel extends StatelessWidget {
  final String label;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleLabel({
    required this.label,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.white54,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
