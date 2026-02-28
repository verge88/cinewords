import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/supabase_service.dart';
import '../services/youtube_data_service.dart';

class VideoProvider extends ChangeNotifier {
  final YouTubeDataService _ytDataService = YouTubeDataService();

  List<VideoItem> _featuredVideos = [];
  List<VideoItem> _searchResults = [];
  List<VideoItem> _trendingVideos = [];
  final Map<String, List<VideoItem>> _categoryVideos = {};
  bool _isLoading = false;
  String? _error;
  String? _nextPageToken;

  List<VideoItem> get featuredVideos => _featuredVideos;
  List<VideoItem> get searchResults => _searchResults;
  List<VideoItem> get trendingVideos => _trendingVideos;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _nextPageToken != null;

  List<VideoItem> getByCategory(String cat) => _categoryVideos[cat] ?? [];

  /// Load featured videos from Supabase (curated)
  Future<void> loadFeatured() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _featuredVideos = await SupabaseService.getFeaturedVideos();

      // If Supabase is empty, fetch trending education videos from YouTube
      if (_featuredVideos.isEmpty) {
        _featuredVideos = await _ytDataService.getPopularVideos(
          videoCategoryId: '27', // Education
          maxResults: 10,
        );
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('VideoProvider: Error loading featured: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load trending English learning videos
  Future<void> loadTrending() async {
    try {
      final result = await _ytDataService.searchVideos(
        'learn english conversation',
        maxResults: 10,
        order: 'viewCount',
      );
      _trendingVideos = result.videos;
      notifyListeners();
    } catch (e) {
      debugPrint('VideoProvider: Error loading trending: $e');
    }
  }

  /// Load videos by category (using YouTube search)
  Future<void> loadCategory(String category) async {
    _isLoading = true;
    notifyListeners();

    try {
      final queryMap = {
        'movies': 'english movie scenes with subtitles',
        'series': 'english tv series scenes learn english',
        'ted_talks': 'TED talk english subtitles',
        'news': 'BBC news english learning',
        'interviews': 'english interview conversation practice',
        'music': 'english songs lyrics learn english',
        'cartoons': 'english cartoons with subtitles',
        'general': 'learn english video lesson',
      };

      final result = await _ytDataService.searchVideos(
        queryMap[category] ?? 'learn english $category',
        maxResults: 20,
      );

      _categoryVideos[category] = result.videos;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load videos from a curated learning channel
  Future<void> loadFromChannel(String channelId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _ytDataService.getChannelVideos(
        channelId,
        maxResults: 20,
      );
      _searchResults = result.videos;
      _nextPageToken = result.nextPageToken;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Search videos by user query
  Future<void> search(String query) async {
    _isLoading = true;
    _nextPageToken = null;
    notifyListeners();

    try {
      final result = await _ytDataService.searchVideos(
        '$query english subtitles',
        maxResults: 20,
      );
      _searchResults = result.videos;
      _nextPageToken = result.nextPageToken;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load more search results (pagination)
  Future<void> loadMoreSearchResults(String query) async {
    if (_nextPageToken == null || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _ytDataService.searchVideos(
        '$query english subtitles',
        maxResults: 20,
        pageToken: _nextPageToken,
      );
      _searchResults.addAll(result.videos);
      _nextPageToken = result.nextPageToken;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Import a YouTube video by URL/ID — get details and save to Supabase
  Future<VideoItem?> importYouTubeVideo(String urlOrId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Extract video ID from URL if needed
      final videoId = _extractVideoId(urlOrId);

      // Get details from YouTube Data API
      final video = await _ytDataService.getVideoDetail(videoId);

      if (video == null) {
        _error = 'Video not found';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // Save to Supabase
      final saved = await SupabaseService.addVideo(video);
      _featuredVideos.insert(0, saved);

      _isLoading = false;
      notifyListeners();
      return saved;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Extract video ID from various YouTube URL formats
  String _extractVideoId(String input) {
    input = input.trim();

    // Already just an ID (11 chars)
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(input)) return input;

    // Standard URL: youtube.com/watch?v=ID
    final uri = Uri.tryParse(input);
    if (uri != null) {
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v']!;
      }
      // Short URL: youtu.be/ID
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : input;
      }
      // Embed URL: youtube.com/embed/ID
      if (uri.pathSegments.contains('embed') && uri.pathSegments.length > 1) {
        final idx = uri.pathSegments.indexOf('embed');
        return uri.pathSegments[idx + 1];
      }
      // Shorts URL: youtube.com/shorts/ID
      if (uri.pathSegments.contains('shorts') && uri.pathSegments.length > 1) {
        final idx = uri.pathSegments.indexOf('shorts');
        return uri.pathSegments[idx + 1];
      }
    }

    return input; // Assume it's an ID
  }

  @override
  void dispose() {
    _ytDataService.dispose();
    super.dispose();
  }
}
