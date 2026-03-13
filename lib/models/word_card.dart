import 'package:equatable/equatable.dart';

class WordCard extends Equatable {
  final String id;
  final String userId;
  final String word;
  final String? translation;
  final String? contextSentence;
  final String? contextVideoId;
  final int? contextTimestampMs;
  final String? phonetic;
  final double difficultyScore;
  final int repetitionCount;
  final DateTime nextReviewAt;
  final double easeFactor;
  final int intervalDays;
  final String status;
  final String type;

  const WordCard({
    required this.id,
    required this.userId,
    required this.word,
    this.translation,
    this.contextSentence,
    this.contextVideoId,
    this.contextTimestampMs,
    this.phonetic,
    this.difficultyScore = 0.5,
    this.repetitionCount = 0,
    required this.nextReviewAt,
    this.easeFactor = 2.5,
    this.intervalDays = 1,
    this.status = 'new',
    this.type = 'word',
  });

  factory WordCard.fromJson(Map<String, dynamic> json) {
    return WordCard(
      id: json['id'],
      userId: json['user_id'],
      word: json['word'],
      translation: json['translation'],
      contextSentence: json['context_sentence'],
      contextVideoId: json['context_video_id'],
      contextTimestampMs: json['context_timestamp_ms'],
      phonetic: json['phonetic'],
      difficultyScore: (json['difficulty_score'] as num?)?.toDouble() ?? 0.5,
      repetitionCount: json['repetition_count'] ?? 0,
      nextReviewAt: DateTime.parse(json['next_review_at']),
      easeFactor: (json['ease_factor'] as num?)?.toDouble() ?? 2.5,
      intervalDays: json['interval_days'] ?? 1,
      status: json['status'] ?? 'new',
      type: json['item_type'] ?? 'word',
    );
  }

  bool get isDueForReview {
    final nowWithSkew = DateTime.now().toUtc().add(const Duration(minutes: 5));
    return nowWithSkew.isAfter(nextReviewAt.toUtc());
  }

  String get statusEmoji {
    switch (status) {
      case 'new': return '🆕';
      case 'learning': return '📖';
      case 'review': return '🔄';
      case 'mastered': return '⭐';
      default: return '📝';
    }
  }

  @override
  List<Object?> get props => [id, word];
}
