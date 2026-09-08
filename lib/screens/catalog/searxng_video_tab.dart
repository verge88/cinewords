import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/searx_video.dart';
import '../../services/searxng_service.dart';
import '../player/player_screen.dart';
import 'searx_web_player_screen.dart';

/// Вкладка «Видео» на странице фильмов: метапоиск через SearXNG API.
class SearxngVideoTab extends StatefulWidget {
  const SearxngVideoTab({super.key});

  @override
  State<SearxngVideoTab> createState() => _SearxngVideoTabState();
}

class _SearxngVideoTabState extends State<SearxngVideoTab> {
  static const String _defaultQuery = 'english movie trailer';

  static const List<(String, String)> _topics = [
    ('english movie trailer', 'Трейлеры'),
    ('full movie english subtitles', 'Полные фильмы'),
    ('ted talk', 'TED'),
    ('learn english lesson', 'Уроки английского'),
    ('movie scene english', 'Сцены из фильмов'),
    ('documentary english', 'Документальное'),
    ('interview english', 'Интервью'),
  ];

  final SearxngService _searxng = SearxngService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounce;
  static const Duration _debounceDelay = Duration(milliseconds: 450);

  final List<SearxVideo> _videos = [];
  String _query = _defaultQuery;
  int _page = 1;
  bool _hasMore = false;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(_query));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searxng.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 500) _loadMore();
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _page = 1;
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await _searxng.searchVideos(query);
      if (!mounted) return;
      setState(() {
        _videos
          ..clear()
          ..addAll(page.videos);
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);

    try {
      final next = await _searxng.searchVideos(_query, page: _page + 1);
      if (!mounted) return;

      final seen = _videos.map((v) => v.url).toSet();

      setState(() {
        _videos.addAll(next.videos.where((v) => seen.add(v.url)));
        _page = next.page;
        _hasMore = next.hasMore;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      // Ошибку доподгрузки не показываем на весь экран — просто
      // прекращаем пагинацию.
      debugPrint('[SearXNG] loadMore: $error');
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();

    _debounce = Timer(_debounceDelay, () {
      if (!mounted) return;
      final target = trimmed.isEmpty ? _defaultQuery : trimmed;
      if (target == _query) return;
      _search(target);
    });
  }

  void _open(SearxVideo video) {
    final route = video.isYoutube
        ? MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(video: video.toVideoItem()),
          )
        : MaterialPageRoute<void>(
            builder: (_) => SearxWebPlayerScreen(video: video),
          );

    Navigator.push(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SearchBar(
            controller: _searchController,
            hintText: 'Поиск видео через SearXNG...',
            leading: const Icon(Icons.search),
            onChanged: _onSearchChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              final trimmed = value.trim();
              _search(trimmed.isEmpty ? _defaultQuery : trimmed);
            },
            trailing: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    _search(_defaultQuery);
                  },
                ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _topics.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (query, label) = _topics[index];
              return ChoiceChip(
                label: Text(label),
                selected: _query == query,
                onSelected: (_) {
                  _debounce?.cancel();
                  _searchController.text = label;
                  _search(query);
                },
              );
            },
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _search(_query),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }

    return RefreshIndicator(
      onRefresh: () => _search(_query),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _videos.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _videos.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return _SearxVideoTile(
            video: _videos[index],
            onTap: () => _open(_videos[index]),
          );
        },
      ),
    );
  }
}

class _SearxVideoTile extends StatelessWidget {
  final SearxVideo video;
  final VoidCallback onTap;

  const _SearxVideoTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final meta = [
      if (video.author != null && video.author!.isNotEmpty) video.author!,
      if (video.engine != null && video.engine!.isNotEmpty) video.engine!,
      if (video.publishedDate != null)
        '${video.publishedDate!.day.toString().padLeft(2, '0')}.'
            '${video.publishedDate!.month.toString().padLeft(2, '0')}.'
            '${video.publishedDate!.year}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  SizedBox(
                    width: 168,
                    height: 94,
                    child: video.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: video.thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey.shade900),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.movie_outlined,
                                  color: Colors.grey),
                            ),
                          )
                        : Container(
                            color: Colors.grey.shade900,
                            child: const Icon(Icons.movie_outlined,
                                color: Colors.grey),
                          ),
                  ),
                  if (video.formattedLength.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          video.formattedLength,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                  if (video.isYoutube) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.subtitles_outlined, size: 14),
                        const SizedBox(width: 4),
                        Text('Доступны реплики', style: tt.labelSmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
