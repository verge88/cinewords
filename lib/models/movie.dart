import 'package:equatable/equatable.dart';

class Movie extends Equatable {
  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final String releaseDate;
  final double voteAverage;

  const Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] as int,
      title: json['title'] ?? '',
      overview: json['overview'] ?? '',
      posterPath: json['poster_path'] ?? '',
      backdropPath: json['backdrop_path'] ?? '',
      releaseDate: json['release_date'] ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get posterUrl => posterPath.isNotEmpty
      ? 'https://image.tmdb.org/t/p/w500$posterPath'
      : '';

  String get backdropUrl => backdropPath.isNotEmpty
      ? 'https://image.tmdb.org/t/p/original$backdropPath'
      : '';

  @override
  List<Object?> get props => [id, title];
}
