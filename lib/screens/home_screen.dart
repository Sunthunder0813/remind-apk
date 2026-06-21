import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show checklistUpdateStream;
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

  // New tab order: Notes, Discover, Liked Anime, Calendar
  final List<String> _titles = ['Notes', 'Discover', 'Liked Anime', 'Calendar'];

  final GlobalKey<NotesScreenState> _notesKey = GlobalKey<NotesScreenState>();
  final GlobalKey<DiscoverScreenState> _discoverKey = GlobalKey<DiscoverScreenState>();
  final GlobalKey<CalendarScreenState> _calendarKey = GlobalKey<CalendarScreenState>();
  StreamSubscription? _widgetSyncSubscription;

  List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens = [
      NotesScreen(key: _notesKey, onStateChanged: () => setState(() {})),
      DiscoverScreen(key: _discoverKey),
      const LikedAnimeScreen(),
      CalendarScreen(key: _calendarKey),
    ];
    _widgetSyncSubscription = checklistUpdateStream.stream.listen((message) {
      if (!mounted) return;
      _calendarKey.currentState?.reloadFromStorage();
    });
    _loadWidgetSetupState();
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
          for (int i = 0; i < _screens.length; i++)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              opacity: _selectedIndex == i ? 1.0 : 0.0,
              child: _screens[i],
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
