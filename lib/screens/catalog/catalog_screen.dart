import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../providers/video_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_data_service.dart';
import '../player/player_screen.dart';

/// Лента в стиле YouTube: полноширинное превью 16:9, под ним аватар канала,
/// заголовок в две строки и строка метаданных.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounce;
  static const Duration _debounceDelay = Duration(milliseconds: 400);

  bool _isSearchOpen = false;
  bool _isBootstrapping = true;
  String _query = '';
  String _category = 'all';
  String _difficulty = 'all';

  static const List<(String, String, IconData)> _categories = [
    ('all', 'Все', Icons.apps_rounded),
    ('movies', 'Фильмы', Icons.movie_rounded),
    ('series', 'Сериалы', Icons.tv_rounded),
    ('ted_talks', 'TED', Icons.mic_rounded),
    ('news', 'Новости', Icons.newspaper_rounded),
    ('interviews', 'Интервью', Icons.people_rounded),
    ('music', 'Музыка', Icons.music_note_rounded),
    ('cartoons', 'Мультфильмы', Icons.animation_rounded),
  ];

  static const List<(String, String)> _difficulties = [
    ('all', 'Любой уровень'),
    ('beginner', 'A1 · Начальный'),
    ('elementary', 'A2 · Базовый'),
    ('intermediate', 'B1 · Средний'),
    ('upper_intermediate', 'B2 · Выше среднего'),
    ('advanced', 'C1 · Продвинутый'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Рекомендации грузим сразу при открытии таба, а не по действию
    // пользователя: экран не должен встречать пустотой.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final videos = context.read<VideoProvider>();

    await Future.wait<void>([
      if (videos.featuredVideos.isEmpty) videos.loadFeatured(),
      if (videos.trendingVideos.isEmpty) videos.loadTrending(),
    ]);

    if (mounted) setState(() => _isBootstrapping = false);
  }

  Future<void> _refresh() async {
    final videos = context.read<VideoProvider>();
    if (_query.isNotEmpty) {
      await videos.search(_query);
      return;
    }
    if (_category != 'all') {
      await videos.loadCategory(_category);
      return;
    }
    await Future.wait<void>([videos.loadFeatured(), videos.loadTrending()]);
  }

  /// Бесконечная прокрутка работает только для результатов поиска —
  /// пагинацию отдаёт YouTube API через nextPageToken.
  void _onScroll() {
    if (_query.isEmpty) return;
    final videos = context.read<VideoProvider>();
    if (videos.isLoading || !videos.hasMore) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      videos.loadMoreSearchResults(_query);
    }
  }

  void _toggleSearch() {
    setState(() => _isSearchOpen = !_isSearchOpen);
    if (_isSearchOpen) {
      _searchFocus.requestFocus();
      return;
    }
    _debounce?.cancel();
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() => _query = '');
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      if (_query.isNotEmpty) setState(() => _query = '');
      return;
    }

    _debounce = Timer(_debounceDelay, () {
      if (!mounted || trimmed == _query) return;
      setState(() => _query = trimmed);
      context.read<VideoProvider>().search(trimmed);
    });
  }

  void _onSearchSubmitted(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _query) return;
    setState(() => _query = trimmed);
    context.read<VideoProvider>().search(trimmed);
  }

  void _searchByChannel(String channelId, String label) {
    _debounce?.cancel();
    _searchController.text = label;
    setState(() {
      _query = label;
      _isSearchOpen = false;
    });
    _searchFocus.unfocus();
    context.read<VideoProvider>().loadFromChannel(channelId);
  }

  void _selectCategory(String value) {
    setState(() => _category = value);
    if (value != 'all') context.read<VideoProvider>().loadCategory(value);
  }

  Future<void> _showDifficultySheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label) in _difficulties)
              RadioListTile<String>(
                value: value,
                groupValue: _difficulty,
                title: Text(label),
                onChanged: (v) => Navigator.of(ctx).pop(v),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _difficulty = selected);
    }
  }

  /// Источник ленты: поиск → категория → рекомендации.
  /// Рекомендации склеены из featured и trending с дедупликацией,
  /// чтобы лента не была короткой на свежем аккаунте.
  List<VideoItem> _feed(VideoProvider videos) {
    List<VideoItem> items;

    if (_query.isNotEmpty) {
      items = videos.searchResults;
    } else if (_category != 'all') {
      items = videos.getByCategory(_category);
    } else {
      final seen = <String>{};
      items = [
        for (final video in [...videos.featuredVideos, ...videos.trendingVideos])
          if (seen.add(video.youtubeId)) video,
      ];
    }

    if (_difficulty == 'all') return items;
    return items.where((v) => v.difficulty == _difficulty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final videos = context.watch<VideoProvider>();
    final feed = _feed(videos);
    final isBusy = videos.isLoading || _isBootstrapping;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        heroTag: 'catalog_search_fab',
        onPressed: _toggleSearch,
        tooltip: _isSearchOpen ? 'Закрыть поиск' : 'Поиск видео',
        child: Icon(_isSearchOpen ? Icons.close_rounded : Icons.search_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // Поисковая строка остаётся наверху экрана — открывается кнопкой
            // из правого нижнего угла.
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 2,
              titleSpacing: _isSearchOpen ? 12 : 20,
              automaticallyImplyLeading: false,
              title: _isSearchOpen
                  ? _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmitted,
                      onClear: () {
                        _debounce?.cancel();
                        _searchController.clear();
                        setState(() => _query = '');
                        _searchFocus.requestFocus();
                      },
                    )
                  : Text(
                      'Видео',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _ChipsBar(
                  categories: _categories,
                  selectedCategory: _category,
                  difficultyLabel: _difficultyLabel,
                  isDifficultyActive: _difficulty != 'all',
                  onCategorySelected: _selectCategory,
                  onDifficultyTap: _showDifficultySheet,
                ),
              ),
            ),

            // Подсказки с обучающими каналами, пока запрос не введён.
            if (_isSearchOpen && _searchController.text.trim().isEmpty)
              SliverList.list(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      'Каналы для изучения',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final entry
                      in YouTubeDataService.learningChannels.entries)
                    ListTile(
                      leading: const Icon(Icons.play_circle_outline_rounded),
                      title: Text(entry.value),
                      trailing: const Icon(Icons.north_east_rounded, size: 18),
                      onTap: () => _searchByChannel(entry.key, entry.value),
                    ),
                ],
              )
            else if (feed.isEmpty && isBusy)
              const _FeedSkeleton()
            else if (feed.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyFeed(
                  isSearch: _query.isNotEmpty,
                  onReset: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _category = 'all';
                      _difficulty = 'all';
                      _isSearchOpen = false;
                    });
                    _refresh();
                  },
                ),
              )
            else
              SliverList.separated(
                itemCount: feed.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final video = feed[index];
                  return _VideoTile(
                    video: video,
                    isFavorite: videos.isFavorite(video.youtubeId),
                    onTap: () => _openVideo(video),
                    onToggleFavorite: () => videos.toggleFavorite(video),
                  );
                },
              ),

            // Индикатор догрузки следующей страницы поиска.
            if (feed.isNotEmpty && videos.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),

            // Место под FAB и таббар, чтобы кнопка не накрывала последнюю карточку.
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  String get _difficultyLabel {
    if (_difficulty == 'all') return 'Уровень';
    return _difficulties.firstWhere((d) => d.$1 == _difficulty).$2.split(' · ').first;
  }

  /// Переход открывается синхронно, до любых сетевых операций: раньше здесь
  /// был await записи в Supabase, из-за которого между тапом и появлением
  /// плеера проходила пауза. Сохранение уходит в фон.
  void _openVideo(VideoItem video) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(video: video)),
    );

    if (video.id.isEmpty) {
      unawaited(
        SupabaseService.addVideo(video).catchError((Object error) {
          debugPrint('[Catalog] Не удалось сохранить видео: $error');
          return video;
        }),
      );
    }
  }
}

