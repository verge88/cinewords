import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/subtitle_line.dart';
import '../models/video_item.dart';
import '../services/youtube_service.dart';
import '../services/supabase_service.dart';
import '../services/dictionary_service.dart';
import '../services/open_subtitles_service.dart';
import '../utils/vtt_parser.dart';
import 'dart:async';


class PlayerProvider extends ChangeNotifier {
  final YouTubeService _ytService = YouTubeService();

  VideoItem? _currentVideo;
  List<SubtitleLine> _englishSubs = [];
  List<SubtitleLine> _russianSubs = [];
  SubtitleLine? _currentEnglishLine;
  SubtitleLine? _currentRussianLine;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _showTranslation = true;
  double _playbackSpeed = 1.0;
  double _subtitleScale = 1.0;
  bool _onVideoSubtitlesEnabled = true;
  double _subtitleBottomPadding = 80.0;
  bool _isLoadingSubs = false;
  String? _subtitleError;
  
  List<String> _availableQualities = [];
  String? _selectedQuality;

  VideoItem? get currentVideo => _currentVideo;
  List<SubtitleLine> get englishSubs => _englishSubs;
  List<SubtitleLine> get russianSubs => _russianSubs;
  SubtitleLine? get currentEnglishLine => _currentEnglishLine;
  SubtitleLine? get currentRussianLine => _currentRussianLine;
  Duration get position => _position;
  bool get isPlaying => _isPlaying;
  bool get showTranslation => _showTranslation;
  double get playbackSpeed => _playbackSpeed;
  double get subtitleScale => _subtitleScale;
  bool get onVideoSubtitlesEnabled => _onVideoSubtitlesEnabled;
  double get subtitleBottomPadding => _subtitleBottomPadding;
  bool get isLoadingSubs => _isLoadingSubs;
  String? get subtitleError => _subtitleError;
  List<String> get availableQualities => _availableQualities;
  String? get selectedQuality => _selectedQuality;

  Future<void> loadVideo(VideoItem video) async {
    prepareVideo(video, resetQualities: false);


    // Для фильмов (vidapi) загружаем субтитры из OpenSubtitles
    if (video.sourceType == 'vidapi') {
      await _loadMovieSubtitles(video);
      return;
    }

    // Для прямых источников (Internet Archive) — субтитры из URL,
    // если они приложены к VideoItem.
    if (video.sourceType == 'direct') {
      await _loadDirectSubtitles(video);
      return;
    }

    // Для YouTube видео — стандартный путь
    bool cached = false;
    try {
      final c = await SupabaseService.getSubtitles(video.id, language: 'en')
          .timeout(const Duration(seconds: 3));
      if (c.isNotEmpty) {
        _englishSubs = c;
        cached = true;
        debugPrint('[Subs] Loaded ${c.length} EN subs from cache');
      }
    } catch (_) {}

    if (!cached) {
      try {
        _englishSubs = await _ytService.getSubtitles(
          video.youtubeId,
          language: 'en',
          dbVideoId: video.id,
        );
        debugPrint('[Subs] YouTube EN subs: ${_englishSubs.length}');
        if (_englishSubs.isNotEmpty) {
          SupabaseService.saveSubtitles(_englishSubs).catchError((_) {});
        }
      } catch (e) {
        debugPrint('[Subs] EN failed: $e');
        _subtitleError = 'Could not load subtitles';
      }
    }

    _isLoadingSubs = false;
    notifyListeners();

    // Russian subs in background
    _loadRussianSubs(video);
  }

  /// Загрузка субтитров для прямых источников (Internet Archive и т.п.).
  /// Берёт URL из [VideoItem.subtitleUrl] / `subtitleUrlRu`, парсит .srt/.vtt
  /// и при отсутствии русских — автопереводит через DictionaryService.
  Future<void> _loadDirectSubtitles(VideoItem video) async {
    // Кэш в Supabase
    try {
      final cached = await SupabaseService.getSubtitles(video.id, language: 'en')
          .timeout(const Duration(seconds: 3));
      if (cached.isNotEmpty) {
        _englishSubs = cached;
      }
    } catch (_) {}

    if (_englishSubs.isEmpty && video.subtitleUrl != null) {
      try {
        final res = await _ytService.client
            .get(Uri.parse(video.subtitleUrl!))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final body = _decodeSubtitleBody(res.bodyBytes);
          _englishSubs = VttParser.parse(body, video.id, 'en');
          debugPrint('[DirectSubs] Loaded ${_englishSubs.length} EN lines');
          if (_englishSubs.isNotEmpty) {
            SupabaseService.saveSubtitles(_englishSubs).catchError((_) {});
          }
        }
      } catch (e) {
        debugPrint('[DirectSubs] EN fetch failed: $e');
      }
    }

