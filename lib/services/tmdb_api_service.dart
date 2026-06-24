import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/anime.dart';

class TmdbApiService {
  TmdbApiService._();
  static final TmdbApiService instance = TmdbApiService._();

  static const String _apiKey = 'db6e7da8afca317b4daa12bbe6f6a57f';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';

  Future<List<Anime>> fetchPopularMovies({int page = 1, List<int> genreIds = const []}) async {
    final genreParam = genreIds.isNotEmpty
        ? '&with_genres=${genreIds.join(',')}'
        : '';
    final url = Uri.parse(
      '$_baseUrl/discover/movie?api_key=$_apiKey&language=en-US&sort_by=popularity.desc&page=$page$genreParam',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to load movies (status ${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>? ?? [];

    return results
        .map((item) => _movieFromJson(item as Map<String, dynamic>))
        .where((m) => m.imageUrl.isNotEmpty)
        .toList();
  }

  Anime _movieFromJson(Map<String, dynamic> json) {
    final posterPath = json['poster_path'] as String?;
    final genreIds = json['genre_ids'] as List<dynamic>? ?? [];

    return Anime(
      malId: json['id'] as int,
      title: json['title'] as String? ?? 'Unknown',
      imageUrl: posterPath != null ? '$_imageBase$posterPath' : '',
      synopsis: json['overview'] as String? ?? 'No synopsis available.',
      score: (json['vote_average'] as num?)?.toDouble(),
      genres: genreIds.map((id) => _genreLabel(id as int)).toList(),
      source: AnimeSource.jikan,
      isMovie: true,
    );
  }

  // TMDB genre id → human-readable label
  String _genreLabel(int id) {
    const map = {
      28: 'Action', 12: 'Adventure', 16: 'Animation',
      35: 'Comedy', 80: 'Crime', 99: 'Documentary',
      18: 'Drama', 10751: 'Family', 14: 'Fantasy',
      36: 'History', 27: 'Horror', 10402: 'Music',
      9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi',
      10770: 'TV Movie', 53: 'Thriller', 10752: 'War',
      37: 'Western',
    };
    return map[id] ?? 'Other';
  }
}