// ── Поисковая строка ────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          hintText: 'Поиск видео на YouTube',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    onPressed: onClear,
                  ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ── Строка чипов ────────────────────────────────────────────────────────

class _ChipsBar extends StatelessWidget {
  const _ChipsBar({
    required this.categories,
    required this.selectedCategory,
    required this.difficultyLabel,
    required this.isDifficultyActive,
    required this.onCategorySelected,
    required this.onDifficultyTap,
  });

  final List<(String, String, IconData)> categories;
  final String selectedCategory;
  final String difficultyLabel;
  final bool isDifficultyActive;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onDifficultyTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return FilterChip(
              selected: isDifficultyActive,
              showCheckmark: false,
              avatar: const Icon(Icons.tune_rounded, size: 18),
              label: Text(difficultyLabel),
              onSelected: (_) => onDifficultyTap(),
            );
          }

          final (value, label, icon) = categories[index - 1];
          final selected = selectedCategory == value;
          return FilterChip(
            selected: selected,
            showCheckmark: false,
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onSelected: (_) => onCategorySelected(value),
          );
        },
      ),
    );
  }
}

// ── Карточка видео в стиле YouTube ──────────────────────────────────────

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.video,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final VideoItem video;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Превью во всю ширину — как в мобильном YouTube.
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: video.thumbnailUrl == null
                    ? ColoredBox(color: cs.surfaceContainerHighest)
                    : CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) =>
                            ColoredBox(color: cs.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    _Badge(
                      text: video.difficultyLabel,
                      background: Color(video.difficultyColorValue),
                      foreground: Colors.black.withValues(alpha: 0.8),
                    ),
                    if (video.formattedDuration.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _Badge(
                        text: video.formattedDuration,
                        background: Colors.black.withValues(alpha: 0.78),
                        foreground: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Мета-блок: аватар канала, заголовок в две строки, подпись.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChannelAvatar(name: video.channelName ?? ''),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _metaLine(video),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isFavorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 20,
                  ),
                  tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
                  onPressed: onToggleFavorite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _metaLine(VideoItem video) {
    final parts = <String>[
      if ((video.channelName ?? '').isNotEmpty) video.channelName!,
      if (video.viewCount > 0) '${_compactViews(video.viewCount)} просмотров',
      if (video.totalUniqueWords > 0) '${video.totalUniqueWords} слов',
    ];
    return parts.join(' · ');
  }

  String _compactViews(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1).replaceAll('.0', '')} млн';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1).replaceAll('.0', '')} тыс.';
    }
    return '$count';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

// ── Заглушки ────────────────────────────────────────────────────────────

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = cs.surfaceContainerHighest.withValues(alpha: 0.45);

    return SliverList.builder(
      itemCount: 4,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(color: placeholder),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: placeholder,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 14, color: placeholder),
                        const SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.55,
                          child: Container(height: 12, color: placeholder),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.isSearch, required this.onReset});

  final bool isSearch;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearch ? Icons.search_off_rounded : Icons.video_library_outlined,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              isSearch ? 'Ничего не нашлось' : 'Пока нет видео',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              isSearch
                  ? 'Попробуйте изменить запрос, категорию или уровень'
                  : 'Потяните вниз, чтобы обновить подборку',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onReset,
              child: const Text('Сбросить фильтры'),
            ),
          ],
        ),
      ),
    );
  }
}
