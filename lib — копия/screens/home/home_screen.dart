import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/video_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/user_progress.dart';
import '../../widgets/video_card.dart';
import '../../widgets/progress_ring.dart';
import '../catalog/catalog_screen.dart';
import '../player/player_screen.dart';
import '../vocabulary/vocabulary_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  UserProgress _progress = const UserProgress();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    context.read<VideoProvider>().loadFeatured();
    context.read<VideoProvider>().loadTrending();
    context.read<VocabularyProvider>().loadAll();
    final progress = await SupabaseService.getUserProgress();
    if (mounted) setState(() => _progress = progress);
  }


  @override
  Widget build(BuildContext context) {
    final screens = [
      _HomeTab(progress: _progress, onRefresh: _loadData),
      const CatalogScreen(),
      const VocabularyScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Words',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final UserProgress progress;
  final VoidCallback onRefresh;

  const _HomeTab({required this.progress, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();
    final videoProvider = context.watch<VideoProvider>();

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${auth.displayName}!',
                  style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Ready to learn?',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── Progress Card ───
                _buildProgressCard(context).animate().fadeIn().slideY(begin: 0.1),
                const SizedBox(height: 24),

                // ─── Quick Actions ───
                _buildQuickActions(context)
                    .animate(delay: 100.ms)
                    .fadeIn()
                    .slideY(begin: 0.1),
                const SizedBox(height: 28),

                // ─── Featured Videos ───
                Text('Featured', style: tt.titleLarge)
                    .animate(delay: 200.ms)
                    .fadeIn(),
                const SizedBox(height: 12),

                if (videoProvider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (videoProvider.featuredVideos.isEmpty)
                  _buildEmptyState(context)
                else
                  ...videoProvider.featuredVideos.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VideoCard(
                        video: entry.value,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(video: entry.value),
                          ),
                        ),
                      ),
                    )
                        .animate(delay: (300 + entry.key * 80).ms)
                        .fadeIn()
                        .slideX(begin: 0.05),
                  ),

                const SizedBox(height: 24),

                // ─── Add YouTube Video ───
                _buildAddVideoButton(context)
                    .animate(delay: 500.ms)
                    .fadeIn(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            ProgressRing(
              progress: progress.dailyProgressPercent,
              size: 80,
              strokeWidth: 8,
              color: cs.primary,
              backgroundColor: cs.primary.withOpacity(0.15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${progress.todayMinutes}',
                    style: tt.titleLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'min',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_fire_department_rounded,
                          color: cs.tertiary, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '${progress.streakDays} day streak',
                        style: tt.titleMedium?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${progress.totalWordsLearned} words learned',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${progress.wordsToReview} words to review',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer.withOpacity(0.8),
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

  Widget _buildQuickActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _QuickActionChip(
            icon: Icons.replay_rounded,
            label: '${progress.wordsToReview} to review',
            color: cs.tertiary,
            onTap: () {
              // Navigate to review
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionChip(
            icon: Icons.history_rounded,
            label: 'Continue watching',
            color: cs.secondary,
            onTap: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.video_library_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'No videos yet',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a YouTube video to start learning!',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAddVideoButton(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _showAddVideoDialog(context),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add YouTube Video'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
      ),
    );
  }

  void _showAddVideoDialog(BuildContext context) {
    final controller = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add YouTube Video',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Paste YouTube URL or video ID',
                prefixIcon: Icon(Icons.link, color: cs.primary),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final video = await context
                    .read<VideoProvider>()
                    .importYouTubeVideo(controller.text.trim());
                if (video != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PlayerScreen(video: video)),
                  );
                }
              },
              child: const Text('Import & Watch'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
