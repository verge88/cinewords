import 'package:equatable/equatable.dart';

class VideoItem extends Equatable {
  final String id;
  final String youtubeId;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? channelName;
  final int? durationSeconds;
  final String difficulty;
  final String category;
  final List<String> tags;
  final int totalUniqueWords;
  final int viewCount;
  final bool isFeatured;

  const VideoItem({
    required this.id,
    required this.youtubeId,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.channelName,
    this.durationSeconds,
    this.difficulty = 'intermediate',
    this.category = 'general',
    this.tags = const [],
    this.totalUniqueWords = 0,
    this.viewCount = 0,
    this.isFeatured = false,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id'],
      youtubeId: json['youtube_id'],
      title: json['title'],
      description: json['description'],
      thumbnailUrl: json['thumbnail_url'],
      channelName: json['channel_name'],
      durationSeconds: json['duration_seconds'],
      difficulty: json['difficulty'] ?? 'intermediate',
      category: json['category'] ?? 'general',
      tags: List<String>.from(json['tags'] ?? []),
      totalUniqueWords: json['total_unique_words'] ?? 0,
      viewCount: json['view_count'] ?? 0,
      isFeatured: json['is_featured'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'youtube_id': youtubeId,
        'title': title,
        'description': description,
        'thumbnail_url': thumbnailUrl,
        'channel_name': channelName,
        'duration_seconds': durationSeconds,
        'difficulty': difficulty,
        'category': category,
        'tags': tags,
        'total_unique_words': totalUniqueWords,
      };

  String get formattedDuration {
    if (durationSeconds == null) return '';
    final d = Duration(seconds: durationSeconds!);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  String get difficultyLabel {
    switch (difficulty) {
      case 'beginner':
        return 'A1';
      case 'elementary':
        return 'A2';
      case 'intermediate':
        return 'B1';
      case 'upper_intermediate':
        return 'B2';
      case 'advanced':
        return 'C1';
      default:
        return 'B1';
    }
  }

  /// Returns a hex color value for the difficulty level.
  /// Use with Color() in UI widgets.
  int get difficultyColorValue {
    switch (difficulty) {
      case 'beginner':
        return 0xFF4CAF50;
      case 'elementary':
        return 0xFF8BC34A;
      case 'intermediate':
        return 0xFFFFC107;
      case 'upper_intermediate':
        return 0xFFFF9800;
      case 'advanced':
        return 0xFFF44336;
      default:
        return 0xFFFFC107;
    }
  }

  @override
  List<Object?> get props => [id, youtubeId];
}