import 'package:flutter/material.dart';
import '../models/subtitle_line.dart';
import '../models/video_item.dart';
import '../services/youtube_service.dart';
import '../services/supabase_service.dart';

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
  bool _isLoadingSubs = false;
  String? _subtitleError;

  VideoItem? get currentVideo => _currentVideo;
  List<SubtitleLine> get englishSubs => _englishSubs;
  List<SubtitleLine> get russianSubs => _russianSubs;
  SubtitleLine? get currentEnglishLine => _currentEnglishLine;
  SubtitleLine? get currentRussianLine => _currentRussianLine;
  Duration get position => _position;
  bool get isPlaying => _isPlaying;
  bool get showTranslation => _showTranslation;
  double get playbackSpeed => _playbackSpeed;
  bool get isLoadingSubs => _isLoadingSubs;
  String? get subtitleError => _subtitleError;

  Future<void> loadVideo(VideoItem video) async {
    _currentVideo = video;
    _englishSubs = [];
    _russianSubs = [];
    _currentEnglishLine = null;
    _currentRussianLine = null;
    _subtitleError = null;
    _isLoadingSubs = true;
    notifyListeners();

    // Try Supabase cache first (with short timeout)
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

  Future<void> _loadRussianSubs(VideoItem video) async {
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
      debugPrint('[Subs] RU subs: ${_russianSubs.length}');
      if (_russianSubs.isNotEmpty) {
        SupabaseService.saveSubtitles(_russianSubs).catchError((_) {});
      }
      notifyListeners();
    } catch (_) {}
  }

  void updatePosition(Duration pos) {
    _position = pos;
    final prevEn = _currentEnglishLine;
    final prevRu = _currentRussianLine;
    _currentEnglishLine = _findActiveLine(_englishSubs, pos);
    _currentRussianLine = _findActiveLine(_russianSubs, pos);
    if (_currentEnglishLine != prevEn || _currentRussianLine != prevRu) {
      notifyListeners();
    }
  }

  SubtitleLine? _findActiveLine(List<SubtitleLine> subs, Duration pos) {
    if (subs.isEmpty) return null;
    final ms = pos.inMilliseconds;
    for (final line in subs) {
      if (ms >= line.startMs && ms <= line.endMs) return line;
      if (line.startMs > ms) break;
    }
    return null;
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

  Duration? seekToLine(int index) {
    if (index >= 0 && index < _englishSubs.length) {
      return _englishSubs[index].startDuration;
    }
    return null;
  }

  @override
  void dispose() {
    _ytService.dispose();
    super.dispose();
  }
}
