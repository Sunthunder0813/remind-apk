import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/anime.dart';
import '../models/anime_genre.dart';

// Talks to the free Jikan API (https://jikan.moe) to fetch anime data.
// No API key required.
class AnimeApiService {
  AnimeApiService._();
  static final AnimeApiService instance = AnimeApiService._();

  static const String _baseUrl = 'https://api.jikan.moe/v4';

  // Fetches a page of top-ranked anime, optionally filtered by a genre id.
  // When genreId is null, returns the overall top-ranked list.
  // When genreId is set, queries the general anime search endpoint
  // filtered by that genre, sorted by score (Jikan's /top/anime endpoint
  // does not support genre filtering, so we use /anime with genres+order_by).
  // genreIds supports multiple selections — Jikan's /anime endpoint accepts
  // a comma-separated list and matches anime with ANY of the listed genres
  // (an OR, not an AND). DiscoverScreen re-ranks results afterward so anime
  // matching MORE of the selected genres surface first.
  Future<List<Anime>> fetchTopAnime({int page = 1, List<int>? genreIds}) async {
    final Uri url;

    if (genreIds == null || genreIds.isEmpty) {
      url = Uri.parse('$_baseUrl/top/anime?page=$page');
    } else {
      url = Uri.parse(
        '$_baseUrl/anime?genres=${genreIds.join(',')}&order_by=score&sort=desc&page=$page',
      );
    }

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to load anime (status ${response.statusCode})');
    }

    final Map<String, dynamic> body = jsonDecode(response.body);
    final List<dynamic> data = body['data'] as List<dynamic>;

    return data
        .map((item) => Anime.fromJikanJson(item as Map<String, dynamic>))
        .toList();
  }

  // Fetches the full list of anime genres (e.g. Action, Romance, Comedy)
  Future<List<AnimeGenre>> fetchGenres() async {
    final url = Uri.parse('$_baseUrl/genres/anime');
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to load genres (status ${response.statusCode})');
    }

    final Map<String, dynamic> body = jsonDecode(response.body);
    final List<dynamic> data = body['data'] as List<dynamic>;

    final genres = data
        .map((item) => AnimeGenre.fromJson(item as Map<String, dynamic>))
        .toList();

    // Sort alphabetically so the filter bar is easy to scan
    genres.sort((a, b) => a.name.compareTo(b.name));
    return genres;
  }
}