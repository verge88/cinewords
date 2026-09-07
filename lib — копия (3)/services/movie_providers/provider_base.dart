/// Контракт провайдера потоков для фильмов / сериалов.
///
/// Каждая реализация умеет вытащить прямую ссылку (.m3u8 / .mp4) по TMDB id
/// одного публичного бесплатного источника. Все провайдеры — чистый HTTP,
/// без headless WebView (вдохновлено архитектурой проекта `kodify-js/MovieDex`).
library;

abstract class MovieStreamProvider {
  String get name;

  /// Вернёт `null`, если источник недоступен или не нашёл фильм —
  /// тогда оркестратор пробует следующего провайдера.
  Future<MovieStream?> fetchStream({
    required int tmdbId,
    String? imdbId,
  });
}

/// Один вариант качества у потока (например, 1080p).
class StreamSource {
  final String quality; // '1080', '720', 'auto' и т.п.
  final String url;
  const StreamSource(this.quality, this.url);

  @override
  String toString() => 'StreamSource($quality, $url)';
}

class StreamSubtitle {
  final String url;
  final String language; // ISO-2 код: 'en', 'ru', ...
  final String label;
  const StreamSubtitle({
    required this.url,
    required this.language,
    this.label = '',
  });
}

class MovieStream {
  /// URL для воспроизведения (как правило — мастер-плейлист m3u8).
  final String url;
  final Map<String, String> headers;
  final List<StreamSource> qualities;
  final List<StreamSubtitle> subtitles;
  final String? audioLanguage;
  final String providerName;

  const MovieStream({
    required this.url,
    required this.headers,
    required this.providerName,
    this.qualities = const [],
    this.subtitles = const [],
    this.audioLanguage,
  });

  StreamSubtitle? subtitleFor(String lang) {
    for (final s in subtitles) {
      if (s.language.toLowerCase() == lang.toLowerCase()) return s;
    }
    return null;
  }
}

/// Утилита: нормализация кода языка (англ. название → ISO-2).
String normalizeLanguageCode(String raw) {
  final l = raw.toLowerCase().trim();
  if (l.isEmpty) return '';
  // Маппинг распространённых вариантов
  const map = {
    'english': 'en',
    'eng': 'en',
    'en-us': 'en',
    'en-gb': 'en',
    'russian': 'ru',
    'rus': 'ru',
    'ру': 'ru',
    'spanish': 'es',
    'french': 'fr',
    'german': 'de',
    'arabic': 'ar',
    'chinese': 'zh',
    'japanese': 'ja',
    'korean': 'ko',
    'hindi': 'hi',
  };
  if (map.containsKey(l)) return map[l]!;
  if (l.length >= 2) return l.substring(0, 2);
  return l;
}

/// Утилита: парсинг master m3u8 → список качеств.
/// Возвращает пустой список, если плейлист — это уже media-плейлист
/// (без `#EXT-X-STREAM-INF`).
List<StreamSource> parseMasterPlaylist(String body, String masterUrl) {
  final result = <StreamSource>[];
  final lines = body.split('\n');
  final base = masterUrl.contains('/')
      ? masterUrl.substring(0, masterUrl.lastIndexOf('/'))
      : masterUrl;

  String resolve(String streamLine) {
    final s = streamLine.trim();
    if (s.startsWith('http')) return s;
    if (s.startsWith('//')) return 'https:$s';
    if (s.startsWith('/')) {
      final u = Uri.parse(masterUrl);
      return '${u.scheme}://${u.host}$s';
    }
    if (s.startsWith('./')) return '$base/${s.substring(2)}';
    return '$base/$s';
  }

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      final m = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
      final quality = m?.group(1) ?? 'auto';
      if (i + 1 < lines.length) {
        final next = lines[i + 1].trim();
        if (next.isNotEmpty && !next.startsWith('#')) {
          result.add(StreamSource(quality, resolve(next)));
        }
      }
    }
  }

  // Сортируем по убыванию качества: лучшее первым
  result.sort((a, b) {
    final aq = int.tryParse(a.quality) ?? 0;
    final bq = int.tryParse(b.quality) ?? 0;
    return bq.compareTo(aq);
  });
  return result;
}
