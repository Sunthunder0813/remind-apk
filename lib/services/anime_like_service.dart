import 'package:flutter/foundation.dart';
import '../models/anime.dart';
import '../models/saved_anime.dart';
import 'database_service.dart';

/// Holds the liked AND watchlisted anime lists, shared between the
/// Discover tab (where likes happen), the Liked Anime tab, and the
/// Watchlisted tab, so all three stay in sync in real time.
///
/// Now backed by Hive (via DatabaseService) instead of being purely
/// in-memory — both lists survive app restarts. The in-memory `_liked`/
/// `_watchlisted` lists below are a live cache loaded from Hive at
/// startup and kept in sync on every change, so the rest of the app can
/// keep reading them synchronously (no async needed at the call site)
/// exactly like before.
class AnimeLikeService extends ChangeNotifier {
  AnimeLikeService._();
  static final AnimeLikeService instance = AnimeLikeService._();

  static const String _likedListType = 'liked';
  static const String _watchlistedListType = 'watchlisted';

  final List<Anime> _liked = [];
  final List<Anime> _watchlisted = [];

  // uniqueKey -> remarks, only meaningful for watchlisted entries. Loaded
  // from Hive alongside _watchlisted and kept in sync on every edit.
  final Map<String, String?> _remarks = {};

  List<Anime> get liked => List.unmodifiable(_liked);
  List<Anime> get watchlisted => List.unmodifiable(_watchlisted);

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // Call once at app startup (after DatabaseService.init()) to populate
  // the in-memory cache from Hive. Safe to call more than once — it's a
  // no-op after the first successful load.
  void loadFromHive() {
    if (_isLoaded) return;

    _liked
      ..clear()
      ..addAll(
        DatabaseService.instance.getSavedAnime(_likedListType).map((e) => e.toAnime()),
      );
    final watchlistedEntries = DatabaseService.instance.getSavedAnime(_watchlistedListType);
    _watchlisted
      ..clear()
      ..addAll(watchlistedEntries.map((e) => e.toAnime()));

    _remarks.clear();
    for (final entry in watchlistedEntries) {
      _remarks[entry.uniqueKey] = entry.remarks;
    }

    _isLoaded = true;
    notifyListeners();
  }

  // ── Remarks (watchlisted only) ──────────────────────────────────────────

  String? getRemark(String uniqueKey) => _remarks[uniqueKey];

  // Updates the remark on an already-watchlisted entry. No-ops if the
  // anime isn't actually watchlisted, since remarks only apply there.
  void setRemark(String uniqueKey, String? remarks) {
    final entry = DatabaseService.instance.getSavedAnimeEntry(_watchlistedListType, uniqueKey);
    if (entry == null) return;

    entry.remarks = (remarks == null || remarks.trim().isEmpty) ? null : remarks.trim();
    entry.save(); // HiveObject.save() writes back to the same box key

    _remarks[uniqueKey] = entry.remarks;
    notifyListeners();
  }

  // ── Liked ────────────────────────────────────────────────────────────────

  void like(Anime anime) {
    // Dedupe by uniqueKey (source + malId), not malId alone — a Jikan
    // entry and an AniList entry can share the same malId without being
    // the same anime, so malId-only dedupe was a latent bug.
    if (_liked.any((a) => a.uniqueKey == anime.uniqueKey)) return;
    _liked.add(anime);
    notifyListeners();
    DatabaseService.instance.saveSavedAnime(
      SavedAnime.fromAnime(anime, listType: _likedListType),
    );
  }

  void unlike(String uniqueKey) {
    final removed = _liked.where((a) => a.uniqueKey == uniqueKey).toList();
    if (removed.isEmpty) return;
    _liked.removeWhere((a) => a.uniqueKey == uniqueKey);
    notifyListeners();
    DatabaseService.instance.deleteSavedAnime(_likedListType, uniqueKey);
  }

  bool isLiked(String uniqueKey) => _liked.any((a) => a.uniqueKey == uniqueKey);

  // ── Watchlisted ──────────────────────────────────────────────────────────

  // Moves an anime from Liked into Watchlisted — removes it from the
  // liked list and adds it to watchlisted, both persisted. If it's
  // already watchlisted, this is a no-op beyond ensuring it's not also
  // still sitting in Liked.
  void moveToWatchlist(Anime anime) {
    final wasLiked = _liked.any((a) => a.uniqueKey == anime.uniqueKey);
    if (wasLiked) {
      _liked.removeWhere((a) => a.uniqueKey == anime.uniqueKey);
      DatabaseService.instance.deleteSavedAnime(_likedListType, anime.uniqueKey);
    }

    if (!_watchlisted.any((a) => a.uniqueKey == anime.uniqueKey)) {
      _watchlisted.add(anime);
      DatabaseService.instance.saveSavedAnime(
        SavedAnime.fromAnime(anime, listType: _watchlistedListType),
      );
    }

    notifyListeners();
  }

  void removeFromWatchlist(String uniqueKey) {
    final removed = _watchlisted.where((a) => a.uniqueKey == uniqueKey).toList();
    if (removed.isEmpty) return;
    _watchlisted.removeWhere((a) => a.uniqueKey == uniqueKey);
    _remarks.remove(uniqueKey);
    notifyListeners();
    DatabaseService.instance.deleteSavedAnime(_watchlistedListType, uniqueKey);
  }

  // Moves an anime from Watchlisted back into Liked — removes it (and its
  // remark) from watchlisted and adds it to liked, both persisted. Mirrors
  // moveToWatchlist() in the opposite direction.
  void moveToLiked(Anime anime) {
    final wasWatchlisted = _watchlisted.any((a) => a.uniqueKey == anime.uniqueKey);
    if (wasWatchlisted) {
      _watchlisted.removeWhere((a) => a.uniqueKey == anime.uniqueKey);
      _remarks.remove(anime.uniqueKey);
      DatabaseService.instance.deleteSavedAnime(_watchlistedListType, anime.uniqueKey);
    }

    if (!_liked.any((a) => a.uniqueKey == anime.uniqueKey)) {
      _liked.add(anime);
      DatabaseService.instance.saveSavedAnime(
        SavedAnime.fromAnime(anime, listType: _likedListType),
      );
    }

    notifyListeners();
  }

  bool isWatchlisted(String uniqueKey) =>
      _watchlisted.any((a) => a.uniqueKey == uniqueKey);

  // How many cards per row the Liked Anime / Watchlisted grids show.
  // Lives here (not in either screen's state) so it survives switching
  // tabs/screens. Still session-only (not persisted) — purely a layout
  // preference, not data worth surviving a restart.
  int _gridColumns = 3;
  int get gridColumns => _gridColumns;
  set gridColumns(int value) {
    if (value == _gridColumns) return;
    _gridColumns = value;
    notifyListeners();
  }
}