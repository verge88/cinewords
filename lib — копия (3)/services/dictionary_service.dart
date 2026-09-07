import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:translator/translator.dart';
import '../models/subtitle_line.dart';

class DictionaryResult {
  final String word;
  final String? phonetic;
  final String? translation;

  const DictionaryResult({
    required this.word,
    this.phonetic,
    this.translation,
  });
}

class DictionaryService {
  static final _translator = GoogleTranslator();

  /// Looks up phonetics from free Dictionary API and translates via Google.
  static Future<DictionaryResult> lookupWord(String word, {String from = 'en', String to = 'ru'}) async {
    String? phonetic;
    String? translation;

    // 1. Get Phonetics
    try {
      final url = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          final entry = data.first;
          // Free API returns multiple phonetics sometimes, find the first non-empty text
          if (entry['phonetics'] != null) {
            for (var p in entry['phonetics']) {
              if (p['text'] != null && p['text'].toString().isNotEmpty) {
                phonetic = p['text'];
                break;
              }
            }
          }
          // Fallback to top-level phonetic if available
          phonetic ??= entry['phonetic'];
        }
      }
    } catch (e) {
      debugPrint('[DictionaryService] Error getting phonetics: $e');
    }

    // 2. Translate word
    try {
      final result = await _translator.translate(word, from: from, to: to);
      translation = result.text;
    } catch (e) {
      debugPrint('[DictionaryService] Error translating word: $e');
    }

    return DictionaryResult(
      word: word,
      phonetic: phonetic,
      translation: translation,
    );
  }

  /// Translates a full sentence for context
  static Future<String?> translateSentence(String sentence, {String from = 'en', String to = 'ru'}) async {
    try {
      final result = await _translator.translate(sentence, from: from, to: to);
      return result.text;
    } catch (e) {
      debugPrint('[DictionaryService] Error translating sentence: $e');
      return null;
    }
  }

  /// Translates an entire transcript in batches to avoid API rate limits
  static Future<List<SubtitleLine>> translateSubtitles(
      List<SubtitleLine> englishSubs,
      {String from = 'en', String to = 'ru'}) async {
    
    if (englishSubs.isEmpty) return [];
    
    final List<SubtitleLine> russianSubs = [];
    final int chunkSize = 50; 
    const separator = ' \n~~~\n '; // A separator Google Translate usually leaves intact

    for (var i = 0; i < englishSubs.length; i += chunkSize) {
      final end = (i + chunkSize < englishSubs.length)
          ? i + chunkSize
          : englishSubs.length;
      final chunk = englishSubs.sublist(i, end);

      // Join with separator
      final combinedText = chunk.map((c) => c.text).join(separator);

      try {
        final result = await _translator.translate(combinedText, from: from, to: to);
        final translatedText = result.text;
        
        // Split back by separator
        // Note: Translation APIs sometimes mess up spacing around separators
        final splitTranslated = translatedText.split(RegExp(r'\n?~~~\n?|\n \n\n|\n\n\n')); 
        
        // Clean up any remaining artifacts and map back to lines
        for (var j = 0; j < chunk.length; j++) {
          final original = chunk[j];
          String translatedLine = '';
          
          if (j < splitTranslated.length) {
            translatedLine = splitTranslated[j].replaceAll('~', '').trim();
          }

          russianSubs.add(SubtitleLine(
            id: '${original.id}_ru',
            videoId: original.videoId,
            language: to,
            startMs: original.startMs,
            endMs: original.endMs,
            text: translatedLine.isNotEmpty ? translatedLine : original.text,
            sequenceIndex: original.sequenceIndex,
          ));
        }
      } catch (e) {
        debugPrint('[DictionaryService] Error batch translating chunk $i: $e');
        // Fallback: Just return the original text if translation fails for this chunk
        for (final original in chunk) {
          russianSubs.add(SubtitleLine(
            id: '${original.id}_ru',
            videoId: original.videoId,
            language: to,
            startMs: original.startMs,
            endMs: original.endMs,
            text: original.text, 
            sequenceIndex: original.sequenceIndex,
          ));
        }
      }
    }

    return russianSubs;
  }
}
