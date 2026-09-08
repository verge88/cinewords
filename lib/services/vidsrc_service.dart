import '../models/movie.dart';

class VidsrcService {
  static const String host = 'vidsrcme.ru';

  /// Возвращает IMDb ID, если он корректный, иначе TMDB ID.
  static String? movieId(Movie movie) {
    final imdb = movie.imdbId?.trim();

    if (imdb != null && RegExp(r'^tt\d+$').hasMatch(imdb)) {
      return imdb;
    }

    if (movie.tmdbId != null && movie.tmdbId! > 0) {
      return movie.tmdbId.toString();
    }

    return null;
  }

  static Uri movieEmbedUri(
    Movie movie, {
    double? startAt,
    bool autoplay = false,
  }) {
    final id = movieId(movie);

    if (id == null) {
      throw StateError(
        'Для фильма отсутствует корректный IMDb или TMDB ID',
      );
    }

    return Uri.https(
      host,
      '/embed/movie/$id',
      {
        'autoplay': autoplay ? '1' : '0',
        'ds_lang': 'en,ru',
        if (startAt != null && startAt > 0)
          'startAt': startAt.floor().toString(),
      },
    );
  }
}
