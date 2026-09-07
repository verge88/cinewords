import 'package:flutter/foundation.dart';
import 'movie_providers/provider_base.dart';
import 'movie_providers/rivestream_provider.dart';
import 'movie_providers/vdrk_subtitles.dart';

/// Оркестратор провайдеров видео-потоков.
///
/// На начало 2026 единственный надёжный публичный JSON-источник прямых
/// .m3u8 — Rivestream Scraper (`scrapper.rivestream.org`). Старые
/// `vidsrc.to` / `vidsrc.xyz` / `vidzee` шифруют ссылки, `flix.1anime.app`
/// в maintenance, `vidsrc.su` стал JS-SPA — все три выкинули.
///
/// Дополнительно к видео-потоку дополняем результат субтитрами от
/// VDRK (`cache.vdrk.site`) — отдельный CDN, прямые VTT по TMDB id,
/// сильно быстрее OpenSubtitles.
class MovieStreamService {
  static final List<MovieStreamProvider> _providers = [
    RivestreamProvider(),
  ];

  static Future<MovieStream?> fetchStream({
    required int tmdbId,
    String? imdbId,
  }) async {
    MovieStream? stream;
    for (final p in _providers) {
      final t = DateTime.now();
      try {
        final s = await p.fetchStream(tmdbId: tmdbId, imdbId: imdbId);
        final ms = DateTime.now().difference(t).inMilliseconds;
        if (s != null) {
          debugPrint('[MovieStream] ${p.name} OK (${ms}ms): ${s.url}');
          stream = s;
          break;
        } else {
          debugPrint('[MovieStream] ${p.name} miss (${ms}ms)');
        }
      } catch (e) {
        debugPrint('[MovieStream] ${p.name} error: $e');
      }
    }
    if (stream == null) return null;

    // Дополняем субтитры VDRK-ссылками, если провайдер не вернул свои.
    final hasEn = stream.subtitleFor('en') != null;
    final hasRu = stream.subtitleFor('ru') != null;
    if (!hasEn || !hasRu) {
      final vdrk = VdrkSubtitles.buildSubtitles(tmdbId);
      final merged = <StreamSubtitle>[
        ...stream.subtitles,
        for (final s in vdrk)
          if (stream.subtitleFor(s.language) == null) s,
      ];
      stream = MovieStream(
        url: stream.url,
        headers: stream.headers,
        qualities: stream.qualities,
        subtitles: merged,
        audioLanguage: stream.audioLanguage,
        providerName: stream.providerName,
      );
      debugPrint(
          '[MovieStream] augmented subs with VDRK (en=${!hasEn}, ru=${!hasRu})');
    }
    return stream;
  }
}
