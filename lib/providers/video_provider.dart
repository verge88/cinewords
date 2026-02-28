import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/supabase_service.dart';
import '../services/youtube_service.dart';

class VideoProvider extends ChangeNotifier {
  final YouTubeService _ytService = YouTubeService();

  List<VideoItem> _featuredVideos = [];
  List<VideoItem> _searchResults = [];
  Map<String, List<VideoItem>> _categoryVideos = {};
  bool _isLoading = false;
  String? _error;

  List<VideoItem> get featuredVideos => _featuredVideos;
  List<VideoItem> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<VideoItem> getByCategory(String cat) => _categoryVideos[cat] ?? [];

  Future<void> loadFeatured() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _featuredVideos = await SupabaseService.getFeaturedVideos();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCategory(String category) async {
    try {
      _categoryVideos[category] =
          await SupabaseService.getVideosByCategory(category);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    _isLoading = true;
    notifyListeners();

    try {
      _searchResults = await SupabaseService.searchVideos(query);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Import a YouTube video by URL/ID into the catalog
  Future<VideoItem?> importYouTubeVideo(String urlOrId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final video = await _ytService.getVideoInfo(urlOrId);

      final item = VideoItem(
        id: '',
        youtubeId: video.id.value,
        title: video.title,
        description: video.description,
        thumbnailUrl: video.thumbnails.highResUrl,
        channelName: video.author,
        durationSeconds: video.duration?.inSeconds,
      );

      final saved = await SupabaseService.addVideo(item);
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

  @override
  void dispose() {
    _ytService.dispose();
    super.dispose();
  }
}
