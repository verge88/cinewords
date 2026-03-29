import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/video_provider.dart';
import '../../widgets/video_card.dart';
import '../player/player_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final videoProvider = context.watch<VideoProvider>();
    final favorites = videoProvider.favoriteVideos;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Favorites', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (favorites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('${favorites.length}'),
                backgroundColor: cs.primaryContainer,
                labelStyle: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
                side: BorderSide.none,
                shape: const StadiumBorder(),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => videoProvider.loadFavorites(), // Refreshes only favorites
        child: favorites.isEmpty
            ? _buildEmptyState(context)
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: favorites.length,
                itemBuilder: (context, index) {
                  final video = favorites[index];
                  return VideoCard(
                    video: video,
                    isCompact: true, // We should add this flag to VideoCard if we want it smaller
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(video: video),
                      ),
                    ),
                  ).animate().fadeIn(delay: (index * 50).ms).scale(begin: const Offset(0.95, 0.95));
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Stack(
      children: [
        ListView(), // To make RefreshIndicator work
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 64,
                    color: cs.primary.withOpacity(0.2),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Your library is empty',
                  style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Collect videos you want to learn from. Tap the heart icon on any video to save it here.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.explore_rounded),
                  label: const Text('Discover Videos'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
