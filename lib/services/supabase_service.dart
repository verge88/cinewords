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

  // ──────────────── FAVORITES ────────────────

  static Future<void> toggleFavorite(String videoId, bool isFavorite) async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return;

    if (isFavorite) {
      await _client.from('user_favorites').upsert({
        'user_id': userId,
        'video_id': videoId,
      }, onConflict: 'user_id,video_id');
    } else {
      await _client
          .from('user_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('video_id', videoId);
    }
  }

  static Future<List<VideoItem>> getFavoriteVideos() async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return [];

    try {
      // 1. Get IDs first
      final ids = await getFavoriteIds();
      if (ids.isEmpty) return [];

      // 2. Fetch full video details for those IDs
      final data = await _client
          .from('videos')
          .select()
          .inFilter('id', ids);
      
      if (data == null) return [];
      
      final List<VideoItem> videos = (data as List).map((e) => VideoItem.fromJson(e)).toList();
      
      // Keep same order as IDs if possible, or just return them
      return videos;
    } catch (e) {
      debugPrint('[SupabaseService] Error in getFavoriteVideos: $e');
      return [];
    }
  }

  static Future<List<String>> getFavoriteIds() async {
    final userId = SupabaseConfig.userId;
    if (userId == null) return [];

    final data = await _client
        .from('user_favorites')
        .select('video_id')
        .eq('user_id', userId);
    
    return (data as List).map((e) => e['video_id'] as String).toList();
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

    final nowWithSkew = DateTime.now().toUtc().add(const Duration(minutes: 5));
    final data = await _client
        .from('vocabulary')
        .select()
        .eq('user_id', userId)
        .lte('next_review_at', nowWithSkew.toIso8601String())
        .neq('status', 'mastered')
        .order('next_review_at')
        .limit(20);
    return data.map((e) => WordCard.fromJson(e)).toList();
  }

  static Future<WordCard> addWord({
    required String word,
    String? translation,
    String? phonetic,
    String? contextSentence,
    String? contextVideoId,
    int? contextTimestampMs,
    String type = 'word',
  }) async {
    try {
      final userId = SupabaseConfig.userId;
      if (userId == null) {
        throw Exception('User is not logged in');
      }
      
      final data = await _client
          .from('vocabulary')
          .upsert({
            'user_id': userId,
            'word': word.toLowerCase().trim(),
            'translation': translation,
            'phonetic': phonetic,
            'context_sentence': contextSentence,
            'context_video_id': contextVideoId,
            'context_timestamp_ms': contextTimestampMs,
            'item_type': type,
          }, onConflict: 'user_id,word')
          .select()
          .single();
      return WordCard.fromJson(data);
    } catch (e) {
      debugPrint('🔴 [SupabaseService] Error adding word: $e');
      rethrow;
    }
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

    try {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final todayStatsList = await _client
          .from('daily_stats')
          .select()
          .eq('user_id', userId)
          .eq('date', today)
          .limit(1);
          
      final todayStats = todayStatsList.isNotEmpty ? todayStatsList.first : null;

      final reviewCountData = await _client
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
        wordsToReview: (reviewCountData as List?)?.length ?? 0,
      );
    } catch (e) {
      debugPrint('🔴 [Supabase] Error loading user progress: $e');
      return const UserProgress();
    }
  }

  static Future<void> updateWatchProgress(
    String videoId,
    int positionMs,
    int watchDurationSec,
  ) async {
    final userId = SupabaseConfig.userId;
    if (userId == null || watchDurationSec <= 0 || videoId.isEmpty) return;

    try {
      // Ensure videoId is a UUID. Sometimes we pass a youtube_id instead when the video isn't saved yet.
      String targetVideoId = videoId;
      final isUuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(videoId);
      
      if (!isUuid) {
        final videoData = await _client.from('videos').select('id').eq('youtube_id', videoId).maybeSingle();
        if (videoData == null) return; // Cannot track watch time for a video not in DB
        targetVideoId = videoData['id'];
      }

      await _client.rpc('log_watch_progress', params: {
        'p_user_id': userId,
        'p_video_id': targetVideoId,
        'p_position_ms': positionMs,
        'p_duration_sec': watchDurationSec,
      });
    } catch (e) {
      debugPrint('[SupabaseService] Error logging watch progress: $e');
    }
  }
}
