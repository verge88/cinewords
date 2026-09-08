import 'package:equatable/equatable.dart';

import 'video_item.dart';

class Movie extends Equatable {
  final int id;
  final String title;
  final String overview;
  final String posterUrl;
  final String backdropUrl;
  final String releaseDate;
  final double voteAverage;

  /// IMDb ID в формате tt1234567.
  ///
  /// Используется VidSpark и OpenSubtitles.
  final String? imdbId;

  /// TMDB ID.
  ///
  /// Используется как резервный идентификатор VidSpark
  /// и основной идентификатор для загрузки субтитров.
  final int? tmdbId;

  /// Идентификатор фильма на archive.org.
  ///
  /// Если указан, фильм воспроизводится через media_kit
  /// по прямому URL, без VidSpark.
  final String? archiveId;

  const Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterUrl,
    required this.backdropUrl,
    required this.releaseDate,
    required this.voteAverage,
    this.imdbId,
    this.tmdbId,
    this.archiveId,
  });

  /// Парсинг ответа kinopoisk.dev v1.4.
  factory Movie.fromKinopoisk(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>?;
    final poster = json['poster'] as Map<String, dynamic>?;
    final backdrop = json['backdrop'] as Map<String, dynamic>?;
    final externalId = json['externalId'] as Map<String, dynamic>?;

    double bestRating() {
      final kinopoisk =
          (rating?['kp'] as num?)?.toDouble() ?? 0;

      final imdb =
          (rating?['imdb'] as num?)?.toDouble() ?? 0;

      return kinopoisk > 0 ? kinopoisk : imdb;
    }

    return Movie(
      id: json['id'] as int,
      title: (json['name'] as String?)?.isNotEmpty == true
          ? json['name'] as String
          : (json['alternativeName'] as String? ?? ''),
      overview:
          json['description'] as String? ??
          json['shortDescription'] as String? ??
          '',
      posterUrl:
          poster?['url'] as String? ??
          poster?['previewUrl'] as String? ??
          '',
      backdropUrl:
          backdrop?['url'] as String? ??
          poster?['url'] as String? ??
          '',
      releaseDate: json['year']?.toString() ?? '',
      voteAverage: bestRating(),
      imdbId: externalId?['imdb'] as String?,
      tmdbId: (externalId?['tmdb'] as num?)?.toInt(),
    );
  }

  /// VidSpark поддерживает как IMDb, так и TMDB ID.
  ///
  /// IMDb используется в первую очередь.
  String get _vidSparkId {
    final imdb = imdbId?.trim();

    if (imdb != null && imdb.isNotEmpty) {
      return imdb;
    }

    return tmdbId?.toString() ?? '';
  }

  bool get isPlayable {
    if (archiveId != null && archiveId!.trim().isNotEmpty) {
      return true;
    }

    return _vidSparkId.isNotEmpty;
  }

  VideoItem toVideoItem() {
    final vidSparkId = _vidSparkId;

    return VideoItem(
      id: 'kp_movie_$id',

      // PlayerProvider использует это поле как TMDB ID
      // при загрузке субтитров фильма.
      youtubeId: tmdbId?.toString() ?? '',

      imdbId: imdbId,
      title: title,

      // Оставляем vidapi для совместимости с PlayerProvider:
      // при таком sourceType загружаются субтитры фильма.
      sourceType: 'vidapi',

      videoUrl: vidSparkId.isEmpty
          ? null
          : Uri.https(
              'vidspark.to',
              '/movie/$vidSparkId',
              const {
                'theme': '7C3AED',
              },
            ).toString(),

      description: overview,
      thumbnailUrl: posterUrl,
      durationSec: 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        imdbId,
        tmdbId,
        archiveId,
      ];
}
