import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/subtitle_line.dart';

typedef WebViewSubtitleFetcher = Future<String> Function(String url);

class YouTubeService {
  late final YoutubeExplode _yt;
  final http.Client _httpClient = http.Client();

  YouTubeService() {
    _yt = YoutubeExplode();
  }

  Future<Video> getVideoInfo(String videoIdOrUrl) async {
    return await _yt.videos.get(videoIdOrUrl);
  }

  Future<List<Video>> searchVideos(String query, {int limit = 20}) async {
    final searchList = await _yt.search.search(query);
    return searchList.take(limit).toList();
  }

  /// Main subtitle fetching method with multiple fallbacks
  Future<List<SubtitleLine>> getSubtitles(
    String youtubeVideoId, {
    String language = 'en',
    required String dbVideoId,
    WebViewSubtitleFetcher? webViewFetcher,
  }) async {
    debugPrint('[YT] Fetching $language subtitles for: $youtubeVideoId');

    // Try 1: Extract caption URL from watch page and download directly
    try {
      final subs = await _getSubtitlesFromWatchPage(
        youtubeVideoId, language, dbVideoId,
      );
      if (subs.isNotEmpty) {
        debugPrint('[YT] Got ${subs.length} subtitles from watch page');
        return subs;
      }
    } catch (e) {
      debugPrint('[YT] Watch page method failed: $e');
    }

    // Try 2: youtube_explode_dart manifest (may still work for some videos)
    try {
      final subs = await _getSubtitlesViaExplode(
        youtubeVideoId, language, dbVideoId,
      );
      if (subs.isNotEmpty) {
        debugPrint('[YT] Got ${subs.length} subtitles via Explode');
        return subs;
      }
    } catch (e) {
      debugPrint('[YT] Explode method failed: $e');
    }

    // Try 3: WebView with full page context (has cookies/session)
    if (webViewFetcher != null) {
      try {
        final subs = await _getSubtitlesViaWebViewPage(
          youtubeVideoId, language, dbVideoId, webViewFetcher,
        );
        if (subs.isNotEmpty) {
          debugPrint('[YT] Got ${subs.length} subtitles via WebView');
          return subs;
        }
      } catch (e) {
        debugPrint('[YT] WebView method failed: $e');
      }
    }

    debugPrint('[YT] No subtitles found');
    return [];
  }

