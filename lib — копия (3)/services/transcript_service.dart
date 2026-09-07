import 'package:flutter/foundation.dart';
import 'package:youtube_transcript_api/youtube_transcript_api.dart';
import '../models/subtitle_line.dart';

class TranscriptService {
  YouTubeTranscriptApi? _api;

  YouTubeTranscriptApi get api {
    _api ??= YouTubeTranscriptApi();
    return _api!;
  }

  /// Fetch subtitles for a video in a given language using YouTube Transcript API.
  /// Returns a list of [SubtitleLine] ready for display and caching.
  Future<List<SubtitleLine>> fetchTranscript(
      String youtubeVideoId, {
        required String dbVideoId,
        String language = 'en',
      }) async {
    try {
      final transcript = await api.fetch(
        youtubeVideoId,
        languages: [language],
      );

      final lines = <SubtitleLine>[];
      for (int i = 0; i < transcript.length; i++) {
        final snippet = transcript[i];
        final startMs = (snippet.start * 1000).round();
        final durationMs = (snippet.duration * 1000).round();

        lines.add(SubtitleLine(
          id: '${dbVideoId}_${language}_$i',
          videoId: dbVideoId,
          language: language,
          startMs: startMs,
          endMs: startMs + durationMs,
          text: _cleanText(snippet.text),
          sequenceIndex: i,
        ));
      }

      debugPrint(
          'TranscriptService: Loaded ${lines.length} $language lines for $youtubeVideoId');
      return lines;
    } on NoTranscriptFoundException catch (e) {
      debugPrint(
          'TranscriptService: No $language transcript found. Available: ${e.availableLanguages}');
      return [];
    } on TranscriptsDisabledException {
      debugPrint('TranscriptService: Transcripts disabled for $youtubeVideoId');
      return [];
    } on VideoUnavailableException {
      debugPrint('TranscriptService: Video unavailable $youtubeVideoId');
      return [];
    } on TranscriptException catch (e) {
      debugPrint('TranscriptService: Error fetching transcript: $e');
      return [];
    } catch (e) {
      debugPrint('TranscriptService: Unexpected error: $e');
      return [];
    }
  }

  /// Fetch translated subtitles.
  /// First fetches English, then translates to target language.
  Future<List<SubtitleLine>> fetchTranslatedTranscript(
      String youtubeVideoId, {
        required String dbVideoId,
        String fromLanguage = 'en',
        String toLanguage = 'ru',
      }) async {
    try {
      final transcriptList = await api.list(youtubeVideoId);

      // Find a transcript to translate from
      final source = transcriptList.findTranscript([fromLanguage]);

      if (!source.isTranslatable) {
        debugPrint(
            'TranscriptService: $fromLanguage transcript is not translatable');
        return [];
      }

      // Translate to target language
      final translated = source.translate(toLanguage);
      final snippets = await translated.fetch();

      final lines = <SubtitleLine>[];
      for (int i = 0; i < snippets.length; i++) {
        final snippet = snippets[i];
        final startMs = (snippet.start * 1000).round();
        final durationMs = (snippet.duration * 1000).round();

        lines.add(SubtitleLine(
          id: '${dbVideoId}_${toLanguage}_$i',
          videoId: dbVideoId,
          language: toLanguage,
          startMs: startMs,
          endMs: startMs + durationMs,
          text: _cleanText(snippet.text),
          sequenceIndex: i,
        ));
      }

      debugPrint(
          'TranscriptService: Loaded ${lines.length} translated $toLanguage lines');
      return lines;
    } on NoTranscriptFoundException {
      debugPrint('TranscriptService: No translatable transcript found');
      return [];
    } catch (e) {
      debugPrint('TranscriptService: Translation error: $e');
      return [];
    }
  }

  /// List all available transcript languages for a video.
  Future<List<TranscriptInfo>> listAvailableTranscripts(
      String youtubeVideoId) async {
    try {
      final transcriptList = await api.list(youtubeVideoId);
      final infos = <TranscriptInfo>[];
      for (final t in transcriptList) {
        infos.add(TranscriptInfo(
          languageCode: t.languageCode,
          language: t.language,
          isGenerated: t.isGenerated,
          isTranslatable: t.isTranslatable,
        ));
      }
      return infos;
    } catch (e) {
      debugPrint('TranscriptService: Error listing transcripts: $e');
      return [];
    }
  }

  /// Clean HTML entities and tags from transcript text
  String _cleanText(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('\n', ' ')
        .trim();
  }

  void dispose() {
    _api?.dispose();
    _api = null;
  }
}

extension on FetchedTranscript {
  operator [](int other) {}
}

/// Info about an available transcript
class TranscriptInfo {
  final String languageCode;
  final String language;
  final bool isGenerated;
  final bool isTranslatable;

  const TranscriptInfo({
    required this.languageCode,
    required this.language,
    required this.isGenerated,
    required this.isTranslatable,
  });

  @override
  String toString() =>
      '$language [$languageCode] ${isGenerated ? "(auto)" : "(manual)"} ${isTranslatable ? "✓ translatable" : ""}';
}
