import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/supabase_service.dart';
import '../services/youtube_data_service.dart';

class VideoProvider extends ChangeNotifier {
  final YouTubeDataService _ytDataService = YouTubeDataService();

  List<VideoItem> _featuredVideos = [];
  List<VideoItem> _searchResults = [];
  List<VideoItem> _trendingVideos = [];
  List<VideoItem> _favoriteVideos = [];
  final Map<String, List<VideoItem>> _categoryVideos = {};
  bool _isLoading = false;
  String? _error;
  String? _nextPageToken;
  Set<String> _favoriteVideoIds = {};

  List<VideoItem> get featuredVideos => _featuredVideos;
  List<VideoItem> get searchResults => _searchResults;
  List<VideoItem> get trendingVideos => _trendingVideos;
  List<VideoItem> get favoriteVideos => _favoriteVideos;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _nextPageToken != null;
  Set<String> get favoriteVideoIds => _favoriteVideoIds;
  
  bool isFavorite(String videoId) => _favoriteVideoIds.contains(videoId);

  List<VideoItem> getByCategory(String cat) => _categoryVideos[cat] ?? [];

  /// Load featured videos from Supabase (curated)
  Future<void> loadFeatured() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load favorites IDs first for UI status
      _favoriteVideoIds = (await SupabaseService.getFavoriteIds()).toSet();
      
      _featuredVideos = await SupabaseService.getFeaturedVideos();

      // Load full favorites list
      await loadFavorites();

      // If Supabase is empty, fetch trending education videos from YouTube
      if (_featuredVideos.isEmpty) {
        _featuredVideos = await _ytDataService.getPopularVideos(
          videoCategoryId: '27', // Education
          maxResults: 10,
        );
      }

      // If still empty (e.g., API limits or region issues), fallback to a search for quality learning content
      if (_featuredVideos.isEmpty) {
        final searchResult = await _ytDataService.searchVideos(
          'english learning lessons with subtitles',
          maxResults: 10,
          order: 'viewCount',
        );
        _featuredVideos = searchResult.videos;
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('VideoProvider: Error loading featured: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadFavorites() async {
    try {
      _favoriteVideoIds = (await SupabaseService.getFavoriteIds()).toSet();
      _favoriteVideos = await SupabaseService.getFavoriteVideos();
      notifyListeners();
    } catch (e) {
      debugPrint('VideoProvider: Error loading favorites: $e');
    }
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
    _searchResults = [];
    notifyListeners();

    try {
      final trimmed = query.trim();
      final id = _extractVideoId(trimmed);

      // If it looks like a YouTube ID (11 chars) and was extracted from a URL
      // or looks specifically like an ID, try to fetch it directly
      if (id.length == 11 && (trimmed.contains('youtube.com') || trimmed.contains('youtu.be') || trimmed == id)) {
        final video = await _ytDataService.getVideoDetail(id);
        if (video != null) {
          _searchResults = [video];
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      // Otherwise do a general search
      final result = await _ytDataService.searchVideos(
        trimmed,
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
        query.trim(),
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

  /// Import a custom video by direct URL
  Future<VideoItem?> importCustomVideo(String url) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.tryParse(url);
      final filename = uri?.pathSegments.isNotEmpty == true 
          ? uri!.pathSegments.last 
          : 'Custom Video';

      final video = VideoItem(
        id: '', // Supabase handles UUID generation
        youtubeId: 'custom_${url.hashCode}', // Fallback unique ID
        title: filename,
        sourceType: 'direct',
        videoUrl: url,
        durationSec: 0, 
      );

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

  /// Import a VidAPI video by full embed URL or IMDB ID
  Future<VideoItem?> importVidApiVideo(String urlOrId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String embedUrl = urlOrId;
      String id = urlOrId;
      final text = urlOrId.trim();
      
      if (text.contains('vidapi.xyz')) {
         final uri = Uri.tryParse(text);
         if (uri != null && uri.pathSegments.isNotEmpty) {
           id = uri.pathSegments.last;
         }
      } else if (text.startsWith('tt')) {
         embedUrl = 'https://vidapi.xyz/embed/movie/$text';
         id = text;
      }

      final video = VideoItem(
        id: '', // Supabase handles UUID generation
        youtubeId: 'vidapi_$id', 
        title: 'Movie: $id',
        sourceType: 'vidapi',
        videoUrl: embedUrl,
        durationSec: 0, 
      );

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

  Future<void> toggleFavorite(VideoItem video) async {
    VideoItem targetVideo = video;
    
    // If video is from YouTube search/trending, it might not be in our DB yet
    if (targetVideo.id.isEmpty) {
      try {
        targetVideo = await SupabaseService.addVideo(targetVideo);
        // Replace in existing lists so UI reflects the new object with ID
        _updateVideoInLists(targetVideo);
      } catch (e) {
        debugPrint('VideoProvider: Failed to auto-save video for favorite: $e');
        return; 
      }
    }

    final isFav = isFavorite(targetVideo.id);
    if (isFav) {
      _favoriteVideoIds.remove(targetVideo.id);
      _favoriteVideos.removeWhere((v) => v.id == targetVideo.id);
    } else {
      _favoriteVideoIds.add(targetVideo.id);
      _favoriteVideos.insert(0, targetVideo);
    }
    notifyListeners();

    try {
      await SupabaseService.toggleFavorite(targetVideo.id, !isFav);
    } catch (e) {
      // Revert on error
      if (isFav) {
        _favoriteVideoIds.add(targetVideo.id);
        _favoriteVideos.insert(0, targetVideo);
      } else {
        _favoriteVideoIds.remove(targetVideo.id);
        _favoriteVideos.removeWhere((v) => v.id == targetVideo.id);
      }
      notifyListeners();
    }
  }

  void _updateVideoInLists(VideoItem newVideo) {
    // Helper to find and replace video in all active lists
    void replaceInList(List<VideoItem> list) {
      final idx = list.indexWhere((v) => v.youtubeId == newVideo.youtubeId);
      if (idx != -1) list[idx] = newVideo;
    }

    replaceInList(_featuredVideos);
    replaceInList(_trendingVideos);
    replaceInList(_searchResults);
    _categoryVideos.values.forEach(replaceInList);
  }

  @override
  void dispose() {
    _ytDataService.dispose();
    super.dispose();
  }
}
