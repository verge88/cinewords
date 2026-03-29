import 'dart:convert';
import 'package:cinewords/services/youtube_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/video_item.dart';

class YouTubeDataService {
  final http.Client _client = http.Client();

  // ──────────────── SEARCH ────────────────

  /// Search YouTube for videos
  Future<YouTubeSearchResult> searchVideos(
      String query, {
        int maxResults = YouTubeConfig.defaultMaxResults,
        String? pageToken,
        String? categoryId,
        String order = 'relevance', // relevance, date, viewCount, rating
      }) async {
    final params = {
      'part': 'snippet',
      'q': query,
      'type': 'video',
      'maxResults': maxResults.toString(),
      'key': YouTubeConfig.apiKey,
      'relevanceLanguage': YouTubeConfig.defaultRelevanceLanguage,
      'videoCaption': 'closedCaption', // Only videos with captions!
      'videoEmbeddable': 'true', // Only embeddable videos
      'order': order,
      if (pageToken != null) 'pageToken': pageToken,
      if (categoryId != null) 'videoCategoryId': categoryId,
    };

    final uri = Uri.parse('${YouTubeConfig.baseUrl}/search')
        .replace(queryParameters: params);

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
          'YouTube search failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body);
    final videoIds =
    (json['items'] as List).map((e) => e['id']['videoId'] as String).toList();

    // Get full details (duration, stats) for found videos
    final videos = await getVideoDetails(videoIds);

    return YouTubeSearchResult(
      videos: videos,
      nextPageToken: json['nextPageToken'],
      prevPageToken: json['prevPageToken'],
      totalResults: json['pageInfo']['totalResults'] ?? 0,
    );
  }

  /// Search specifically for English learning content
  Future<YouTubeSearchResult> searchLearningContent(
      String topic, {
        String? pageToken,
        String difficulty = 'intermediate',
      }) async {
    final queryMap = {
      'beginner': '$topic english for beginners easy',
      'elementary': '$topic english elementary level',
      'intermediate': '$topic english intermediate',
      'upper_intermediate': '$topic english upper intermediate advanced',
      'advanced': '$topic english advanced native speaker',
    };

    return searchVideos(
      queryMap[difficulty] ?? '$topic english',
      pageToken: pageToken,
      order: 'relevance',
    );
  }

  // ──────────────── VIDEO DETAILS ────────────────

