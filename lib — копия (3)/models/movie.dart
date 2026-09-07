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

  /// IMDb id (формат `tt1234567`). Нужен для vidsrc и для OpenSubtitles.
  final String? imdbId;

  /// TMDB id. Нужен для OpenSubtitles (там TMDB — основной идентификатор).
  final int? tmdbId;

  /// Идентификатор элемента на archive.org (например `night_of_the_living_dead`).
  /// Если задан — фильм проигрывается напрямую через Internet Archive,
  /// без vidsrc. Резолвится в URL .mp4 через [ArchiveOrgService.resolveStream].
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

  /// Парсинг из ответа kinopoisk.dev (v1.4).
  factory Movie.fromKinopoisk(Map<String, dynamic> json) {
    final rating = json['rating'] as Map<String, dynamic>?;
    final poster = json['poster'] as Map<String, dynamic>?;
    final backdrop = json['backdrop'] as Map<String, dynamic>?;
    final externalId = json['externalId'] as Map<String, dynamic>?;

    double bestRating() {
      final kp = (rating?['kp'] as num?)?.toDouble() ?? 0;
      final imdb = (rating?['imdb'] as num?)?.toDouble() ?? 0;
      return kp > 0 ? kp : imdb;
    }

    return Movie(
      id: json['id'] as int,
      title: (json['name'] as String?)?.isNotEmpty == true
          ? json['name'] as String
          : (json['alternativeName'] as String? ?? ''),
      overview: json['description'] as String? ??
          json['shortDescription'] as String? ??
          '',
      posterUrl: (poster?['url'] as String?) ??
          (poster?['previewUrl'] as String?) ??
          '',
      backdropUrl:
          (backdrop?['url'] as String?) ?? (poster?['url'] as String?) ?? '',
      releaseDate: (json['year']?.toString()) ?? '',
      voteAverage: bestRating(),
      imdbId: externalId?['imdb'] as String?,
      tmdbId: (externalId?['tmdb'] as num?)?.toInt(),
    );
  }

  /// Какой ID отдать в vidsrc.to. Предпочитаем IMDb (стабильнее), потом TMDB.
  String get _vidsrcId =>
      imdbId ?? (tmdbId?.toString() ?? '');

  bool get isPlayable => _vidsrcId.isNotEmpty;

  VideoItem toVideoItem() {
    return VideoItem(
      id: 'kp_movie_$id',
      // Для OpenSubtitles нужен TMDB id — кладём его в youtubeId
      // (player_provider читает оттуда).
      youtubeId: tmdbId?.toString() ?? '',
      imdbId: imdbId,
      title: title,
      sourceType: 'vidapi',
      // videoUrl используется как первичный embed URL (на случай отображения
      // ссылки или фоллбэка). Реальный поток вытащит VidsrcExtractor.
      videoUrl: imdbId != null
          ? 'https://vidsrc.xyz/embed/movie?imdb=$imdbId'
          : 'https://vidsrc.xyz/embed/movie?tmdb=$_vidsrcId',
      description: overview,
      thumbnailUrl: posterUrl,
      durationSec: 0,
    );
  }

  @override
  List<Object?> get props => [id, title];
}
