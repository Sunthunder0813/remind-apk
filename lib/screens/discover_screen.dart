import 'dart:math';
import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../models/anime_genre.dart';
import '../services/anime_api_service.dart';
import '../services/anilist_api_service.dart';
import '../services/tmdb_api_service.dart';
import '../services/anime_like_service.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

// Public (no leading underscore) so HomeScreen can reach it via a GlobalKey
// and trigger "open genre filter" from the shared FAB — same pattern as
// NotesScreenState.showAddOptions() and CalendarScreenState.addReminderForSelectedDay().
class DiscoverScreenState extends State<DiscoverScreen> with TickerProviderStateMixin {
  List<Anime> _deck = [];
  int _jikanPage = 1;
  int _anilistPage = 1;
  bool _isLoading = true;
  String? _errorMessage;
  final Random _random = Random();
  // Stores the last passed (left-swiped) card so the user can
// double-tap the stack to restore it. Only one level of undo.
  Anime? _lastPassedAnime;
  // Session-only list of all left-swiped (passed) anime.
// Lives in memory only — clears when the app is killed.
  final List<Anime> _passedHistory = [];

  // Toggle between Anime and Movie mode.
  bool isMovieMode = false;
  int _tmdbPage = 1;

  // Genre filter state — multi-select now, so a Set of genre ids rather
  // than a single nullable genre.
  List<AnimeGenre> _genres = [];
  Set<int> _selectedGenreIds = {};
  bool _genresLoading = true;

  // Resolves selected ids back to full AnimeGenre objects, for display
  // and for building the AniList genre_in name list.
  List<AnimeGenre> get _selectedGenreObjects =>
      _genres.where((g) => _selectedGenreIds.contains(g.malId)).toList();

  // Compact label for the status-row chip, e.g. "Action", "Action +1",
  // "Action +2" — first selected genre plus a count of the rest, so the
  // chip stays a fixed, predictable width no matter how many are picked.
  String get _genreSummaryLabel {
    final selected = _selectedGenreObjects;
    if (selected.isEmpty) return '';
    if (selected.length == 1) return selected.first.name;
    return '${selected.first.name} +${selected.length - 1}';
  }

  double _dragOffsetX = 0;
  double _dragOffsetY = 0;

  // How far (in px) the user needs to drag before it counts as a swipe
  static const double _swipeThreshold = 120;
  // How far the overlay needs to fade from 0 -> fully visible.
  // Smaller than the threshold so the user sees full color right as it commits.
  static const double _fadeDistance = 140;

  // Plays once, the first time the deck actually has cards to show —
  // fades + slides the stack in instead of it just snapping into place.
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;
  bool _entrancePlayed = false;

  // Coaching overlay teaching the swipe gesture with an animated drifting
  // hand icon before fading away on its own (or on first touch). Replayed
  // every time the user switches back to this tab — see replayCoachOverlay().
  bool _showCoachOverlay = true;
  late final AnimationController _coachController;
  late final Animation<double> _coachHandX;