    if (_englishSubs.isEmpty) {
      _subtitleError = 'Subtitles not found';
    }
    _isLoadingSubs = false;
    notifyListeners();

    // Русские: либо из URL, либо автоперевод
    try {
      if (video.subtitleUrlRu != null) {
        final res = await _ytService.client
            .get(Uri.parse(video.subtitleUrlRu!))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final body = _decodeSubtitleBody(res.bodyBytes);
          _russianSubs = VttParser.parse(body, video.id, 'ru');
        }
      }
    } catch (e) {
      debugPrint('[DirectSubs] RU fetch failed: $e');
    }

    if (_russianSubs.isEmpty && _englishSubs.isNotEmpty) {
      _isAutoTranslating = true;
      notifyListeners();
      try {
        _russianSubs = await DictionaryService.translateSubtitles(_englishSubs);
        if (_russianSubs.isNotEmpty) {
          SupabaseService.saveSubtitles(_russianSubs).catchError((_) {});
        }
      } catch (e) {
        debugPrint('[DirectSubs] Auto-translate failed: $e');
      }
      _isAutoTranslating = false;
    }
    notifyListeners();
  }

  /// SRT-файлы часто приходят в windows-1251/cp1251 (особенно русские) или
  /// latin-1. Сначала пробуем UTF-8, при ошибке — latin1.
  String _decodeSubtitleBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Загрузка субтитров для фильмов через OpenSubtitles API
  Future<void> _loadMovieSubtitles(
    VideoItem video,
  ) async {
    final tmdbId = int.tryParse(
      video.youtubeId.trim(),
    );

    final imdbId = video.imdbId?.trim();

    if (tmdbId == null &&
        (imdbId == null || imdbId.isEmpty)) {
      _isLoadingSubs = false;
      _subtitleError =
          'У фильма отсутствуют TMDB и IMDb ID';
      notifyListeners();
      return;
    }

    debugPrint(
      '[MovieSubs] Loading subtitles: '
      'TMDB=$tmdbId, IMDb=$imdbId',
    );

    // Кэш английских субтитров.
    try {
      final cached = await SupabaseService.getSubtitles(
        video.id,
        language: 'en',
      ).timeout(
        const Duration(seconds: 3),
      );

      if (cached.isNotEmpty) {
        _englishSubs = cached;

        debugPrint(
          '[MovieSubs] Loaded '
          '${cached.length} EN lines from cache',
        );
      }
    } catch (error) {
      debugPrint(
        '[MovieSubs] EN cache failed: $error',
      );
    }

    // Прямой URL от другого провайдера, если он задан.
    if (_englishSubs.isEmpty &&
        video.subtitleUrl != null &&
        video.subtitleUrl!.isNotEmpty) {
      try {
        final response = await _ytService.client
            .get(
              Uri.parse(video.subtitleUrl!),
            )
            .timeout(
              const Duration(seconds: 15),
            );

        if (response.statusCode == 200) {
          _englishSubs = VttParser.parse(
            _decodeSubtitleBody(
              response.bodyBytes,
            ),
            video.id,
            'en',
          );

          debugPrint(
            '[MovieSubs] Loaded '
            '${_englishSubs.length} EN lines '
            'from direct URL',
          );
        } else {
          debugPrint(
            '[MovieSubs] Direct EN URL returned '
            '${response.statusCode}',
          );
        }
      } catch (error) {
        debugPrint(
          '[MovieSubs] Direct EN failed: $error',
        );
      }
    }

    // OpenSubtitles: сначала TMDB, затем IMDb.
    if (_englishSubs.isEmpty) {
      try {
        final content =
            await OpenSubtitlesService.fetchSubtitle(
          tmdbId: tmdbId,
          imdbId: imdbId,
          language: 'en',
        );

        if (content != null &&
            content.trim().isNotEmpty) {
          _englishSubs = VttParser.parse(
            content,
            video.id,
            'en',
          );

          debugPrint(
            '[MovieSubs] Loaded '
            '${_englishSubs.length} EN lines '
            'from OpenSubtitles',
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[MovieSubs] EN subtitle fetch failed: '
          '$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    if (_englishSubs.isNotEmpty) {
      _subtitleError = null;

      SupabaseService.saveSubtitles(
        _englishSubs,
      ).catchError((_) {});
    } else {
      _subtitleError =
          'Английские реплики для этого фильма не найдены';
    }

    _isLoadingSubs = false;
    notifyListeners();

    // Русскую дорожку загружаем после английской.
    unawaited(
      _loadMovieRussianSubs(
        video,
        tmdbId,
        imdbId,
      ),
    );
  }


  /// Загрузка русских субтитров для фильма
  Future<void> _loadMovieRussianSubs(
    VideoItem video,
    int? tmdbId,
    String? imdbId,
  ) async {
    // Кэш русских субтитров.
    try {
      final cached = await SupabaseService.getSubtitles(
        video.id,
        language: 'ru',
      ).timeout(
        const Duration(seconds: 3),
      );

      if (cached.isNotEmpty) {
        _russianSubs = cached;
        notifyListeners();
        return;
      }
    } catch (error) {
      debugPrint(
        '[MovieSubs] RU cache failed: $error',
      );
    }

    // Прямая RU-дорожка, если присутствует.
    if (video.subtitleUrlRu != null &&
        video.subtitleUrlRu!.isNotEmpty) {
      try {
        final response = await _ytService.client
            .get(
              Uri.parse(video.subtitleUrlRu!),
            )
            .timeout(
              const Duration(seconds: 15),
            );

        if (response.statusCode == 200) {
          _russianSubs = VttParser.parse(
            _decodeSubtitleBody(
              response.bodyBytes,
            ),
            video.id,
            'ru',
          );

          if (_russianSubs.isNotEmpty) {
            SupabaseService.saveSubtitles(
              _russianSubs,
            ).catchError((_) {});

            notifyListeners();
            return;
          }
        }
      } catch (error) {
        debugPrint(
          '[MovieSubs] Direct RU failed: $error',
        );
      }
    }

    // OpenSubtitles: TMDB с fallback на IMDb.
    try {
      final content =
          await OpenSubtitlesService.fetchSubtitle(
        tmdbId: tmdbId,
        imdbId: imdbId,
        language: 'ru',
      );

      if (content != null &&
          content.trim().isNotEmpty) {
        _russianSubs = VttParser.parse(
          content,
          video.id,
          'ru',
        );

        debugPrint(
          '[MovieSubs] Loaded '
          '${_russianSubs.length} RU lines '
          'from OpenSubtitles',
        );

        if (_russianSubs.isNotEmpty) {
          SupabaseService.saveSubtitles(
            _russianSubs,
          ).catchError((_) {});

          notifyListeners();
          return;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[MovieSubs] RU subtitle fetch failed: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }

    // Если русской дорожки нет, переводим английскую.
    if (_englishSubs.isNotEmpty &&
        _russianSubs.isEmpty) {
      debugPrint(
        '[MovieSubs] RU not found; '
        'starting automatic translation',
      );

      _isAutoTranslating = true;
      notifyListeners();

      try {
        _russianSubs =
            await DictionaryService.translateSubtitles(
          _englishSubs,
        );

        if (_russianSubs.isNotEmpty) {
          SupabaseService.saveSubtitles(
            _russianSubs,
          ).catchError((_) {});
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[MovieSubs] Auto-translation failed: '
          '$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      } finally {
        _isAutoTranslating = false;
        notifyListeners();
      }
    }
  }


  bool _isAutoTranslating = false;
  bool get isAutoTranslating => _isAutoTranslating;

  Future<void> _loadRussianSubs(VideoItem video) async {
    _isAutoTranslating = false;
    try {
      final c = await SupabaseService.getSubtitles(video.id, language: 'ru')
          .timeout(const Duration(seconds: 3));
      if (c.isNotEmpty) {
        _russianSubs = c;
        notifyListeners();
        return;
      }
    } catch (_) {}

    try {
      _russianSubs = await _ytService.getSubtitles(
        video.youtubeId,
        language: 'ru',
        dbVideoId: video.id,
      );
      debugPrint('[Subs] RU subs from YT: ${_russianSubs.length}');
      if (_russianSubs.isNotEmpty) {
        SupabaseService.saveSubtitles(_russianSubs).catchError((_) {});
        notifyListeners();
        return; // Success!
      }
    } catch (_) {}

    // Fallback: Auto-translate english subtitles
    if (_englishSubs.isNotEmpty) {
      debugPrint('[Subs] Native RU subs not found. Auto-translating...');
      _isAutoTranslating = true;
      notifyListeners();

      try {
        _russianSubs = await DictionaryService.translateSubtitles(_englishSubs);
        debugPrint('[Subs] Auto-translated ${_russianSubs.length} lines.');
        if (_russianSubs.isNotEmpty) {
          // Cache to Supabase for next time so we don't translate again
          SupabaseService.saveSubtitles(_russianSubs).catchError((_) {});
        }
      } catch (e) {
        debugPrint('[Subs] Auto-translation failed: $e');
      }

      _isAutoTranslating = false;
      notifyListeners();
    }
  }

  // Кэшируем индекс последней найденной строки для оптимизации последовательного
  // воспроизведения — в типичном случае позиция меняется монотонно, и можно
  // делать O(1)-проверку, прежде чем уходить в бинарный поиск.
  int _lastEnIndex = -1;
  int _lastRuIndex = -1;

  void updatePosition(Duration pos) {
    _position = pos;
    final prevEn = _currentEnglishLine;
    final prevRu = _currentRussianLine;
    final ms = pos.inMilliseconds;

    final enRes = _findActiveLineFast(_englishSubs, ms, _lastEnIndex);
    _currentEnglishLine = enRes.line;
    _lastEnIndex = enRes.index;

    final ruRes = _findActiveLineFast(_russianSubs, ms, _lastRuIndex);
    _currentRussianLine = ruRes.line;
    _lastRuIndex = ruRes.index;

    if (_currentEnglishLine != prevEn || _currentRussianLine != prevRu) {
      notifyListeners();
    }
  }


    /// Синхронно подготавливает состояние для нового видео.
  ///
  /// Вызывается сразу при открытии PlayerScreen, чтобы интерфейс не показывал
  /// субтитры, позицию и последнюю реплику предыдущего видео, пока загружается
  /// новый видеопоток.
  void prepareVideo(VideoItem video, {bool notify = true, bool resetQualities = true}) {
    _videoScale = 1.0;
    _videoFit = BoxFit.contain;
    _controlsVisible = true;

    _currentVideo = video;

    _englishSubs = [];
    _russianSubs = [];
    _currentEnglishLine = null;
    _currentRussianLine = null;

    _lastEnIndex = -1;
    _lastRuIndex = -1;

    _position = Duration.zero;
    _isPlaying = false;

    _isLoadingSubs = true;
    _isAutoTranslating = false;
    _subtitleError = null;

    if (resetQualities) {
      _availableQualities = [];
      _selectedQuality = null;
    }

    if (notify) {
      notifyListeners();
    }
  }


  /// Быстрый поиск активной строки за O(log n) бинарным поиском.
  /// Сначала пробует hot-path: предыдущий индекс / следующий за ним
  /// (типичный случай монотонного воспроизведения) — это даёт O(1).
  _ActiveLineResult _findActiveLineFast(
    List<SubtitleLine> subs,
    int ms,
    int lastIndex,
  ) {
    if (subs.isEmpty) return const _ActiveLineResult(null, -1);

    // Hot path №1: позиция всё ещё внутри предыдущей активной строки.
    if (lastIndex >= 0 && lastIndex < subs.length) {
      final cur = subs[lastIndex];
      if (ms >= cur.startMs && ms <= cur.endMs) {
        return _ActiveLineResult(cur, lastIndex);
      }
      // Hot path №2: позиция продвинулась в следующую строку.
      final nextIdx = lastIndex + 1;
      if (nextIdx < subs.length) {
        final nxt = subs[nextIdx];
        if (ms >= nxt.startMs && ms <= nxt.endMs) {
          return _ActiveLineResult(nxt, nextIdx);
        }
      }
    }

    // Fallback: бинарный поиск по startMs.
    int lo = 0;
    int hi = subs.length - 1;
    int candidate = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final line = subs[mid];
      if (line.startMs <= ms) {
        candidate = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (candidate == -1) return const _ActiveLineResult(null, -1);
    final line = subs[candidate];
    if (ms >= line.startMs && ms <= line.endMs) {
      return _ActiveLineResult(line, candidate);
    }
    return _ActiveLineResult(null, candidate);
  }

  void setPlaying(bool p) {
    _isPlaying = p;
    notifyListeners();
  }

  void toggleTranslation() {
    _showTranslation = !_showTranslation;
    notifyListeners();
  }

  void setPlaybackSpeed(double s) {
    _playbackSpeed = s;
    notifyListeners();
  }

  void setSubtitleScale(double s) {
    _subtitleScale = s;
    notifyListeners();
  }

  void toggleOnVideoSubtitles() {
    _onVideoSubtitlesEnabled = !_onVideoSubtitlesEnabled;
    notifyListeners();
  }

  void setSubtitleBottomPadding(double p) {
    _subtitleBottomPadding = p;
    notifyListeners();
  }

  Duration? seekToLine(int index) {
    if (index >= 0 && index < _englishSubs.length) {
      return _englishSubs[index].startDuration;
    }
    return null;
  }

  void setAvailableQualities(List<String> q) {
    _availableQualities = q;
    notifyListeners();
  }

  void setSelectedQuality(String? q) {
    _selectedQuality = q;
    notifyListeners();
  }

  Future<void> loadSubtitlesFromUrl(String url, String language) async {
    if (_currentVideo == null) return;

    // Если субтитры этой группы уже загружены, не грузим повторно
    if (language == 'en' && _englishSubs.isNotEmpty) return;
    if (language == 'ru' && _russianSubs.isNotEmpty) return;

    debugPrint('[PlayerProvider] Loading $language subs from: $url');

    try {
      final response = await _ytService.client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final lines =
            VttParser.parse(response.body, _currentVideo!.id, language);
        if (language == 'en') {
          _englishSubs = lines;
          // Trigger auto-translation if Russian is missing
          if (_russianSubs.isEmpty) {
            _loadRussianSubs(_currentVideo!);
          }
        } else {
          _russianSubs = lines;
        }
        notifyListeners();
        debugPrint(
            '[PlayerProvider] Loaded ${lines.length} $language lines from URL');
      }
    } catch (e) {
      debugPrint('[PlayerProvider] Failed to load subs from URL: $e');
    }
  }

    // ─────────────────── масштаб видео и видимость интерфейса ───────────────────

  static const double minVideoScale = 1.0;
  static const double maxVideoScale = 3.0;

  /// На сколько субтитры поднимаются, пока виден интерфейс плеера.
  static const double controlsSubtitleLift = 96.0;

  double _videoScale = 1.0;
  BoxFit _videoFit = BoxFit.contain;
  bool _controlsVisible = true;

  double get videoScale => _videoScale;
  BoxFit get videoFit => _videoFit;
  bool get controlsVisible => _controlsVisible;

  /// Фактический нижний отступ субтитров: пока контролы на экране, строка
  /// поднимается над прогресс-баром, после автоскрытия — плавно опускается.
  double get effectiveSubtitleBottomPadding =>
      _subtitleBottomPadding + (_controlsVisible ? controlsSubtitleLift : 0);

  void setVideoScale(double scale) {
    final next = scale.clamp(minVideoScale, maxVideoScale).toDouble();
    if ((next - _videoScale).abs() < 0.001) return;
    _videoScale = next;
    notifyListeners();
  }

  void resetVideoScale() {
    if (_videoScale == 1.0 && _videoFit == BoxFit.contain) return;
    _videoScale = 1.0;
    _videoFit = BoxFit.contain;
    notifyListeners();
  }

  /// Переключение режима вписывания (contain → cover → fill).
  void cycleVideoFit() {
    _videoFit = switch (_videoFit) {
      BoxFit.contain => BoxFit.cover,
      BoxFit.cover => BoxFit.fill,
      _ => BoxFit.contain,
    };
    notifyListeners();
  }

  void setControlsVisible(bool visible) {
    if (_controlsVisible == visible) return;
    _controlsVisible = visible;
    notifyListeners();
  }


  @override
  void dispose() {
    _ytService.dispose();
    super.dispose();
  }
}

/// Результат поиска активной строки субтитров (строка + её индекс в списке,
/// чтобы можно было кэшировать положение между вызовами `updatePosition`).
class _ActiveLineResult {
  final SubtitleLine? line;
  final int index;
  const _ActiveLineResult(this.line, this.index);
}