  /// NEW: Extract caption track URLs from the watch page HTML/JSON
  /// YouTube embeds caption URLs with all needed tokens in the page data
  Future<List<SubtitleLine>> _getSubtitlesFromWatchPage(
    String videoId,
    String language,
    String dbVideoId,
  ) async {
    // Fetch the watch page
    final watchUrl = 'https://www.youtube.com/watch?v=$videoId&hl=en';
    final response = await _httpClient.get(
      Uri.parse(watchUrl),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );

    if (response.statusCode != 200) {
      debugPrint('[YT] Watch page returned ${response.statusCode}');
      return [];
    }

    final body = response.body;

    // Extract ytInitialPlayerResponse JSON from the page
    final playerResponseJson = _extractPlayerResponse(body);
    if (playerResponseJson == null) {
      debugPrint('[YT] Could not extract playerResponse from watch page');
      return [];
    }

    // Navigate to captions data
    final captions = playerResponseJson['captions'];
    if (captions == null) {
      debugPrint('[YT] No captions object in playerResponse');
      return [];
    }

    final renderer = captions['playerCaptionsTracklistRenderer'];
    if (renderer == null) {
      debugPrint('[YT] No playerCaptionsTracklistRenderer');
      return [];
    }

    final captionTracks = renderer['captionTracks'] as List<dynamic>?;
    if (captionTracks == null || captionTracks.isEmpty) {
      debugPrint('[YT] No caption tracks available');
      return [];
    }

    // Find the track for the requested language
    Map<String, dynamic>? selectedTrack;

    // First try exact match
    for (final track in captionTracks) {
      final langCode = track['languageCode'] as String? ?? '';
      if (langCode == language) {
        selectedTrack = track as Map<String, dynamic>;
        break;
      }
    }

    // Try prefix match (e.g., 'en' matches 'en-US')
    if (selectedTrack == null) {
      for (final track in captionTracks) {
        final langCode = track['languageCode'] as String? ?? '';
        if (langCode.startsWith(language) || language.startsWith(langCode)) {
          selectedTrack = track as Map<String, dynamic>;
          break;
        }
      }
    }

    if (selectedTrack == null) {
      debugPrint('[YT] No track found for language: $language');
      debugPrint('[YT] Available languages: ${captionTracks.map((t) => t['languageCode']).toList()}');
      return [];
    }

    // Get the base URL (already contains signature, expire, etc.)
    var captionUrl = selectedTrack['baseUrl'] as String? ?? '';
    if (captionUrl.isEmpty) {
      debugPrint('[YT] Empty baseUrl for caption track');
      return [];
    }

    // Request JSON3 format (most reliable to parse)
    if (!captionUrl.contains('fmt=')) {
      captionUrl += '&fmt=json3';
    } else {
      captionUrl = captionUrl.replaceAll(RegExp(r'fmt=[^&]*'), 'fmt=json3');
    }

    debugPrint('[YT] Downloading captions from: ${captionUrl.substring(0, 80)}...');

    // Download the caption track
    final captionResponse = await _httpClient.get(
      Uri.parse(captionUrl),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (captionResponse.statusCode != 200) {
      debugPrint('[YT] Caption download failed: ${captionResponse.statusCode}');

      // Fallback: try XML format (srv3)
      final xmlUrl = captionUrl.replaceAll(RegExp(r'fmt=[^&]*'), 'fmt=srv3');
      final xmlResponse = await _httpClient.get(
        Uri.parse(xmlUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );
      if (xmlResponse.statusCode == 200 && xmlResponse.body.isNotEmpty) {
        return _parseSubtitleBody(xmlResponse.body, dbVideoId, language);
      }

      return [];
    }

    final captionBody = captionResponse.body;
    if (captionBody.isEmpty) {
      debugPrint('[YT] Caption response body is empty');
      return [];
    }

    return _parseSubtitleBody(captionBody, dbVideoId, language);
  }

  /// Extract ytInitialPlayerResponse from the watch page HTML
  Map<String, dynamic>? _extractPlayerResponse(String html) {
    // Try pattern: var ytInitialPlayerResponse = {...};
    final patterns = [
      RegExp(r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\})\s*;', dotAll: true),
      RegExp(r'ytInitialPlayerResponse\s*=\s*(\{.+?\})\s*;', dotAll: true),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        try {
          final jsonStr = match.group(1)!;
          // Find the end of the JSON object properly
          final decoded = _extractJsonObject(jsonStr);
          if (decoded != null) return decoded;
        } catch (e) {
          debugPrint('[YT] Failed to parse playerResponse pattern: $e');
        }
      }
    }

    // Alternative: try to find it in the script tags
    final scriptPattern = RegExp(
      r'ytInitialPlayerResponse\s*=\s*(\{.*?"captions".*?\})\s*;\s*var\s',
      dotAll: true,
    );
    final scriptMatch = scriptPattern.firstMatch(html);
    if (scriptMatch != null) {
      try {
        return jsonDecode(scriptMatch.group(1)!) as Map<String, dynamic>;
      } catch (_) {}
    }

    return null;
  }

