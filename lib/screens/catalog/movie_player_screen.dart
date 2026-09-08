import 'package:flutter/material.dart';

import '../../models/movie.dart';
import '../../models/video_item.dart';
import '../../services/archive_org_service.dart';
import '../player/player_screen.dart';
import 'vidsrc_player_screen.dart';

class MoviePlayerScreen extends StatefulWidget {
  final Movie movie;

  const MoviePlayerScreen({
    super.key,
    required this.movie,
  });

  @override
  State<MoviePlayerScreen> createState() =>
      _MoviePlayerScreenState();
}

class _MoviePlayerScreenState
    extends State<MoviePlayerScreen> {
  final ArchiveOrgService _archive = ArchiveOrgService();

  VideoItem? _video;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Для Archive.org нужен прямой URL, поэтому сначала
    // резолвим информацию о потоке.
    if (widget.movie.archiveId != null) {
      _resolveArchiveVideo();
    }
  }

  Future<void> _resolveArchiveVideo() async {
    try {
      final video = await _buildArchiveVideoItem(
        widget.movie,
      );

      if (!mounted) return;

      setState(() {
        _video = video;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error
            .toString()
            .replaceAll('Exception: ', '');
      });
    }
  }

  Future<VideoItem> _buildArchiveVideoItem(
    Movie movie,
  ) async {
    final archiveId = movie.archiveId;

    if (archiveId == null || archiveId.isEmpty) {
      throw Exception(
        'У фильма отсутствует Archive.org ID',
      );
    }

    final stream = await _archive.resolveStream(
      archiveId,
    );

    return VideoItem(
      id: 'archive_$archiveId',
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

  @override
  void dispose() {
    _archive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Обычные фильмы:
    // VidSpark отвечает за воспроизведение,
    // CineWords загружает и синхронизирует реплики.
    if (widget.movie.archiveId == null) {
      return VidsrcPlayerScreen(
        movie: widget.movie,
        showReplicas: true,
      );
    }

    // Archive.org имеет прямой URL потока, поэтому здесь
    // используется оригинальный media_kit PlayerScreen.
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.movie.title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                    });

                    _resolveArchiveVideo();
                  },
                  icon: const Icon(
                    Icons.refresh_rounded,
                  ),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_video == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.movie.title),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return PlayerScreen(
      video: _video!,
    );
  }
}
