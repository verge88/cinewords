import 'package:equatable/equatable.dart';

class VideoItem extends Equatable {
  final String id;
  final String youtubeId;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? channelName;
  final int? durationSec;
  final String difficulty;
  final String category;
  final List<String> keywords;
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
    this.durationSec,
    this.difficulty = 'intermediate',
    this.category = 'general',
    this.keywords = const [],
    this.totalUniqueWords = 0,
    this.viewCount = 0,
    this.isFeatured = false,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id'] ?? '',
      youtubeId: json['youtube_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      thumbnailUrl: json['thumbnail_url'],
      channelName: json['channel_name'] ?? json['author'], // Fallback if still named old way in some rows
      durationSec: json['duration_sec'] ?? ((json['duration_ms'] ?? json['duration_seconds'] ?? 0) ~/ 1000),
      difficulty: json['difficulty'] ?? 'intermediate',
      category: json['category'] ?? 'general',
      keywords: List<String>.from(json['keywords'] ?? json['tags'] ?? []),
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
        'duration_sec': durationSec,
        'difficulty': difficulty,
        'category': category,
        // keywords and total_unique_words are not in the 'videos' table schema in schema.sql
      };

  String get formattedDuration {
    if (durationSec == null) return '';
    final d = Duration(seconds: durationSec!);
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