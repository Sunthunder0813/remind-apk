enum AnimeSource { jikan, anilist }

class Anime {
  final AnimeSource source;
  final int malId;
  final String title;
  final String imageUrl;
  final String synopsis;
  final double? score;
  final List<String> genres;
  final bool isMovie;

  Anime({
    required this.malId,
    required this.title,
    required this.imageUrl,
    required this.synopsis,
    this.score,
    this.genres = const [],
    this.source = AnimeSource.jikan,
    this.isMovie = false,
  });

  String get uniqueKey => '${source.name}_$malId';

  factory Anime.fromJikanJson(Map<String, dynamic> json) {
    final genresJson = json['genres'] as List<dynamic>? ?? [];
    final genreNames = genresJson
        .map((g) => (g as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return Anime(
      malId: json['mal_id'] as int,
      title: json['title'] as String? ?? 'Unknown',
      imageUrl: json['images']?['jpg']?['large_image_url'] as String? ?? '',
      synopsis: json['synopsis'] as String? ?? 'No synopsis available.',
      score: (json['score'] as num?)?.toDouble(),
      genres: genreNames,
      source: AnimeSource.jikan,
    );
  }

  factory Anime.fromAniListJson(Map<String, dynamic> json) {
    final titleJson = json['title'] as Map<String, dynamic>? ?? {};
    final title = (titleJson['english'] as String?) ??
        (titleJson['romaji'] as String?) ??
        'Unknown';

    final genresJson = json['genres'] as List<dynamic>? ?? [];
    final genreNames = genresJson.whereType<String>().toList();

    final rawSynopsis = json['description'] as String?;
    final cleanedSynopsis =
        rawSynopsis?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';

    final averageScore = json['averageScore'] as int?;

    return Anime(
      malId: json['id'] as int,
      title: title,
      imageUrl: json['coverImage']?['large'] as String? ?? '',
      synopsis: cleanedSynopsis.isEmpty ? 'No synopsis available.' : cleanedSynopsis,
      score: averageScore == null ? null : averageScore / 10.0,
      genres: genreNames,
      source: AnimeSource.anilist,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source.name,
      'mal_id': malId,
      'title': title,
      'imageUrl': imageUrl,
      'synopsis': synopsis,
      'score': score,
      'genres': genres,
      'isMovie': isMovie,
    };
  }
}