  /// Get detailed info for a list of video IDs
  Future<List<VideoItem>> getVideoDetails(List<String> videoIds) async {
    if (videoIds.isEmpty) return [];

    final params = {
      'part': 'snippet,contentDetails,statistics',
      'id': videoIds.join(','),
      'key': YouTubeConfig.apiKey,
    };

    final uri = Uri.parse('${YouTubeConfig.baseUrl}/videos')
        .replace(queryParameters: params);

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('YouTube video details failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    final items = json['items'] as List;

    return items.map((item) => _parseVideoItem(item)).toList();
  }

  /// Get detailed info for a single video
  Future<VideoItem?> getVideoDetail(String videoId) async {
    final videos = await getVideoDetails([videoId]);
    return videos.isNotEmpty ? videos.first : null;
  }

  // ──────────────── CHANNELS ────────────────

  /// Get videos from a specific channel
  Future<YouTubeSearchResult> getChannelVideos(
      String channelId, {
        int maxResults = 20,
        String? pageToken,
      }) async {
    final params = {
      'part': 'snippet',
      'channelId': channelId,
      'type': 'video',
      'maxResults': maxResults.toString(),
      'key': YouTubeConfig.apiKey,
      'order': 'date',
      'videoCaption': 'closedCaption',
      if (pageToken != null) 'pageToken': pageToken,
    };

    final uri = Uri.parse('${YouTubeConfig.baseUrl}/search')
        .replace(queryParameters: params);

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('YouTube channel videos failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    final videoIds =
    (json['items'] as List).map((e) => e['id']['videoId'] as String).toList();

    final videos = await getVideoDetails(videoIds);

    return YouTubeSearchResult(
      videos: videos,
      nextPageToken: json['nextPageToken'],
      totalResults: json['pageInfo']['totalResults'] ?? 0,
    );
  }

  // ──────────────── POPULAR / TRENDING ────────────────

  /// Get popular/trending videos (for home feed)
  Future<List<VideoItem>> getPopularVideos({
    String regionCode = 'US',
    String videoCategoryId = '27', // 27 = Education
    int maxResults = 10,
  }) async {
    final params = {
      'part': 'snippet,contentDetails,statistics',
      'chart': 'mostPopular',
      'regionCode': regionCode,
      'videoCategoryId': videoCategoryId,
      'maxResults': maxResults.toString(),
      'key': YouTubeConfig.apiKey,
    };

    final uri = Uri.parse('${YouTubeConfig.baseUrl}/videos')
        .replace(queryParameters: params);

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('YouTube popular failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    return (json['items'] as List).map((e) => _parseVideoItem(e)).toList();
  }

  // ──────────────── CURATED CHANNELS ────────────────

  /// Predefined channels great for English learning
  static const Map<String, String> learningChannels = {
    'UCVhQ2NnY5Rskt6UjCUkJ_DA': 'TED',
    'UCHaHD477h-FeBbRgHUEMRCA': 'BBC Learning English',
    'UCVBErcpqaokOf4fI5j73K_w': 'English with Lucy',
    'UC4cmBAit8i_NJZE8qK8sfpA': 'Rachel\'s English',
    'UCAuUUnT6oDeKwE6v1NGQxug': 'TED-Ed',
    'UCNjPtOCvMrKY5eLwr_-7eUg': 'Learn English with TV Series',
    'UC2gyzKR9VBIgeaRUYl1WFBg': 'EngVid',
  };

  // ──────────────── PARSING ────────────────

  VideoItem _parseVideoItem(Map<String, dynamic> item) {
    final snippet = item['snippet'] ?? {};
    final contentDetails = item['contentDetails'] ?? {};
    final statistics = item['statistics'] ?? {};
    final thumbnails = snippet['thumbnails'] ?? {};

    return VideoItem(
      id: '', // Will be set when saved to Supabase
      youtubeId: item['id'] is String ? item['id'] : (item['id']?['videoId'] ?? ''),
      title: snippet['title'] ?? '',
      description: snippet['description'] ?? '',
      thumbnailUrl: thumbnails['high']?['url'] ??
          thumbnails['medium']?['url'] ??
          thumbnails['default']?['url'],
      channelName: snippet['channelTitle'] ?? '',
      durationSec: _parseIsoDuration(contentDetails['duration']) ?? 0,
      difficulty: _estimateDifficulty(snippet),
      category: _categorize(snippet),
      keywords: List<String>.from(snippet['tags'] ?? []).take(10).toList(),
      totalUniqueWords: 0,
      viewCount: int.tryParse(statistics['viewCount'] ?? '0') ?? 0,
      isFeatured: false,
    );
  }

  /// Parse ISO 8601 duration (PT1H2M3S) to seconds
  int? _parseIsoDuration(String? iso) {
    if (iso == null) return null;
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(iso);
    if (match == null) return null;

    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;

    return hours * 3600 + minutes * 60 + seconds;
  }

  /// Estimate difficulty based on channel / description
  String _estimateDifficulty(Map<String, dynamic> snippet) {
    final title = (snippet['title'] ?? '').toString().toLowerCase();
    final desc = (snippet['description'] ?? '').toString().toLowerCase();
    final combined = '$title $desc';

    if (combined.contains('beginner') || combined.contains('a1') || combined.contains('easy english')) {
      return 'beginner';
    }
    if (combined.contains('elementary') || combined.contains('a2') || combined.contains('basic')) {
      return 'elementary';
    }
    if (combined.contains('advanced') || combined.contains('c1') || combined.contains('native')) {
      return 'advanced';
    }
    if (combined.contains('upper') || combined.contains('b2')) {
      return 'upper_intermediate';
    }
    return 'intermediate';
  }

  /// Categorize based on content
  String _categorize(Map<String, dynamic> snippet) {
    final title = (snippet['title'] ?? '').toString().toLowerCase();
    final channelTitle = (snippet['channelTitle'] ?? '').toString().toLowerCase();
    final combined = '$title $channelTitle';

    if (combined.contains('ted')) return 'ted_talks';
    if (combined.contains('news') || combined.contains('bbc')) return 'news';
    if (combined.contains('interview')) return 'interviews';
    if (combined.contains('movie') || combined.contains('film') || combined.contains('scene')) {
      return 'movies';
    }
    if (combined.contains('series') || combined.contains('episode') || combined.contains('sitcom')) {
      return 'series';
    }
    if (combined.contains('song') || combined.contains('music') || combined.contains('lyric')) {
      return 'music';
    }
    if (combined.contains('cartoon') || combined.contains('animation') || combined.contains('disney')) {
      return 'cartoons';
    }
    return 'general';
  }

  void dispose() {
    _client.close();
  }
}

/// Search result with pagination support
class YouTubeSearchResult {
  final List<VideoItem> videos;
  final String? nextPageToken;
  final String? prevPageToken;
  final int totalResults;

  const YouTubeSearchResult({
    required this.videos,
    this.nextPageToken,
    this.prevPageToken,
    this.totalResults = 0,
  });
}