  /// Safely extract a JSON object from a string that might have trailing content
  Map<String, dynamic>? _extractJsonObject(String str) {
    int braceCount = 0;
    int? start;

    for (int i = 0; i < str.length; i++) {
      if (str[i] == '{') {
        start ??= i;
        braceCount++;
      } else if (str[i] == '}') {
        braceCount--;
        if (braceCount == 0 && start != null) {
          try {
            return jsonDecode(str.substring(start, i + 1))
                as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Get subtitles using youtube_explode_dart library
  /// NOW: manually download and parse to avoid the XML bug
  Future<List<SubtitleLine>> _getSubtitlesViaExplode(
    String videoId,
    String language,
    String dbVideoId,
  ) async {
    final manifest = await _yt.videos.closedCaptions.getManifest(videoId);

    ClosedCaptionTrackInfo? pickTrack(String lang) {
      final sameLang =
          manifest.tracks.where((t) => t.language.code == lang).toList();
      if (sameLang.isEmpty) return null;

      final manual = sameLang.where((t) => !t.isAutoGenerated).toList();
      return manual.isNotEmpty ? manual.first : sameLang.first;
    }

    var trackInfo = pickTrack(language);
    if (trackInfo == null && language != 'en') {
      return [];
    }
    if (trackInfo == null && language == 'en') {
      final enTracks =
          manifest.tracks.where((t) => t.language.code == 'en').toList();
      trackInfo = enTracks.isNotEmpty ? enTracks.first : null;
    }
    if (trackInfo == null) return [];

    // Instead of using _yt.videos.closedCaptions.get(trackInfo) which
    // crashes on JSON3 responses, download the URL ourselves
    try {
      var url = trackInfo.url.toString();

      // Force JSON3 format
      if (!url.contains('fmt=')) {
        url += '&fmt=json3';
      } else {
        url = url.replaceAll(RegExp(r'fmt=[^&]*'), 'fmt=json3');
      }

      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      if (response.statusCode != 200 || response.body.isEmpty) {
        debugPrint('[YT] Explode URL download failed: ${response.statusCode}');
        return [];
      }

      final lines = _parseSubtitleBody(response.body, dbVideoId, language);
      debugPrint('[YT] Explode+manual parse: ${lines.length} lines');
      return lines;
    } catch (e) {
      debugPrint('[YT] Explode manual download error: $e');
      return [];
    }
  }

  /// WebView-based fetching: load the video page and extract captions via JS
  Future<List<SubtitleLine>> _getSubtitlesViaWebViewPage(
    String videoId,
    String language,
    String dbVideoId,
    WebViewSubtitleFetcher fetcher,
  ) async {
    // Use WebView to execute JS that extracts caption URLs from the page
    // The JS extracts ytInitialPlayerResponse from the loaded page
    final jsCode = '''
      (function() {
        try {
          var player = ytInitialPlayerResponse || {};
          var captions = player.captions || {};
          var renderer = captions.playerCaptionsTracklistRenderer || {};
          var tracks = renderer.captionTracks || [];
          var result = [];
          for (var i = 0; i < tracks.length; i++) {
            result.push({
              lang: tracks[i].languageCode,
              url: tracks[i].baseUrl,
              kind: tracks[i].kind || ''
            });
          }
          return JSON.stringify(result);
        } catch(e) {
          return '[]';
        }
      })();
    ''';

    // First, have the WebView navigate to the video page
    final pageUrl = 'https://www.youtube.com/watch?v=$videoId';

    // Fetch the page content (this depends on your WebView implementation)
    // The fetcher should:
    // 1. Navigate to the page URL
    // 2. Wait for it to load
    // 3. Execute the JS and return the result
    final tracksJson = await fetcher(pageUrl);

    if (tracksJson.isEmpty || tracksJson == '[]') {
      // Fallback: try direct URL fetch through WebView
      return [];
    }

    try {
      final tracks = jsonDecode(tracksJson) as List<dynamic>;

      // Find track for requested language
      Map<String, dynamic>? selectedTrack;
      for (final t in tracks) {
        if (t['lang'] == language ||
            (t['lang'] as String).startsWith(language)) {
          selectedTrack = t as Map<String, dynamic>;
          break;
        }
      }

      if (selectedTrack == null) return [];

      var captionUrl = selectedTrack['url'] as String;
      if (!captionUrl.contains('fmt=')) {
        captionUrl += '&fmt=json3';
      }

      // Download through WebView (has session cookies)
      final body = await fetcher(captionUrl);
      if (body.isEmpty) return [];

      return _parseSubtitleBody(body, dbVideoId, language);
    } catch (e) {
      debugPrint('[YT] WebView page method error: $e');
      return [];
    }
  }

  // ============================================================
  // PARSING METHODS (same as before, all working correctly)
  // ============================================================

  List<SubtitleLine> _parseSubtitleBody(
    String body,
    String dbVideoId,
    String language,
  ) {
    // Try JSON3 format first (YouTube's current default)
    if (body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[')) {
      final lines = _parseJson3Subtitles(body, dbVideoId, language);
      if (lines.isNotEmpty) return lines;
    }

    // Try XML format
    if (body.contains('<text') || body.contains('<?xml')) {
      return _parseXmlSubtitles(body, dbVideoId, language);
    }

    // Try VTT format
    if (body.contains('WEBVTT') || body.contains('-->')) {
      return _parseVttSubtitles(body, dbVideoId, language);
    }

    return [];
  }

  List<SubtitleLine> _parseJson3Subtitles(
      String body, String dbVideoId, String lang) {
    final lines = <SubtitleLine>[];
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final events = json['events'] as List<dynamic>? ?? [];

      int i = 0;
      for (final ev in events) {
        if (ev is! Map) continue;

        final startMs = (ev['tStartMs'] as num?)?.toInt() ?? 0;
        final durMs = (ev['dDurationMs'] as num?)?.toInt() ?? 3000;

        final segs = ev['segs'] as List<dynamic>?;
        if (segs == null) continue;

        final text = segs
            .map((s) => (s is Map ? (s['utf8'] ?? '') : '').toString())
            .join()
            .replaceAll('\n', ' ')
            .trim();

        if (text.isEmpty) continue;

        lines.add(SubtitleLine(
          id: '${dbVideoId}_${lang}_$i',
          videoId: dbVideoId,
          language: lang,
          startMs: startMs,
          endMs: startMs + durMs,
          text: text,
          sequenceIndex: i,
        ));
        i++;
      }
      debugPrint('[YT] JSON3: parsed ${lines.length} lines');
    } catch (e) {
      debugPrint('[YT] JSON3 parse error: $e');
    }
    return lines;
  }

  List<SubtitleLine> _parseXmlSubtitles(
      String body, String dbVideoId, String lang) {
    final lines = <SubtitleLine>[];
    final regex = RegExp(
      r'<text\b[^>]*\bstart="([^"]*)"[^>]*\bdur="([^"]*)"[^>]*>(.*?)</text>',
      dotAll: true,
    );

    int i = 0;
    for (final m in regex.allMatches(body)) {
      final start = double.tryParse(m.group(1) ?? '') ?? 0;
      final dur = double.tryParse(m.group(2) ?? '2') ?? 2;
      final text = _decodeXml(m.group(3) ?? '').trim();
      if (text.isEmpty) continue;

      lines.add(SubtitleLine(
        id: '${dbVideoId}_${lang}_$i',
        videoId: dbVideoId,
        language: lang,
        startMs: (start * 1000).round(),
        endMs: ((start + dur) * 1000).round(),
        text: text,
        sequenceIndex: i,
      ));
      i++;
    }

    debugPrint('[YT] XML: parsed ${lines.length} lines');
    return lines;
  }

  List<SubtitleLine> _parseVttSubtitles(
      String body, String dbVideoId, String lang) {
    final lines = <SubtitleLine>[];
    final raw = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final all = raw.split('\n');

    int i = 0;
    int idx = 0;
    if (all.isNotEmpty && all[0].contains('WEBVTT')) idx = 1;

    while (idx < all.length) {
      while (idx < all.length && all[idx].trim().isEmpty) idx++;
      if (idx >= all.length) break;

      if (RegExp(r'^\d+$').hasMatch(all[idx].trim())) {
        idx++;
        if (idx >= all.length) break;
      }

      final timingLine = all[idx].trim();
      if (!timingLine.contains('-->')) {
        idx++;
        continue;
      }

      final parts = timingLine.split('-->');
      if (parts.length < 2) {
        idx++;
        continue;
      }

      final startMs = _vttTimeToMs(parts[0].trim());
      final endMs = _vttTimeToMs(parts[1].trim().split(RegExp(r'\s+')).first);
      idx++;

      final buffer = <String>[];
      while (idx < all.length && all[idx].trim().isNotEmpty) {
        buffer.add(all[idx].trim());
        idx++;
      }

      final text = buffer.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;

      lines.add(SubtitleLine(
        id: '${dbVideoId}_${lang}_$i',
        videoId: dbVideoId,
        language: lang,
        startMs: startMs,
        endMs: endMs > startMs ? endMs : (startMs + 2000),
        text: text,
        sequenceIndex: i,
      ));
      i++;
    }

    debugPrint('[YT] VTT: parsed ${lines.length} lines');
    return lines;
  }

  int _vttTimeToMs(String s) {
    final t = s.trim();
    final parts = t.split(':');
    double seconds = 0;

    if (parts.length == 3) {
      seconds = (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (double.tryParse(parts[2]) ?? 0);
    } else if (parts.length == 2) {
      seconds =
          (int.tryParse(parts[0]) ?? 0) * 60 + (double.tryParse(parts[1]) ?? 0);
    } else {
      seconds = double.tryParse(parts[0]) ?? 0;
    }

    return (seconds * 1000).round();
  }

  String _decodeXml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll(RegExp(r'<[^>]+>'), '');
  }

  Future<List<String>> getAvailableLanguages(String videoId) async {
    // Also use watch page approach as primary
    try {
      final watchUrl = 'https://www.youtube.com/watch?v=$videoId&hl=en';
      final response = await _httpClient.get(
        Uri.parse(watchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );

      if (response.statusCode == 200) {
        final playerResponse = _extractPlayerResponse(response.body);
        if (playerResponse != null) {
          final captions = playerResponse['captions'];
          final renderer = captions?['playerCaptionsTracklistRenderer'];
          final tracks = renderer?['captionTracks'] as List<dynamic>?;
          if (tracks != null) {
            return tracks
                .map((t) => (t['languageCode'] as String?) ?? '')
                .where((code) => code.isNotEmpty)
                .toSet()
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[YT] Watch page languages error: $e');
    }

    // Fallback to explode
    try {
      final manifest = await _yt.videos.closedCaptions.getManifest(videoId);
      return manifest.tracks
          .map((t) => t.language.code)
          .where((code) => code.isNotEmpty)
          .toSet()
          .toList();
    } catch (e) {
      debugPrint('[YT] Get available languages error: $e');
      return [];
    }
  }

  void dispose() {
    _httpClient.close();
    _yt.close();
  }
}
