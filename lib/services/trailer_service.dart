import 'dart:convert';
import 'package:http/http.dart' as http;

class TrailerService {
  TrailerService._();
  static final TrailerService instance = TrailerService._();

  static const String _tmdbKey = 'db6e7da8afca317b4daa12bbe6f6a57f';

  // Returns a YouTube video ID or null if none found.
  Future<String?> fetchTrailerKey({
    required int malId,
    required bool isMovie,
    required bool isAnilist,
  }) async {
    if (isMovie) {
      return _fetchTmdbTrailer(malId);
    } else {
      // Jikan returns trailer data directly on the anime detail endpoint.
      return _fetchJikanTrailer(malId);
    }
  }

  Future<String?> _fetchTmdbTrailer(int movieId) async {
    try {
      final url = Uri.parse(
        'https://api.themoviedb.org/3/movie/$movieId/videos'
        '?api_key=$_tmdbKey&language=en-US',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? [];
      // Prefer official YouTube trailers first, then any teaser.
      final trailer = results.firstWhere(
        (v) =>
            v['site'] == 'YouTube' &&
            v['type'] == 'Trailer' &&
            v['official'] == true,
        orElse: () => results.firstWhere(
          (v) => v['site'] == 'YouTube' && v['type'] == 'Trailer',
          orElse: () => results.firstWhere(
            (v) => v['site'] == 'YouTube',
            orElse: () => null,
          ),
        ),
      );
      return trailer?['key'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchJikanTrailer(int malId) async {
    try {
      final url = Uri.parse('https://api.jikan.moe/v4/anime/$malId');
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? {};
      final trailer = data['trailer'] as Map<String, dynamic>? ?? {};
      final youtubeId = trailer['youtube_id'] as String?;
      return youtubeId;
    } catch (_) {
      return null;
    }
  }
}