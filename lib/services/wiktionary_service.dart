import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WiktionaryDefinition {
  final String word;
  final String partOfSpeech;
  final String definition;
  final List<String> examples;

  const WiktionaryDefinition({
    required this.word,
    required this.partOfSpeech,
    required this.definition,
    this.examples = const [],
  });
}

/// Бесплатный API: https://en.wiktionary.org/api/rest_v1/page/definition/{word}
/// Без ключа, без лимитов, доступен из РФ без VPN.
class WiktionaryService {
  static final Map<String, List<WiktionaryDefinition>> _cache = {};

  static Future<List<WiktionaryDefinition>> lookup(String word) async {
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return const [];
    if (_cache.containsKey(key)) return _cache[key]!;

    final url = Uri.parse(
      'https://en.wiktionary.org/api/rest_v1/page/definition/$key',
    );

    try {
      final res = await http
          .get(url, headers: {'accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('[Wiktionary] HTTP ${res.statusCode} for $key');
        return const [];
      }

      final Map<String, dynamic> data = jsonDecode(res.body);
      final List<dynamic>? en = data['en'] as List<dynamic>?;
      if (en == null) return const [];

      final result = <WiktionaryDefinition>[];
      for (final block in en) {
        final pos = (block['partOfSpeech'] ?? '').toString();
        final defs = block['definitions'] as List<dynamic>? ?? const [];
        for (final d in defs) {
          final raw = (d['definition'] ?? '').toString();
          final cleaned = _stripHtml(raw).trim();
          if (cleaned.isEmpty) continue;
          final examples = <String>[];
          final exs = d['examples'] as List<dynamic>? ?? const [];
          for (final ex in exs) {
            final cleanedEx = _stripHtml(ex.toString()).trim();
            if (cleanedEx.isNotEmpty) examples.add(cleanedEx);
          }
          result.add(WiktionaryDefinition(
            word: key,
            partOfSpeech: pos,
            definition: cleaned,
            examples: examples,
          ));
        }
      }
      _cache[key] = result;
      return result;
    } catch (e) {
      debugPrint('[Wiktionary] error for $key: $e');
      return const [];
    }
  }

  static String _stripHtml(String s) {
    return s
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Замаскировать слово в определении звёздочками, чтобы в упражнении
  /// «определение → слово» оно случайно не появилось в тексте.
  static String maskWord(String text, String word) {
    if (word.length < 2) return text;
    return text.replaceAll(
      RegExp(RegExp.escape(word), caseSensitive: false),
      '*' * word.length,
    );
  }
}
