import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/anime.dart';

class AnilistApiService {
  AnilistApiService._();
  static final AnilistApiService instance = AnilistApiService._();

  static const String _endpoint = 'https://graphql.anilist.co';

  // genre_in matches anime with ANY of the listed genres (OR, same
  // semantics as Jikan's comma-separated genres param above).
  static const String _topAnimeQuery = r'''
    query ($page: Int, $perPage: Int, $genre_in: [String]) {
      Page(page: $page, perPage: $perPage) {
        media(type: ANIME, sort: SCORE_DESC, genre_in: $genre_in, isAdult: false) {
          id
          title {
            romaji
            english
          }
          description(asHtml: false)
          averageScore
          coverImage {
            large
          }
          genres
        }
      }
    }
  ''';

  Future<List<Anime>> fetchTopAnime({
    int page = 1,
    int perPage = 15,
    List<String>? genreNames,
  }) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': _topAnimeQuery,
        'variables': {
          'page': page,
          'perPage': perPage,
          if (genreNames != null && genreNames.isNotEmpty) 'genre_in': genreNames,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load AniList anime (status ${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final mediaList = body['data']?['Page']?['media'] as List<dynamic>? ?? [];

    return mediaList
        .map((item) => Anime.fromAniListJson(item as Map<String, dynamic>))
        .toList();
  }
}