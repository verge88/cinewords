import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_transcript_api/youtube_transcript_api.dart' as yt_transcript;
import '../models/subtitle_line.dart';

class YouTubeService {
  late final YoutubeExplode _yt;
  late final yt_transcript.YouTubeTranscriptApi _transcriptApi;

  YouTubeService() {
    _yt = YoutubeExplode();
    _transcriptApi = yt_transcript.YouTubeTranscriptApi();
  }

  /// Get video metadata (used for importing videos)
  Future<Video> getVideoInfo(String videoIdOrUrl) async {
    return await _yt.videos.get(videoIdOrUrl);
  }

  Future<List<Video>> searchVideos(String query, {int limit = 20}) async {
    final searchList = await _yt.search.search(query);
    return searchList.take(limit).toList();
  }

  /// ═══════════════════════════════════════════════════════
  ///  MAIN: Fetch subtitles using YouTube Transcript API
  /// ═══════════════════════════════════════════════════════
  Future<List<SubtitleLine>> getSubtitles(
      String youtubeVideoId, {
        String language = 'en',
        required String dbVideoId,
      }) async {
    debugPrint('[YT] Fetching $language subtitles for: $youtubeVideoId');

    // ── Try 1: Direct fetch with preferred language ──
    try {
      final transcript = await _transcriptApi
          .fetch(youtubeVideoId, languages: [language])
          .timeout(const Duration(seconds: 15));

      final lines = _convertTranscript(transcript, dbVideoId, language);
      if (lines.isNotEmpty) {
        debugPrint('[YT] ✓ Got ${lines.length} $language lines via Transcript API');
        return lines;
      }
    } catch (e) {
      debugPrint('[YT] Direct fetch ($language) failed: $e');
    }

    // ── Try 2: List all transcripts, find best match ──
    try {
      final transcriptList = await _transcriptApi
          .list(youtubeVideoId)
          .timeout(const Duration(seconds: 15));

      debugPrint('[YT] Available transcripts:');
      for (final t in transcriptList) {
        debugPrint('[YT]   ${t.languageCode} (${t.language}) '
            '${t.isGenerated ? "[auto]" : "[manual]"} '
            '${t.isTranslatable ? "[translatable]" : ""}');
      }

      // Try to find transcript in requested language
      yt_transcript.Transcript? found;
      try {
        found = transcriptList.findTranscript([language]);
      } catch (_) {
        // If no direct match, try to find any translatable transcript
        // and translate it to the desired language
        try {
          // First try English as source for translation
          final source = transcriptList.findTranscript(['en']);
          if (source.isTranslatable) {
            found = source.translate(language);
            debugPrint('[YT] Using translation en -> $language');
          }
        } catch (_) {
          // Try any translatable transcript
          for (final t in transcriptList) {
            if (t.isTranslatable) {
              try {
                found = t.translate(language);
                debugPrint('[YT] Using translation ${t.languageCode} -> $language');
                break;
              } catch (_) {
                continue;
              }
            }
          }
        }
      }

      if (found != null) {
        final fetched = await found.fetch();
        final lines = _convertTranscript(fetched, dbVideoId, language);
        if (lines.isNotEmpty) {
          debugPrint('[YT] ✓ Got ${lines.length} $language lines (list+find)');
          return lines;
        }
      }
    } catch (e) {
      debugPrint('[YT] List transcripts failed: $e');
    }

    // ── Try 3: If requesting non-English, try auto-generated ──
    if (language != 'en') {
      try {
        final transcriptList = await _transcriptApi
            .list(youtubeVideoId)
            .timeout(const Duration(seconds: 15));

        final generated = transcriptList.findGeneratedTranscript([language]);
        final fetched = await generated.fetch();
        final lines = _convertTranscript(fetched, dbVideoId, language);
        if (lines.isNotEmpty) {
          debugPrint('[YT] ✓ Got ${lines.length} auto-generated $language lines');
          return lines;
        }
      } catch (e) {
        debugPrint('[YT] Auto-generated ($language) failed: $e');
      }
    }

    debugPrint('[YT] ✗ No $language subtitles found for $youtubeVideoId');
    return [];
  }

  /// Convert FetchedTranscript to our SubtitleLine model
  List<SubtitleLine> _convertTranscript(
      yt_transcript.FetchedTranscript transcript,
      String dbVideoId,
      String language,
      ) {
    final lines = <SubtitleLine>[];

    for (int i = 0; i < transcript.snippets.length; i++) {
      final snippet = transcript.snippets[i];
      final startMs = (snippet.start * 1000).round();
      final durationMs = (snippet.duration * 1000).round();
      final text = snippet.text.trim();

      if (text.isEmpty) continue;

      lines.add(SubtitleLine(
        id: '${dbVideoId}_${language}_$i',
        videoId: dbVideoId,
        language: language,
        startMs: startMs,
        endMs: startMs + durationMs,
        text: text,
        sequenceIndex: i,
      ));
    }

    return lines;
  }

  /// Get list of available languages for a video
  Future<List<String>> getAvailableLanguages(String videoId) async {
    try {
      final transcriptList = await _transcriptApi
          .list(videoId)
          .timeout(const Duration(seconds: 10));

      return transcriptList
          .map((t) => t.languageCode)
          .toSet()
          .toList();
    } catch (e) {
      debugPrint('[YT] getAvailableLanguages error: $e');
      return [];
    }
  }

  void dispose() {
    _transcriptApi.dispose();
    _yt.close();
  }
}
