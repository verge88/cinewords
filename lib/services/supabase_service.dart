import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import '../models/video_item.dart';
import '../models/subtitle_line.dart';
import '../models/word_card.dart';
import '../models/user_progress.dart';

class SupabaseService {
  static final _client = SupabaseConfig.supabase;

  // ──────────────── AUTH ────────────────

  static Future<void> signUp(String email, String password, String name) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': name},
    );
  }

  static Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ──────────────── VIDEOS ────────────────

  static Future<List<VideoItem>> getFeaturedVideos() async {
    final data = await _client
        .from('videos')
        .select()
        .eq('is_featured', true)
        .order('created_at', ascending: false)
        .limit(10);
    return data.map((e) => VideoItem.fromJson(e)).toList();
  }

  static Future<List<VideoItem>> getVideosByCategory(String category) async {
    final data = await _client
        .from('videos')
        .select()
        .eq('category', category)
        .order('view_count', ascending: false)
        .limit(20);
    return data.map((e) => VideoItem.fromJson(e)).toList();
  }

  static Future<List<VideoItem>> getVideosByDifficulty(String difficulty) async {
    final data = await _client
        .from('videos')
        .select()
        .eq('difficulty', difficulty)
        .order('created_at', ascending: false)
        .limit(20);
    return data.map((e) => VideoItem.fromJson(e)).toList();
  }

  static Future<List<VideoItem>> searchVideos(String query) async {
    final data = await _client
        .from('videos')
        .select()
        .ilike('title', '%$query%')
        .limit(20);
    return data.map((e) => VideoItem.fromJson(e)).toList();
  }

  static Future<VideoItem> addVideo(VideoItem video) async {
    final data = await _client
        .from('videos')
        .upsert(video.toJson(), onConflict: 'youtube_id')
        .select()
        .single();
    return VideoItem.fromJson(data);
  }

    // ──────────────── SUBTITLES ────────────────

  static Future<List<SubtitleLine>> getSubtitles(
    String videoId, {
    String language = 'en',
  }) async {
    try {
      final data = await _client
          .from('subtitles')
          .select()
          .eq('video_id', videoId)
          .eq('language', language)
          .order('sequence_index', ascending: true);  // ← ascending: true!
      return data.map((e) => SubtitleLine.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[Supabase] Error loading subtitles: $e');
      return [];
    }
  }

  static Future<void> saveSubtitles(List<SubtitleLine> subtitles) async {
    if (subtitles.isEmpty) return;
    try {
      // Insert in batches of 100 to avoid payload limits
      for (var i = 0; i < subtitles.length; i += 100) {
        final end = (i + 100).clamp(0, subtitles.length);
        final batch = subtitles.sublist(i, end).map((s) => {
              'video_id': s.videoId,
              'language': s.language,
              'start_ms': s.startMs,
              'end_ms': s.endMs,
              'text': s.text,
              'translation': s.translation,
              'sequence_index': s.sequenceIndex,
            }).toList();
        await _client.from('subtitles').insert(batch);
      }
      debugPrint('[Supabase] Saved ${subtitles.length} subtitles');
    } catch (e) {
      debugPrint('[Supabase] Error saving subtitles: $e');
    }
  }

  // ──────────────── VOCABULARY ────────────────

  static Future<List<WordCard>> getUserVocabulary({String? status}) async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return [];

    var query = _client.from('vocabulary').select().eq('user_id', userId);
    if (status != null) query = query.eq('status', status);

    final data = await query.order('created_at', ascending: false);
    return data.map((e) => WordCard.fromJson(e)).toList();
  }

  static Future<List<WordCard>> getWordsToReview() async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return [];

    final data = await _client
        .from('vocabulary')
        .select()
        .eq('user_id', userId)
        .lte('next_review_at', DateTime.now().toIso8601String())
        .neq('status', 'mastered')
        .order('next_review_at')
        .limit(20);
    return data.map((e) => WordCard.fromJson(e)).toList();
  }

  static Future<WordCard> addWord({
    required String word,
    String? translation,
    String? contextSentence,
    String? contextVideoId,
    int? contextTimestampMs,
  }) async {
    final userId = SupabaseConfig.userId!;
    final data = await _client
        .from('vocabulary')
        .upsert({
          'user_id': userId,
          'word': word.toLowerCase().trim(),
          'translation': translation,
          'context_sentence': contextSentence,
          'context_video_id': contextVideoId,
          'context_timestamp_ms': contextTimestampMs,
        }, onConflict: 'user_id,word')
        .select()
        .single();
    return WordCard.fromJson(data);
  }

  static Future<void> reviewWord(String vocabId, int quality) async {
    await _client.rpc('update_vocabulary_sm2', params: {
      'p_vocab_id': vocabId,
      'p_quality': quality,
    });
  }

  static Future<void> deleteWord(String vocabId) async {
    await _client.from('vocabulary').delete().eq('id', vocabId);
  }

  // ──────────────── PROGRESS ────────────────

  static Future<UserProgress> getUserProgress() async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return const UserProgress();

    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todayStats = await _client
        .from('daily_stats')
        .select()
        .eq('user_id', userId)
        .eq('date', today)
        .maybeSingle();

    final reviewCount = await _client
        .from('vocabulary')
        .select('id')
        .eq('user_id', userId)
        .lte('next_review_at', DateTime.now().toIso8601String())
        .neq('status', 'mastered');

    return UserProgress(
      streakDays: profile['streak_days'] ?? 0,
      totalWordsLearned: profile['total_words_learned'] ?? 0,
      totalWatchMinutes: profile['total_watch_minutes'] ?? 0,
      dailyGoalMinutes: profile['daily_goal_minutes'] ?? 15,
      todayMinutes: todayStats?['minutes_watched'] ?? 0,
      todayWords: todayStats?['words_added'] ?? 0,
      todayReviewed: todayStats?['words_reviewed'] ?? 0,
      wordsToReview: (reviewCount as List).length,
    );
  }

  static Future<void> updateWatchProgress(
    String videoId,
    int positionMs,
    int watchDurationSec,
  ) async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return;

    await _client.from('watch_history').upsert({
      'user_id': userId,
      'video_id': videoId,
      'last_position_ms': positionMs,
      'watch_duration_seconds': watchDurationSec,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,video_id');

    // Update daily stats
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _client.rpc('update_streak', params: {'p_user_id': userId});

    await _client.from('daily_stats').upsert({
      'user_id': userId,
      'date': today,
      'minutes_watched': (watchDurationSec / 60).ceil(),
    }, onConflict: 'user_id,date');
  }
}
