import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/video_provider.dart';
import '../../models/video_item.dart';
import '../../services/supabase_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/video_card.dart';
import '../player/player_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'all';
  String _selectedDifficulty = 'all';
  String _lastQuery = '';

  static const _categories = [
    ('all', 'All', Icons.apps_rounded),
    ('movies', 'Movies', Icons.movie_rounded),
    ('series', 'Series', Icons.tv_rounded),
    ('ted_talks', 'TED Talks', Icons.mic_rounded),
    ('news', 'News', Icons.newspaper_rounded),
    ('interviews', 'Interviews', Icons.people_rounded),
    ('music', 'Music', Icons.music_note_rounded),
    ('cartoons', 'Cartoons', Icons.animation_rounded),
  ];

  static const _difficulties = [
    ('all', 'All Levels'),
    ('beginner', 'A1 Beginner'),
    ('elementary', 'A2 Elementary'),
    ('intermediate', 'B1 Intermediate'),
    ('upper_intermediate', 'B2 Upper'),
    ('advanced', 'C1 Advanced'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final videoProvider = context.watch<VideoProvider>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text('Catalog', style: tt.headlineMedium),
          ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Search YouTube videos...',
                leading: Icon(Icons.search, color: cs.onSurfaceVariant),
                trailing: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _lastQuery = '';
                        setState(() {});
                      },
                    ),
                ],
                onSubmitted: (q) {
                  if (q.trim().isNotEmpty) {
                    _lastQuery = q.trim();
                    videoProvider.search(q.trim());
                  }
                },
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  cs.surfaceContainerHighest.withOpacity(0.4),
                ),
              ),
            ).animate().fadeIn().slideY(begin: -0.1),
          ),

          // Category chips
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (value, label, icon) = _categories[index];
                  final selected = _selectedCategory == value;
                  return FilterChip(
                    selected: selected,
                    label: Text(label),
                    avatar: Icon(icon, size: 18),
                    onSelected: (_) {
                      setState(() => _selectedCategory = value);
                      if (value != 'all') videoProvider.loadCategory(value);
                    },
                  );
                },
              ),
            ).animate(delay: 100.ms).fadeIn(),
          ),

          // Difficulty filter
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _difficulties.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final (value, label) = _difficulties[index];
                    final selected = _selectedDifficulty == value;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      onSelected: (_) {
                        setState(() => _selectedDifficulty = value);
                      },
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
            ),
          ),

          // Learning channels section (when no search)
          if (_lastQuery.isEmpty && _selectedCategory == 'all') ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Learning Channels', style: tt.titleMedium),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: YouTubeDataService.learningChannels.entries
                      .map((entry) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(entry.value),
                      avatar: const Icon(Icons.play_circle_outline,
                          size: 18),
                      onPressed: () {
                        videoProvider.loadFromChannel(entry.key);
                        _lastQuery = entry.value;
                        _searchController.text = entry.value;
                        setState(() {});
                      },
                    ),
                  ))
                      .toList(),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Video list
          _buildVideoList(videoProvider),

          // Load more button
          if (videoProvider.hasMore && _lastQuery.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: OutlinedButton(
                  onPressed: videoProvider.isLoading
                      ? null
                      : () => videoProvider.loadMoreSearchResults(_lastQuery),
                  child: videoProvider.isLoading
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Load More'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoList(VideoProvider provider) {
    List<VideoItem> videos;

    if (_lastQuery.isNotEmpty) {
      videos = provider.searchResults;
    } else if (_selectedCategory != 'all') {
      videos = provider.getByCategory(_selectedCategory);
    } else {
      videos = provider.featuredVideos;
    }

    if (_selectedDifficulty != 'all') {
      videos =
          videos.where((v) => v.difficulty == _selectedDifficulty).toList();
    }

    if (provider.isLoading && videos.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (videos.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('No videos found',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Try a different search or category',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final video = videos[index];
          return VideoCard(
            video: video,
            onTap: () async {
              // Save to Supabase before navigating
              VideoItem savedVideo = video;
              if (video.id.isEmpty) {
                try {
                  savedVideo = await SupabaseService.addVideo(video);
                } catch (_) {
                  // Play anyway even if save fails
                }
              }
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(video: savedVideo),
                  ),
                );
              }
            },
          ).animate(delay: (index * 60).ms).fadeIn().slideY(begin: 0.05);
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
