// Static TMDB genre catalog — TMDB genre IDs/names never change, so no
// fetch is needed. Single source of truth shared by DiscoverScreen (for
// querying TMDB and labeling movie genre ids) and HomeScreen/LikedAnimeScreen
// (for offering the full movie genre list in the Liked filter sheet).
class TmdbGenres {
  TmdbGenres._();

  static const List<Map<String, dynamic>> data = [
    {'id': 28, 'name': 'Action'},
    {'id': 12, 'name': 'Adventure'},
    {'id': 16, 'name': 'Animation'},
    {'id': 35, 'name': 'Comedy'},
    {'id': 80, 'name': 'Crime'},
    {'id': 99, 'name': 'Documentary'},
    {'id': 18, 'name': 'Drama'},
    {'id': 10751, 'name': 'Family'},
    {'id': 14, 'name': 'Fantasy'},
    {'id': 36, 'name': 'History'},
    {'id': 27, 'name': 'Horror'},
    {'id': 10402, 'name': 'Music'},
    {'id': 9648, 'name': 'Mystery'},
    {'id': 10749, 'name': 'Romance'},
    {'id': 878, 'name': 'Sci-Fi'},
    {'id': 10770, 'name': 'TV Movie'},
    {'id': 53, 'name': 'Thriller'},
    {'id': 10752, 'name': 'War'},
    {'id': 37, 'name': 'Western'},
  ];

  static List<String> get names =>
      (data.map((g) => g['name'] as String).toList()..sort());

  static String labelFor(int id) {
    for (final g in data) {
      if (g['id'] == id) return g['name'] as String;
    }
    return 'Other';
  }
}