import 'package:cinewords/screens/catalog/vidsrc_player_screen.dart';
import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../models/video_item.dart';
import '../../services/archive_org_service.dart';
import '../player/player_screen.dart';

class MoviePlayerScreen extends StatefulWidget {
  final Movie movie;

  const MoviePlayerScreen({super.key, required this.movie});

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  final ArchiveOrgService _archive = ArchiveOrgService();

  VideoItem? _video;
  String? _error;

  @override
  void initState() {
    super.initState();

    if (widget.movie.archiveId != null) {
      _resolve();
    }
  }


  Future<void> _resolve() async {
    try {
      final v = await _buildVideoItem(widget.movie);
      if (!mounted) return;
      // loadVideo вызовется внутри PlayerScreen._load() с уже обогащёнными
      // субтитрами от провайдера — здесь дублировать не нужно.
      setState(() => _video = v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<VideoItem> _buildVideoItem(Movie movie) async {
    // Internet Archive — резолвим прямой mp4 + субтитры в файле
    if (movie.archiveId != null) {
      final stream = await _archive.resolveStream(movie.archiveId!);
      return VideoItem(
        id: 'archive_${movie.archiveId}',
        youtubeId: '',
        title: movie.title,
        sourceType: 'direct',
        videoUrl: stream.videoUrl,
        subtitleUrl: stream.subtitleUrl,
        description: movie.overview,
        thumbnailUrl: movie.posterUrl,
        durationSec: 0,
      );
    }
    // Kinopoisk → vidsrc
    return movie.toVideoItem();
  }

  @override
  void dispose() {
    _archive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
        // Для обычных фильмов используем VidSrc как видеодвижок,
    // а реплики загружаем и отображаем средствами CineWords.
    //
    // Archive.org по-прежнему использует оригинальный media_kit-плеер,
    // потому что там имеется прямой URL видео.
    if (widget.movie.archiveId == null) {
      return VidsrcPlayerScreen(
        movie: widget.movie,
        showReplicas: true,
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.movie.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _resolve();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_video == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.movie.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return PlayerScreen(video: _video!);
  }
}
