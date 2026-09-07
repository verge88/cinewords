import '../models/subtitle_line.dart';

/// Utility to parse SRT / VTT format subtitles
class SubtitleParser {
  /// Parse SRT formatted subtitle text
  static List<SubtitleLine> parseSrt(
    String srtContent,
    String videoId, {
    String language = 'en',
  }) {
    final lines = <SubtitleLine>[];
    final blocks = srtContent.trim().split(RegExp(r'\n\s*\n'));
    int idx = 0;

    for (final block in blocks) {
      final parts = block.trim().split('\n');
      if (parts.length < 3) continue;

      final timeParts = parts[1].split(' --> ');
      if (timeParts.length != 2) continue;

      final startMs = _parseSrtTime(timeParts[0].trim());
      final endMs = _parseSrtTime(timeParts[1].trim());
      final text = parts.sublist(2).join(' ').replaceAll(RegExp(r'<[^>]+>'), '');

      lines.add(SubtitleLine(
        id: '${videoId}_${language}_$idx',
        videoId: videoId,
        language: language,
        startMs: startMs,
        endMs: endMs,
        text: text,
        sequenceIndex: idx,
      ));
      idx++;
    }

    return lines;
  }

  static int _parseSrtTime(String time) {
    // Format: 00:01:23,456
    final clean = time.replaceAll(',', '.').trim();
    final parts = clean.split(':');
    if (parts.length != 3) return 0;

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final secParts = parts[2].split('.');
    final seconds = int.tryParse(secParts[0]) ?? 0;
    final millis = int.tryParse(secParts.length > 1 ? secParts[1].padRight(3, '0') : '0') ?? 0;

    return (hours * 3600 + minutes * 60 + seconds) * 1000 + millis;
  }

  /// Parse VTT formatted subtitle text
  static List<SubtitleLine> parseVtt(
    String vttContent,
    String videoId, {
    String language = 'en',
  }) {
    // Remove WEBVTT header
    final content = vttContent.replaceFirst(RegExp(r'WEBVTT.*?\n\n', dotAll: true), '');
    return parseSrt(content, videoId, language: language);
  }
}
