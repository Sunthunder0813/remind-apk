import 'package:hive/hive.dart';
import 'anime.dart';

part 'saved_anime.g.dart';

// Hive needs its own adapter for the AnimeSource enum, since plain Dart
// enums aren't storable by default — HiveType on an enum just maps each
// value to a small int index under the hood.
@HiveType(typeId: 2)
enum HiveAnimeSource {
  @HiveField(0)
  jikan,
  @HiveField(1)
  anilist,
}

// Persisted version of Anime — stores everything needed to redisplay a
// liked/watchlisted card fully offline (title, image, genres, etc.),
// rather than just an id that would need a fresh Jikan/AniList fetch on
// every app restart. `listType` distinguishes "liked" vs "watchlisted"
// entries living in the same Hive box, since the two lists share an
// identical shape — keeping them in one box avoids running two near-
// identical adapters/boxes for what's really just a status flag.
@HiveType(typeId: 3)
class SavedAnime extends HiveObject {
  @HiveField(0)
  late String uniqueKey; // "<source>_<malId>" — matches Anime.uniqueKey exactly

  @HiveField(1)
  late HiveAnimeSource source;

  @HiveField(2)
  late int malId;

  @HiveField(3)
  late String title;

  @HiveField(4)
  late String imageUrl;

  @HiveField(5)
  late String synopsis;

  @HiveField(6)
  double? score;

  @HiveField(7)
  late List<String> genres;

  @HiveField(8)
  late String listType; // 'liked' or 'watchlisted'

  @HiveField(9)
  late DateTime savedAt;

  @HiveField(10, defaultValue: null)
  String? remarks;

  SavedAnime({
    required this.uniqueKey,
    required this.source,
    required this.malId,
    required this.title,
    required this.imageUrl,
    required this.synopsis,
    this.score,
    required this.genres,
    required this.listType,
    required this.savedAt,
    this.remarks,
  });

  // Converts back to the plain Anime model the rest of the app (Discover,
  // the swipe cards, etc.) already knows how to render.
  Anime toAnime() {
    return Anime(
      malId: malId,
      title: title,
      imageUrl: imageUrl,
      synopsis: synopsis,
      score: score,
      genres: genres,
      source: source == HiveAnimeSource.jikan ? AnimeSource.jikan : AnimeSource.anilist,
    );
  }

  // Builds a SavedAnime from a live Anime + which list it's being saved to.
  factory SavedAnime.fromAnime(Anime anime, {required String listType, String? remarks}) {
    return SavedAnime(
      uniqueKey: anime.uniqueKey,
      source: anime.source == AnimeSource.jikan
          ? HiveAnimeSource.jikan
          : HiveAnimeSource.anilist,
      malId: anime.malId,
      title: anime.title,
      imageUrl: anime.imageUrl,
      synopsis: anime.synopsis,
      score: anime.score,
      genres: anime.genres,
      listType: listType,
      savedAt: DateTime.now(),
      remarks: remarks,
    );
  }
}