  // Drives the shimmer sweep on the loading-state skeleton card. Loops
  // continuously (not just once) since the loading state can be visible
  // for an unpredictable, possibly long, stretch on a slow connection.
  late final AnimationController _shimmerController;
  // Bumped every time the overlay is (re)shown, so a stale auto-dismiss
  // timer from a previous showing can't hide a fresher one early.
  int _coachSession = 0;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _entranceFade = CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic));

    // The coaching hand drifts left-right on a loop to mimic a swipe,
    // until the overlay is dismissed.
    _coachController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _coachHandX = Tween<double>(begin: -34, end: 34).animate(
      CurvedAnimation(parent: _coachController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    // Auto-dismiss the coaching overlay after a few seconds so it never
    // overstays — the user can also dismiss it early by starting to drag.
    _scheduleCoachAutoDismiss();

    // Start from a random page each fresh launch instead of always page 1
    // — otherwise every session opens on the exact same handful of
    // top-ranked titles, in the exact same order.
    _jikanPage = 1 + _random.nextInt(5);
    _anilistPage = 1 + _random.nextInt(5);
    _tmdbPage = 1 + _random.nextInt(10);

    _loadGenres();
    _loadMoreAnime();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _coachController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _dismissCoachOverlay() {
    if (!mounted || !_showCoachOverlay) return;
    setState(() => _showCoachOverlay = false);
  }

  // Schedules the auto-dismiss for whichever "showing" of the overlay is
  // currently active. Each call bumps _coachSession so an older, already-
  // queued timer recognizes it's stale and does nothing when it fires.
  void _scheduleCoachAutoDismiss() {
    final session = ++_coachSession;
    Future.delayed(const Duration(seconds: 5), () {
      if (session == _coachSession) _dismissCoachOverlay();
    });
  }

  // Re-shows the swipe-coaching overlay. DiscoverScreen's State stays alive
  // for the whole app session (HomeScreen keeps it in an IndexedStack), so
  // initState() only runs once — this is called instead, via GlobalKey,
  // every time HomeScreen detects the user switching back to this tab.
  void replayCoachOverlay() {
    if (!mounted) return;
    setState(() => _showCoachOverlay = true);
    _scheduleCoachAutoDismiss();
  }

  // Static TMDB genre list — TMDB genre IDs never change, so there's no
  // need to fetch them; we map them the same way TmdbApiService does.
  static const List<Map<String, dynamic>> _tmdbGenreData = [
    {'malId': 28,    'name': 'Action'},
    {'malId': 12,    'name': 'Adventure'},
    {'malId': 16,    'name': 'Animation'},
    {'malId': 35,    'name': 'Comedy'},
    {'malId': 80,    'name': 'Crime'},
    {'malId': 99,    'name': 'Documentary'},
    {'malId': 18,    'name': 'Drama'},
    {'malId': 10751, 'name': 'Family'},
    {'malId': 14,    'name': 'Fantasy'},
    {'malId': 36,    'name': 'History'},
    {'malId': 27,    'name': 'Horror'},
    {'malId': 10402, 'name': 'Music'},
    {'malId': 9648,  'name': 'Mystery'},
    {'malId': 10749, 'name': 'Romance'},
    {'malId': 878,   'name': 'Sci-Fi'},
    {'malId': 53,    'name': 'Thriller'},
    {'malId': 10752, 'name': 'War'},
    {'malId': 37,    'name': 'Western'},
  ];

  // Anime genres fetched from Jikan; TMDB genres are static above.
  List<AnimeGenre> _animeGenres = [];
  List<AnimeGenre> _movieGenres = [];

  // Whichever genre list is active for the current mode.
  List<AnimeGenre> get _activeGenres => isMovieMode ? _movieGenres : _animeGenres;

  Future<void> _loadGenres() async {
    // Movie genres are static — build them immediately, no fetch needed.
    _movieGenres = _tmdbGenreData
        .map((g) => AnimeGenre(malId: g['malId'] as int, name: g['name'] as String))
        .toList();

    try {
      final genres = await AnimeApiService.instance.fetchGenres();
      if (mounted) {
        setState(() {
          _animeGenres = genres;
          _genres = isMovieMode ? _movieGenres : _animeGenres;
          _genresLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _genres = isMovieMode ? _movieGenres : _animeGenres;
          _genresLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreAnime() async {
    if (isMovieMode) {
      await _loadMoreMovies();
      return;
    }

    final wasEmpty = _deck.isEmpty;
    final requestGenreIds = Set<int>.from(_selectedGenreIds);
    final requestGenreObjects = _selectedGenreObjects;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final results = await Future.wait([
      AnimeApiService.instance
          .fetchTopAnime(
            page: _jikanPage,
            genreIds: requestGenreObjects.map((g) => g.malId).toList(),
          )
          .catchError((_) => <Anime>[]),
      AnilistApiService.instance
          .fetchTopAnime(
            page: _anilistPage,
            genreNames: requestGenreObjects.map((g) => g.name).toList(),
          )
          .catchError((_) => <Anime>[]),
    ]);

    if (!_sameGenreSelection(requestGenreIds, _selectedGenreIds)) {
      return;
    }

    final jikanResults = results[0];
    final anilistResults = results[1];

    if (jikanResults.isEmpty && anilistResults.isEmpty) {
      setState(() {
        _isLoading = false;
        if (_deck.isEmpty) {
          _errorMessage = 'Could not load anime. Check your connection.';
        }
      });
      return;
    }

    _jikanPage++;
    _anilistPage++;

    final combined = [...jikanResults, ...anilistResults];

    final seenKeys = _deck.map((a) => a.uniqueKey).toSet();
    final seenTitles = _deck.map(_normalizeTitle).toSet();
    final newAnime = <Anime>[];
    for (final anime in combined) {
      final keyIsNew = seenKeys.add(anime.uniqueKey);
      final titleIsNew = seenTitles.add(_normalizeTitle(anime));
      if (keyIsNew && titleIsNew) {
        newAnime.add(anime);
      }
    }

    _rankByGenreMatch(newAnime, requestGenreObjects);

    setState(() {
      _deck.addAll(newAnime);
      _isLoading = false;
    });
    if (wasEmpty && _deck.isNotEmpty && !_entrancePlayed) {
      _entrancePlayed = true;
      _entranceController.forward();
    }
  }

  Future<void> _loadMoreMovies() async {
    final wasEmpty = _deck.isEmpty;
    final requestGenreIds = Set<int>.from(_selectedGenreIds);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final movies = await TmdbApiService.instance.fetchPopularMovies(
        page: _tmdbPage,
        genreIds: requestGenreIds.toList(),
      );

      // Genre selection changed while the request was in flight — discard
      // the result, the new selection's own request is already underway.
      if (!_sameGenreSelection(requestGenreIds, _selectedGenreIds)) return;

      _tmdbPage++;

      final seenKeys = _deck.map((a) => a.uniqueKey).toSet();
      final newMovies = movies.where((m) => seenKeys.add(m.uniqueKey)).toList();

      // With no genre filter, shuffle purely randomly like anime mode does.
      // With a filter, rank by how many selected genres each movie matches
      // so the most relevant results surface first — reuses the same logic
      // anime uses, since movies now carry proper genre strings too.
      _rankByGenreMatch(newMovies, _selectedGenreObjects);

      setState(() {
        _deck.addAll(newMovies);
        _isLoading = false;
      });

      if (wasEmpty && _deck.isNotEmpty && !_entrancePlayed) {
        _entrancePlayed = true;
        _entranceController.forward();
      }
    } catch (_) {
      setState(() {
        _isLoading = false;
        if (_deck.isEmpty) {
          _errorMessage = 'Could not load movies. Check your connection.';
        }
      });
    }
  }

  // Switches between Anime and Movie mode, resetting the deck and
  // swapping the genre list so the filter sheet shows the right genres.
  void switchMode(bool newMode) {
    if (isMovieMode == newMode) return;
    setState(() {
      isMovieMode = newMode;
      _deck = [];
      _lastPassedAnime = null;
      _passedHistory.clear();
      _tmdbPage = 1 + _random.nextInt(10);
      _jikanPage = 1 + _random.nextInt(5);
      _anilistPage = 1 + _random.nextInt(5);
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _entrancePlayed = false;
      // Clear the genre filter — selections from anime mode are meaningless
      // in movie mode (different id/name spaces) and vice versa.
      _selectedGenreIds = {};
      // Point _genres at the correct list for the new mode so openGenreFilter()
      // and _selectedGenreObjects both read from the right source.
      _genres = isMovieMode ? _movieGenres : _animeGenres;
    });
    _loadMoreAnime();
  }
  String _normalizeTitle(Anime anime) {
    return anime.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _sameGenreSelection(Set<int> a, Set<int> b) {
    return a.length == b.length && a.containsAll(b);
  }

  // Smarter sort: with no genre filter, the batch stays purely shuffled.
  // With a filter active, anime matching MORE of the selected genres rank
  // ahead of anime matching just one — both Jikan's and AniList's genre
  // filters are OR-matches, so without this every result "looks" equally
  // relevant even when some only share a single genre with your picks.
  // A random tiebreaker (not list order) breaks ties within the same
  // match count, since List.sort in Dart isn't guaranteed stable.
  void _rankByGenreMatch(List<Anime> anime, List<AnimeGenre> selectedGenres) {
    if (selectedGenres.isEmpty) {
      anime.shuffle(_random);
      return;
    }

    final selectedNames = selectedGenres.map((g) => g.name.toLowerCase()).toSet();
    final tiebreakers = {for (final a in anime) a.uniqueKey: _random.nextDouble()};

    int matchCount(Anime a) =>
        a.genres.where((g) => selectedNames.contains(g.toLowerCase())).length;

    anime.sort((a, b) {
      final byMatches = matchCount(b).compareTo(matchCount(a));
      if (byMatches != 0) return byMatches;
      return tiebreakers[a.uniqueKey]!.compareTo(tiebreakers[b.uniqueKey]!);
    });
  }

  // Replaces the entire selection — called from the filter sheet's close
  // (Apply/dismiss), and from removing a single chip in the status row.
  void _applyGenreFilter(Set<int> newSelection) {
    if (_sameGenreSelection(newSelection, _selectedGenreIds)) return;

    setState(() {
      _selectedGenreIds = newSelection;
      _deck = [];
      _lastPassedAnime = null; // stale card from old filter, discard it
      _jikanPage = 1 + _random.nextInt(5);
      _anilistPage = 1 + _random.nextInt(5);
      _tmdbPage = 1 + _random.nextInt(10);
      _dragOffsetX = 0;
      _dragOffsetY = 0;
    });    _loadMoreAnime();
  }

  void _removeGenre(int malId) {
    _applyGenreFilter({..._selectedGenreIds}..remove(malId));
  }

  // Small popup anchored under the status-row chip, listing every selected
  // genre with its own remove (x) — a quicker peek/edit than opening the
  // full bottom sheet just to drop one genre. Tapping a row's label (not
  // the x) opens the full sheet instead, for adding new genres.
  Future<void> _openGenreSummaryMenu(BuildContext chipContext) async {
    final RenderBox box = chipContext.findRenderObject() as RenderBox;
    final Offset chipBottomLeft = box.localToGlobal(Offset(0, box.size.height));
    final Offset chipBottomRight =
        box.localToGlobal(Offset(box.size.width, box.size.height));
    final Size screenSize = MediaQuery.of(context).size;

    final selected = _selectedGenreObjects;

    final result = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        chipBottomLeft.dx,
        chipBottomLeft.dy + 4,
        screenSize.width - chipBottomRight.dx,
        0,
      ),
      color: const Color(0xFF3C3541),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        for (final genre in selected)
          PopupMenuItem<int>(
            // Returning the malId means "open the full sheet to manage
            // this genre" is one tap away too, via the row label itself.
            value: genre.malId,
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    genre.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                // Its own tap target — removes just this genre without
                // closing for the others, by popping with a sentinel
                // negative id distinguishable from any real malId.
                GestureDetector(
                  onTap: () => Navigator.pop(context, -genre.malId - 1),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (result == null || !mounted) return;

    if (result < 0) {
      // Sentinel decode: -genre.malId - 1  =>  genre.malId = -(result) - 1
      _removeGenre(-result - 1);
    } else {
      openGenreFilter();
    }
  }

  // Opens a bottom sheet listing every genre as a selectable tile, with
  // the current selection (if any) highlighted, an "All" option to clear
  // the filter, and an A-Z index along the right edge for jumping straight
  // to a letter instead of scrolling through the whole list. Public so
  // HomeScreen's center FAB can call it directly while the Discover tab
  // is active.
  Future<void> openGenreFilter() async {
    if (_genresLoading) return;

    final scrollController = ScrollController();
    const double rowHeight = 56;

    final Map<String, double> letterOffsets = {};
    for (int i = 0; i < _genres.length; i++) {
      final name = _genres[i].name;
      if (name.isEmpty) continue;
      final letter = name[0].toUpperCase();
      if (!letterOffsets.containsKey(letter)) {
        letterOffsets[letter] = i * rowHeight;
      }
    }

    // Local working copy — checking a box only updates the sheet's own
    // state, so we're not re-fetching the deck on every single tap. The
    // network reload fires once, when the sheet closes (Apply tap, swipe
    // down, or tap-outside all commit whatever's checked at that point).
    var working = {..._selectedGenreIds};

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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ListView.builder(
                              controller: scrollController,
                              itemExtent: rowHeight,
                              itemCount: _genres.length,
                              itemBuilder: (context, index) {
                                final genre = _genres[index];
                                final isSelected = working.contains(genre.malId);
                                return CheckboxListTile(
                                  value: isSelected,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  activeColor: Theme.of(context).colorScheme.primary,
                                  title: Text(genre.name),
                                  onChanged: (checked) {
                                    setSheetState(() {
                                      if (checked == true) {
                                        working.add(genre.malId);
                                      } else {
                                        working.remove(genre.malId);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          _AlphabetIndex(
                            letterOffsets: letterOffsets,
                            onLetterTap: (offset) {
                              if (!scrollController.hasClients) return;
                              final maxScroll =
                                  scrollController.position.maxScrollExtent;
                              scrollController.animateTo(
                                offset.clamp(0.0, maxScroll),
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
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
                                ? 'Show all anime'
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

    _applyGenreFilter(working);
  }

  void _swipeTopCard({required bool liked}) {
    if (_deck.isEmpty) return;

    final anime = _deck.first;

    setState(() {
      _deck.removeAt(0);
      if (liked) {
        AnimeLikeService.instance.like(anime);
        _lastPassedAnime = null;
      } else {
        _lastPassedAnime = anime;
        _passedHistory.insert(0, anime); // newest first
      }
      _dragOffsetX = 0;
      _dragOffsetY = 0;
    });

    if (_deck.length < 5 && !_isLoading) {
      _loadMoreAnime();
    }
  }

  // Double-tap restore: puts the last passed card back on top of the deck.
  // Clears _lastPassedAnime immediately so there's only ever one undo.
  void _restoreLastPassed() {
    if (_lastPassedAnime == null) return;
    setState(() {
      _deck.insert(0, _lastPassedAnime!);
      // Also remove it from history since it's back in the deck
      _passedHistory.remove(_lastPassedAnime);
      _lastPassedAnime = null;
    });
  }

  // Opens a bottom sheet listing every anime the user passed this session.
  // From here they can like an entry directly without going back to the deck.
  void _openPassedHistory() {
    if (_passedHistory.isEmpty) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF29262B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: const [
                  Text(
                    'Passed this session',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '0 anime',
                    style: TextStyle(fontSize: 13, color: Colors.white38),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No passed anime yet this session.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF29262B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.93,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Row(
                        children: [
                          const Text(
                            'Passed this session',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_passedHistory.length} anime',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _passedHistory.length,
                        itemBuilder: (context, index) {
                          final anime = _passedHistory[index];
                          final alreadyLiked = AnimeLikeService
                              .instance.liked
                              .any((a) => a.uniqueKey == anime.uniqueKey);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                anime.imageUrl,
                                width: 48,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 48,
                                  height: 64,
                                  color: Colors.white10,
                                  child: const Icon(
                                      Icons.image_not_supported,
                                      size: 20,
                                      color: Colors.white38),
                                ),
                              ),
                            ),
                            title: Text(
                              anime.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: anime.score != null
                                ? Row(
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 12, color: Colors.amber),
                                      const SizedBox(width: 3),
                                      Text(
                                        anime.score!.toStringAsFixed(2),
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                            trailing: IconButton(
                              icon: Icon(
                                alreadyLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: alreadyLiked
                                    ? Colors.pinkAccent
                                    : Colors.white38,
                              ),
                              onPressed: alreadyLiked
                                  ? null
                                  : () {
                                      AnimeLikeService.instance.like(anime);
                                      setSheetState(() {});
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }



  Widget _buildCard(Anime anime, {bool isTop = false}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isTop ? 10 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            anime.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade300,
              child: const Icon(Icons.image_not_supported, size: 48),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.grey.shade200,
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          ),
          // Taller, stronger gradient so the title/synopsis reads clearly
          // over busy artwork — the card's content is the focus now.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.55, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.75),
                    Colors.black.withOpacity(0.92),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (anime.score != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 3),
                          Text(
                            anime.score!.toStringAsFixed(2),
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    anime.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    anime.synopsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Skeleton placeholder shown instead of the spinner while the very
  // first batch of cards is loading — mimics the real card's shape
  // (image area + bottom gradient + title/synopsis bars) so the
  // transition into real content doesn't visually "jump", and a sweeping
  // light band signals "still working" without a single static spinner
  // glyph stuck in a wall of empty dark space.
  Widget _buildSkeletonCard() {
    final baseColor = Colors.white.withOpacity(0.06);
    final highlightColor = Colors.white.withOpacity(0.14);

    Widget bar({required double width, required double height}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: baseColor),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bar(width: 64, height: 20),
                  const SizedBox(height: 14),
                  bar(width: double.infinity, height: 22),
                  const SizedBox(height: 8),
                  bar(width: 180, height: 22),
                  const SizedBox(height: 12),
                  bar(width: double.infinity, height: 12),
                  const SizedBox(height: 6),
                  bar(width: 220, height: 12),
                ],
              ),
            ),
          ),
          // Diagonal light band sweeping left-to-right on a loop. Clipped
          // to the card via the Card's clipBehavior, so it never spills
          // past the rounded corners.
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              // -1.6 to 1.6 (not 0 to 1) so the band fully clears both
              // edges before looping, instead of popping back mid-screen.
              final t = (_shimmerController.value * 3.2) - 1.6;
              return Positioned.fill(
                child: Transform.translate(
                  offset: Offset(t * 220, 0),
                  child: Transform.rotate(
                    angle: -0.35,
                    child: Container(
                      width: 90,
                      height: 700,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            highlightColor,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Fade-in/out colored overlay + direction arrow shown on top of the
  // top card while the user is dragging it. Replaces the old static
  // LIKE/NOPE stamps with something that responds continuously to the drag.
  Widget _buildDirectionOverlay() {
    // 0 = no drag, 1 = fully committed (at or past fade distance)
    final progressRight = (_dragOffsetX / _fadeDistance).clamp(0.0, 1.0);
    final progressLeft = (-_dragOffsetX / _fadeDistance).clamp(0.0, 1.0);

    // Nothing to show if barely moved
    if (progressRight == 0 && progressLeft == 0) {
      return const SizedBox.shrink();
    }

    final isRight = progressRight > progressLeft;
    final progress = isRight ? progressRight : progressLeft;
    final color = isRight ? Colors.green : Colors.red;
    final icon = isRight ? Icons.favorite : Icons.close;
    final label = isRight ? 'LIKE' : 'PASS';
    final alignment = isRight ? Alignment.centerRight : Alignment.centerLeft;

    return Positioned.fill(
      child: Opacity(
        // Fades in as the drag grows, fades back out as it returns to center
        opacity: progress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
              end: isRight ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                Colors.transparent,
                color.withOpacity(0.55),
              ],
            ),
          ),
          child: Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 48),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // One-time coaching overlay over the top card: a dark scrim with a
  // drifting hand icon miming a swipe, plus short copy teaching the
  // gesture. Tapping anywhere dismisses it immediately; it also
  // auto-dismisses after a few seconds or the first real drag.
  //
  // Always present in the tree (never conditionally added/removed) —
  // only its opacity and hit-testing change — so the Stack's children
  // never change shape across rebuilds while animations are running.
Widget _buildCoachOverlay() {
    return GestureDetector(
      onTap: _dismissCoachOverlay,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        opacity: _showCoachOverlay ? 1.0 : 0.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black.withOpacity(0.55),
          ),
          child: Center(
            // The scrim above fades in flatly, but the actual hand/text
            // content pops in with a gentle overshoot — feels much more
            // alive than a plain fade, especially on repeat tab visits.
            child: AnimatedScale(
              duration: const Duration(milliseconds: 380),
              curve: _showCoachOverlay ? Curves.easeOutBack : Curves.easeIn,
              scale: _showCoachOverlay ? 1.0 : 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _coachHandX,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_coachHandX.value, 0),
                        child: const Icon(
                          Icons.swipe,
                          color: Colors.white,
                          size: 52,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Swipe to choose',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.arrow_back, color: Colors.white70, size: 16),
                      SizedBox(width: 6),
                      Text('Not interested',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      SizedBox(width: 16),
                      Text('Save',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward, color: Colors.white70, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Slim status row — filter chip + swipe hint + history button ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 4),
          child: Row(
            children: [
              if (_selectedGenreIds.isNotEmpty)
                Builder(
                  builder: (chipContext) => InputChip(
                    label: Text(_genreSummaryLabel),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openGenreSummaryMenu(chipContext),
                    onDeleted: () => _applyGenreFilter({}),
                    deleteIcon: const Icon(Icons.close, size: 14),
                  ),
                )
              else
                const SizedBox.shrink(),
              const Spacer(),
              if (_deck.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.arrow_back, size: 12, color: Colors.white38),
                    const SizedBox(width: 3),
                    Text(
                      _lastPassedAnime != null
                          ? 'Double-tap to undo'
                          : 'Not interested',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.white38),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 11, color: Colors.white24),
                    const SizedBox(width: 10),
                    const Text(
                      'Save',
                      style: TextStyle(fontSize: 11.5, color: Colors.white38),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_forward,
                        size: 12, color: Colors.white38),
                  ],
                ),
              // History icon button with live badge count
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white54),
                    tooltip: 'Passed this session',
                    onPressed: _openPassedHistory,
                  ),
                  if (_passedHistory.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.pinkAccent,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        child: Text(
                          _passedHistory.length > 99
                              ? '99+'
                              : '${_passedHistory.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ── Card stack area — now the dominant element on the tab ────────
        Expanded(
          child: _deck.isEmpty
              ? _isLoading
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                      child: _buildSkeletonCard(),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.movie_filter_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage ??
                                (_selectedGenreIds.isNotEmpty
                                    ? 'No more anime to show for this genre filter'
                                    : 'No more anime to show'),
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadMoreAnime,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    )
              : Padding(
                  // Bottom padding sized to clear the docked FAB with a
                  // visible margin — the card sits as a contained object,
                  // not edge-to-edge with the bottom bar.
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                  child: Stack(
                    children: [
                      // Entrance fade/slide wraps ONLY the card stack —
                      // never the coach overlay or gesture layer — so the
                      // two independently-ticking animations don't end up
                      // nested inside each other's cached subtree.
                      AnimatedBuilder(
                        animation: _entranceController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _entranceFade.value,
                            child: Transform.translate(
                              offset: Offset(0, _entranceSlide.value.dy * 40),
                              child: child,
                            ),
                          );
                        },
                        child: Stack(
                          children: [
                            for (int i = (_deck.length > 3 ? 2 : _deck.length - 1); i >= 0; i--)
                              if (i != 0)
                                Transform.scale(
                                  key: ValueKey('card_${_deck[i].uniqueKey}'),
                                  scale: 1 - (i * 0.04),
                                  child: Transform.translate(
                                    offset: Offset(0, i * 10),
                                    child: _buildCard(_deck[i]),
                                  ),
                                ),
                            GestureDetector(
                              key: ValueKey('top_${_deck[0].uniqueKey}'),
                              onDoubleTap: _restoreLastPassed, // double-tap brings back last passed card
                              onPanUpdate: (details) {
                                setState(() {
                                  _dragOffsetX += details.delta.dx;
                                  _dragOffsetY += details.delta.dy;
                                  if (_showCoachOverlay) _showCoachOverlay = false;
                                });
                              },
                              onPanEnd: (details) {
                                if (_dragOffsetX > _swipeThreshold) {
                                  _swipeTopCard(liked: true);
                                } else if (_dragOffsetX < -_swipeThreshold) {
                                  _swipeTopCard(liked: false);
                                } else {
                                  setState(() {
                                    _dragOffsetX = 0;
                                    _dragOffsetY = 0;
                                  });
                                }
                              },
                              child: Transform.translate(
                                offset: Offset(_dragOffsetX, _dragOffsetY),
                                child: Transform.rotate(
                                  angle: _dragOffsetX / 800,
                                  child: Stack(
                                    children: [
                                      _buildCard(_deck[0], isTop: true),
                                      _buildDirectionOverlay(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Coach overlay sits outside the entrance AnimatedBuilder
                      // entirely — its own independent animation never gets
                      // nested inside another controller's cached child.
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_showCoachOverlay,
                          child: _buildCoachOverlay(),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// Vertical A-Z quick-jump index running down the right edge of the genre
// list, like the iOS Contacts list. Tapping a letter scrolls straight to
// the first genre starting with it; letters with no matching genre are
// dimmed and not tappable.
class _AlphabetIndex extends StatelessWidget {
  final Map<String, double> letterOffsets;
  final void Function(double offset) onLetterTap;

  const _AlphabetIndex({
    required this.letterOffsets,
    required this.onLetterTap,
  });

  static const List<String> _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: 22,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final letter in _letters)
            Builder(
              builder: (context) {
                final offset = letterOffsets[letter];
                final isAvailable = offset != null;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isAvailable ? () => onLetterTap(offset) : null,
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isAvailable ? activeColor : Colors.white24,
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