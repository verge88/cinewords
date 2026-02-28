import 'package:equatable/equatable.dart';

class SubtitleLine extends Equatable {
  final String id;
  final String videoId;
  final String language;
  final int startMs;
  final int endMs;
  final String text;
  final String? translation;
  final int sequenceIndex;

  const SubtitleLine({
    required this.id,
    required this.videoId,
    required this.language,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.translation,
    required this.sequenceIndex,
  });

  factory SubtitleLine.fromJson(Map<String, dynamic> json) {
    return SubtitleLine(
      id: json['id'],
      videoId: json['video_id'],
      language: json['language'] ?? 'en',
      startMs: json['start_ms'],
      endMs: json['end_ms'],
      text: json['text'],
      translation: json['translation'],
      sequenceIndex: json['sequence_index'],
    );
  }

  Map<String, dynamic> toJson() => {
        'video_id': videoId,
        'language': language,
        'start_ms': startMs,
        'end_ms': endMs,
        'text': text,
        'translation': translation,
        'sequence_index': sequenceIndex,
      };

  Duration get startDuration => Duration(milliseconds: startMs);
  Duration get endDuration => Duration(milliseconds: endMs);

  bool isActiveAt(Duration position) {
    return position >= startDuration && position <= endDuration;
  }

  /// Split text into individual tappable words
  List<String> get words {
    // Remove punctuation except apostrophes and hyphens within words
    final cleaned = text.replaceAll(RegExp(r"[^\w\s'-]"), '');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  @override
  List<Object?> get props => [id, startMs, endMs, text];
}
