import '../models/subtitle_line.dart';

class VttParser {
  static List<SubtitleLine> parse(String vttContent, String videoId, String language) {
    final List<SubtitleLine> results = [];
    final content = vttContent.replaceAll('\r\n', '\n');
    final lines = content.split('\n');
    
    final RegExp timestampRegex = RegExp(r'(?:(\d{2}):)?(\d{2}):(\d{2})[.,](\d{3}) --> (?:(\d{2}):)?(\d{2}):(\d{2})[.,](\d{3})');
    
    String? currentTimestamp;
    List<String> currentTextLines = [];
    int index = 0;

    void addCurrentCue() {
      if (currentTimestamp != null && currentTextLines.isNotEmpty) {
        final match = timestampRegex.firstMatch(currentTimestamp!);
        if (match != null) {
          final startMs = _parseMatch(match, isStart: true);
          final endMs = _parseMatch(match, isStart: false);
          
          final text = currentTextLines.join(' ')
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll(RegExp(r'\{[^\}]*\}'), '')
              .trim();
              
          if (text.isNotEmpty) {
            results.add(SubtitleLine(
              id: '${videoId}_${startMs}_$language',
              videoId: videoId,
              text: text,
              translation: '',
              startMs: startMs,
              endMs: endMs,
              language: language,
              sequenceIndex: index++,
            ));
          }
        }
      }
      currentTimestamp = null;
      currentTextLines = [];
    }

    for (var line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;
      if (trimmedLine.startsWith('WEBVTT')) continue;
      
      if (timestampRegex.hasMatch(trimmedLine)) {
        // Если это новый таймстемп, сохраняем предыдущую реплику
        addCurrentCue();
        currentTimestamp = trimmedLine;
      } else if (currentTimestamp != null) {
        // Если у нас уже есть активный таймстемп, всё остальное - текст реплики
        currentTextLines.add(trimmedLine);
      }
    }
    
    // Не забываем добавить последнюю реплику
    addCurrentCue();
    
    return results;
  }

  static int _parseMatch(RegExpMatch match, {required bool isStart}) {
    final offset = isStart ? 0 : 4;
    final hStr = match.group(1 + offset);
    final h = hStr != null ? int.parse(hStr) : 0;
    final m = int.parse(match.group(2 + offset)!);
    final s = int.parse(match.group(3 + offset)!);
    final ms = int.parse(match.group(4 + offset)!);
    
    return h * 3600000 + m * 60000 + s * 1000 + ms;
  }
}
