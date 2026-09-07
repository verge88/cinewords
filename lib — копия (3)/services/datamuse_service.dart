import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Datamuse — полностью бесплатный API без ключа и лимитов.
/// Поддерживает префикс-поиск, синонимы, антонимы, "means like",
/// рифмы, "sounds like", метаданные (определения, частоты, части речи).
/// Документация: https://www.datamuse.com/api/
class DatamuseService {
  static const _host = 'api.datamuse.com';

  /// Главный поиск: возвращает слова + краткие метаданные (md=dpsrf):
  /// d — definitions, p — parts of speech, s — syllable count,
  /// r — pronunciation (Arpabet), f — frequency per million.
  static Future<List<DatamuseWord>> search({
    required String query,
    DatamuseMode mode = DatamuseMode.startsWith,
    int max = 40,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final params = <String, String>{
      'max': max.toString(),
      'md': 'dpsrf',
    };

    switch (mode) {
      case DatamuseMode.startsWith:
        params['sp'] = '$q*';
        break;
      case DatamuseMode.meansLike:
        params['ml'] = q;
        break;
      case DatamuseMode.synonyms:
        params['rel_syn'] = q;
        break;
      case DatamuseMode.antonyms:
        params['rel_ant'] = q;
        break;
      case DatamuseMode.rhymes:
        params['rel_rhy'] = q;
        break;
      case DatamuseMode.soundsLike:
        params['sl'] = q;
        break;
      case DatamuseMode.triggers:
        params['rel_trg'] = q;
        break;
    }

    final url = Uri.https(_host, '/words', params);

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('[Datamuse] HTTP ${res.statusCode}');
        return const [];
      }
      final List<dynamic> data = jsonDecode(res.body);
      return data.map((e) => DatamuseWord.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[Datamuse] error: $e');
      return const [];
    }
  }

  /// Подсказки для автодополнения — `/sug?s=...` (быстрее чем `/words`)
  static Future<List<String>> suggestions(String prefix,
      {int max = 10}) async {
    final p = prefix.trim();
    if (p.isEmpty) return const [];
    final url = Uri.https(_host, '/sug', {'s': p, 'max': '$max'});
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return const [];
      final List<dynamic> data = jsonDecode(res.body);
      return data.map((e) => (e['word'] ?? '').toString()).toList();
    } catch (e) {
      debugPrint('[Datamuse] suggestion error: $e');
      return const [];
    }
  }
}

enum DatamuseMode {
  startsWith,
  meansLike,
  synonyms,
  antonyms,
  rhymes,
  soundsLike,
  triggers,
}

class DatamuseWord {
  final String word;
  final int score;
  final List<String> tags; // raw tags: 'n', 'v', 'adj', 'f:1.234' etc.
  final List<String> defs; // raw defs: "n\tA tropical fruit..."
  final int? syllables;

  const DatamuseWord({
    required this.word,
    required this.score,
    this.tags = const [],
    this.defs = const [],
    this.syllables,
  });

  factory DatamuseWord.fromJson(Map<String, dynamic> json) {
    return DatamuseWord(
      word: (json['word'] ?? '').toString(),
      score: (json['score'] ?? 0) is int
          ? json['score'] as int
          : ((json['score'] as num?)?.toInt() ?? 0),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      defs: (json['defs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      syllables: json['numSyllables'] as int?,
    );
  }

  /// Частота на миллион слов (из тега `f:...`)
  double? get frequency {
    for (final t in tags) {
      if (t.startsWith('f:')) {
        return double.tryParse(t.substring(2));
      }
    }
    return null;
  }

  /// Произношение в IPA-виде нет, есть Arpabet (тег `pron:...`)
  String? get arpabet {
    for (final t in tags) {
      if (t.startsWith('pron:')) return t.substring(5);
    }
    return null;
  }

  /// Парсит части речи из тегов
  List<String> get partsOfSpeech {
    const map = {
      'n': 'noun',
      'v': 'verb',
      'adj': 'adjective',
      'adv': 'adverb',
      'u': 'other',
      'prop': 'proper',
    };
    return tags
        .where((t) => map.containsKey(t))
        .map((t) => map[t]!)
        .toList();
  }

  /// Парсит определения: каждое имеет вид "POS\tDefinition text"
  List<DatamuseDef> get definitions {
    final out = <DatamuseDef>[];
    for (final d in defs) {
      final parts = d.split('\t');
      if (parts.length >= 2) {
        out.add(DatamuseDef(pos: parts[0], text: parts.sublist(1).join(' ')));
      } else {
        out.add(DatamuseDef(pos: '', text: d));
      }
    }
    return out;
  }
}

class DatamuseDef {
  final String pos;
  final String text;
  const DatamuseDef({required this.pos, required this.text});
}
