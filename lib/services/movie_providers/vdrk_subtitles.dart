import 'provider_base.dart';

/// Кэш субтитров vdrk.site (`https://cache.vdrk.site/v2/movie/{tmdb}/{Lang}.vtt`).
///
/// Этот эндпоинт раньше был внутренним для плеера Vidzee, но теперь они
/// отдают его публично с прямыми VTT-файлами для большинства популярных
/// фильмов и доброй сотни языков. Никакого ключа не требует.
///
/// Используем как первый источник субтитров для фильмов: гораздо быстрее
/// и стабильнее OpenSubtitles. Если файла нет — VDRK молча отдаст пустой
/// ответ, и сработает фоллбэк на OpenSubtitles.
class VdrkSubtitles {
  static const String _base = 'https://cache.vdrk.site/v2';

  /// Конструирует "оптимистичный" список — мы не делаем HEAD-запросы
  /// (HEAD на этом CDN врёт про размер), просто возвращаем URL'ы.
  /// Загрузчик в `PlayerProvider` обработает 404 как обычную ошибку
  /// и пойдёт дальше по цепочке фоллбэков.
  static List<StreamSubtitle> buildSubtitles(int tmdbId) {
    String url(String name) => '$_base/movie/$tmdbId/$name.vtt';
    return [
      StreamSubtitle(url: url('English'), language: 'en', label: 'English'),
      StreamSubtitle(url: url('Russian'), language: 'ru', label: 'Russian'),
    ];
  }
}
