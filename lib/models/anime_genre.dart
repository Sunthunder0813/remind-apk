// Represents a single genre from Jikan's /genres/anime endpoint
class AnimeGenre {
  final int malId;
  final String name;

  AnimeGenre({required this.malId, required this.name});

  factory AnimeGenre.fromJson(Map<String, dynamic> json) {
    return AnimeGenre(
      malId: json['mal_id'] as int,
      name: json['name'] as String? ?? 'Unknown',
    );
  }
}