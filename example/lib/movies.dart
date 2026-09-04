import 'dart:convert';

import 'package:http/http.dart' as http;

/// One row from https://api.sampleapis.com/movies/horror
class Movie {
  /// Creates a movie.
  const Movie({required this.id, required this.title, this.posterUrl});

  /// Stable id from the API.
  final int id;

  /// Display title. Lengths vary wildly in this feed, from "It" to a
  /// seventy-character behind-the-scenes title — which is exactly the case
  /// that punishes a guessed placeholder.
  final String title;

  /// Poster image, or null when the feed has none.
  final String? posterUrl;

  /// Parses one element of the array, tolerating the feed's rough edges.
  static Movie? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    final Object? title = raw['title'];
    if (id is! num || title is! String) return null;

    // The feed uses the literal string "N/A" for a missing poster, and a
    // couple of rows carry an ia.media-imdb.com host instead.
    final Object? poster = raw['posterURL'];
    final String? url =
        (poster is String && poster.isNotEmpty && poster != 'N/A')
            ? poster
            : null;

    return Movie(id: id.toInt(), title: title, posterUrl: url);
  }
}

/// Fetches the horror feed, keeping the last successful response so a refresh
/// can show something readable instead of a screen of bones.
class MovieRepository {
  /// The live endpoint.
  static final Uri endpoint =
      Uri.parse('https://api.sampleapis.com/movies/horror');

  List<Movie>? _cache;
  DateTime? _cachedAt;

  /// The last successful response, or null before the first one.
  List<Movie>? get cached => _cache;

  /// When [cached] was fetched.
  DateTime? get cachedAt => _cachedAt;

  /// Fetches the feed.
  ///
  /// [extraLatency] pads the request so the schedule's phases are observable
  /// on a fast connection — the endpoint often answers in well under 400 ms,
  /// which is precisely the window where Seam paints nothing at all.
  Future<List<Movie>> fetch({
    Duration extraLatency = Duration.zero,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final Future<void> padding = Future<void>.delayed(extraLatency);
    final http.Response response =
        await http.get(endpoint).timeout(timeout);
    await padding;

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Feed returned ${response.statusCode}',
        endpoint,
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Expected a JSON array of movies');
    }

    final List<Movie> movies = <Movie>[
      for (final Object? row in decoded)
        if (Movie.fromJson(row) case final Movie m) m,
    ];

    _cache = movies;
    _cachedAt = DateTime.now();
    return movies;
  }
}
