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
import '../catalog/movie_catalog_screen.dart';
import '../catalog/favorites_screen.dart';
import '../player/player_screen.dart';
import '../vocabulary/vocabulary_screen.dart';
import '../exercises/exercises_hub_screen.dart';
import '../dictionary/full_dictionary_screen.dart';
import '../profile/profile_screen.dart';
import '../../models/video_item.dart';

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
      const MovieCatalogScreen(),
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
            label: 'Videos',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie_rounded),
            label: 'Movies',
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

// ═══════════════════════════════════════════════════════════════
//                          HOME TAB
// ═══════════════════════════════════════════════════════════════
class _HomeTab extends StatelessWidget {
  final UserProgress progress;
  final VoidCallback onRefresh;

  const _HomeTab({required this.progress, required this.onRefresh});

  String _greetingByHour() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Доброй ночи';
    if (h < 12) return 'Доброе утро';
    if (h < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final videoProvider = context.watch<VideoProvider>();
    final vocab = context.watch<VocabularyProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ─── HERO ───
            SliverToBoxAdapter(
              child: _HeroHeader(
                greeting: _greetingByHour(),
                userName: auth.displayName,
                progress: progress,
              ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.05),
            ),

            // ─── BENTO STATS ───
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              sliver: SliverToBoxAdapter(
                child: _BentoStatsGrid(progress: progress, vocab: vocab)
                    .animate(delay: 80.ms)
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.05),
              ),
            ),

            // ─── DAILY PLAN CTA ───
            if (vocab.reviewQueue.isNotEmpty || progress.wordsToReview > 0)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: _DailyPlanCard(
                    wordsToReview: progress.wordsToReview > 0
                        ? progress.wordsToReview
                        : vocab.reviewQueue.length,
                  ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1),
                ),
              ),

            // ─── QUICK ACTIONS ───
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverToBoxAdapter(
                child: _QuickActionsRow()
                    .animate(delay: 200.ms)
                    .fadeIn()
                    .slideY(begin: 0.1),
              ),
            ),

            // ─── CONTINUE WATCHING / FAVORITES ───
            if (videoProvider.favoriteVideos.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Продолжить',
                  icon: Icons.play_circle_outline_rounded,
                  onSeeAll: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FavoritesScreen()),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 270,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: videoProvider.favoriteVideos.length,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemBuilder: (ctx, i) {
                      final v = videoProvider.favoriteVideos[i];
                      return Container(
                        width: 280,
                        margin: const EdgeInsets.only(right: 14),
                        child: VideoCard(
                          video: v,
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) => PlayerScreen(video: v)),
                          ),
                        ),
                      )
                          .animate(delay: (300 + i * 60).ms)
                          .fadeIn()
                          .slideX(begin: 0.08);
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],

            // ─── FEATURED ───
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Рекомендуем',
                icon: Icons.auto_awesome_rounded,
                onSeeAll: () {},
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (videoProvider.isLoading && videoProvider.featuredVideos.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (videoProvider.featuredVideos.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _EmptyVideosCard()
                      .animate(delay: 300.ms)
                      .fadeIn()
                      .slideY(begin: 0.1),
                ),
              )
            else
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 270,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: videoProvider.featuredVideos.length,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemBuilder: (ctx, i) {
                      final v = videoProvider.featuredVideos[i];
                      return Container(
                        width: 280,
                        margin: const EdgeInsets.only(right: 14),
                        child: VideoCard(
                          video: v,
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                                builder: (_) => PlayerScreen(video: v)),
                          ),
                        ),
                      )
                          .animate(delay: (320 + i * 60).ms)
                          .fadeIn()
                          .slideX(begin: 0.08);
                    },
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ─── TRENDING ───
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'В тренде',
                icon: Icons.trending_up_rounded,
                onSeeAll: () {},
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (videoProvider.isLoading && videoProvider.trendingVideos.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: videoProvider.trendingVideos.take(5).length,
                  itemBuilder: (ctx, i) {
                    final v = videoProvider.trendingVideos[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VideoCard(
                        video: v,
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                              builder: (_) => PlayerScreen(video: v)),
                        ),
                      ),
                    )
                        .animate(delay: (400 + i * 60).ms)
                        .fadeIn()
                        .slideX(begin: 0.05);
                  },
                ),
              ),

            // ─── ADD VIDEO BUTTON ───
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              sliver: SliverToBoxAdapter(
                child: _AddVideoBanner(
                  onTap: () => _showAddVideoDialog(context),
                ).animate(delay: 600.ms).fadeIn(),
              ),
            ),
          ],
        ),
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
            Text('Добавить видео',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'YouTube URL или прямая ссылка (.mp4)',
                prefixIcon: Icon(Icons.link, color: cs.primary),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);

                final isVidApi =
                    text.toLowerCase().contains('vidapi.xyz') ||
                        text.toLowerCase().startsWith('tt');
                final isDirect = text.toLowerCase().endsWith('.mp4') ||
                    text.toLowerCase().endsWith('.m3u8') ||
                    (text.startsWith('http') &&
                        !text.contains('youtu') &&
                        !isVidApi);

                VideoItem? video;
                if (isVidApi) {
                  video = await context
                      .read<VideoProvider>()
                      .importVidApiVideo(text);
                } else if (isDirect) {
                  video = await context
                      .read<VideoProvider>()
                      .importCustomVideo(text);
                } else {
                  video = await context
                      .read<VideoProvider>()
                      .importYouTubeVideo(text);
                }

                if (video != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PlayerScreen(video: video!)),
                  );
                }
              },
              child: const Text('Импортировать и смотреть'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//                      HERO HEADER
// ═══════════════════════════════════════════════════════════════
class _HeroHeader extends StatelessWidget {
  final String greeting;
  final String userName;
  final UserProgress progress;
  const _HeroHeader({
    required this.greeting,
    required this.userName,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer,
              cs.tertiaryContainer.withOpacity(0.7),
            ],
          ),
        ),
        child: Column(
          children: [
            // Top bar: avatar + actions
            Row(
              children: [
                _AvatarCircle(name: userName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting,
                          style: tt.bodyMedium?.copyWith(
                              color: cs.onPrimaryContainer.withOpacity(0.7))),
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleLarge?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                _CircleIconButton(
                  icon: Icons.search_rounded,
                  tooltip: 'Словарь',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FullDictionaryScreen()),
                  ),
                  bg: cs.surface.withOpacity(0.45),
                  fg: cs.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                _CircleIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Уведомления',
                  onTap: () {},
                  bg: cs.surface.withOpacity(0.45),
                  fg: cs.onPrimaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Progress Hero
            Row(
              children: [
                ProgressRing(
                  progress: progress.dailyProgressPercent,
                  size: 96,
                  strokeWidth: 9,
                  color: cs.primary,
                  backgroundColor: cs.primary.withOpacity(0.18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${progress.todayMinutes}',
                        style: tt.headlineSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'мин',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(
                              '${progress.streakDays} дн. подряд',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        progress.dailyProgressPercent >= 1
                            ? 'Цель дня выполнена!'
                            : 'Цель дня · ${progress.dailyGoalMinutes} мин',
                        style: tt.titleMedium?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${progress.totalWordsLearned} слов изучено',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final String name;
  const _AvatarCircle({required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final initials = name.isEmpty
        ? '?'
        : name
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join();

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.tertiary],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: tt.titleMedium?.copyWith(
            color: cs.onPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.bg,
    required this.fg,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: fg, size: 20),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ═══════════════════════════════════════════════════════════════
//                      BENTO STATS GRID
// ═══════════════════════════════════════════════════════════════
class _BentoStatsGrid extends StatelessWidget {
  final UserProgress progress;
  final VocabularyProvider vocab;

  const _BentoStatsGrid({required this.progress, required this.vocab});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final newCount =
        vocab.allWords.where((w) => w.status == 'new').length;
    final learning =
        vocab.allWords.where((w) => w.status == 'learning').length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.bolt_rounded,
                label: 'Сегодня слов',
                value: '${progress.todayWords}',
                color: cs.primary,
                bg: cs.primaryContainer,
                fg: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.history_toggle_off_rounded,
                label: 'К повтору',
                value: '${progress.wordsToReview}',
                color: cs.tertiary,
                bg: cs.tertiaryContainer,
                fg: cs.onTertiaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.school_rounded,
                label: 'Изучено',
                value: '${progress.totalWordsLearned}',
                color: Colors.green,
                bg: Colors.green.withOpacity(0.13),
                fg: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.psychology_rounded,
                label: 'В процессе',
                value: '${learning + newCount}',
                color: cs.secondary,
                bg: cs.secondaryContainer,
                fg: cs.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bg;
  final Color fg;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.bodySmall?.copyWith(color: fg.withOpacity(0.75)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//                      DAILY PLAN CARD
// ═══════════════════════════════════════════════════════════════
class _DailyPlanCard extends StatelessWidget {
  final int wordsToReview;
  const _DailyPlanCard({required this.wordsToReview});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () {
        final vocab = context.read<VocabularyProvider>();
        vocab.preparePractice();
        // Open vocabulary screen by switching tab — simplest: push standalone
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VocabularyScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              cs.primary,
              cs.primary.withOpacity(0.78),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flash_on_rounded,
                          color: cs.onPrimary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'СЕГОДНЯ',
                        style: tt.labelMedium?.copyWith(
                          color: cs.onPrimary.withOpacity(0.85),
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$wordsToReview ${_pluralize(wordsToReview)} к повтору',
                    style: tt.titleLarge?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Закрепи изученное за 5 минут',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onPrimary.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.onPrimary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.play_arrow_rounded,
                  color: cs.onPrimary, size: 32),
            ),
          ],
        ),
      ),
    );
  }

  String _pluralize(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'слово';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'слова';
    }
    return 'слов';
  }
}

// ═══════════════════════════════════════════════════════════════
//                      QUICK ACTIONS ROW
// ═══════════════════════════════════════════════════════════════
class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final items = <_QuickActionItem>[
      _QuickActionItem(
        icon: Icons.fitness_center_rounded,
        label: 'Упражнения',
        color: cs.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExercisesHubScreen()),
        ),
      ),
      _QuickActionItem(
        icon: Icons.menu_book_rounded,
        label: 'Словарь',
        color: cs.tertiary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FullDictionaryScreen()),
        ),
      ),
      _QuickActionItem(
        icon: Icons.school_rounded,
        label: 'Мои слова',
        color: cs.secondary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VocabularyScreen()),
        ),
      ),
      _QuickActionItem(
        icon: Icons.movie_outlined,
        label: 'Фильмы',
        color: Colors.deepOrange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MovieCatalogScreen()),
        ),
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Expanded(child: _QuickActionTile(item: items[i])),
          if (i < items.length - 1) const SizedBox(width: 10),
        ]
      ],
    );
  }
}

class _QuickActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _QuickActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QuickActionItem item;
  const _QuickActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//                      SECTION HEADER
// ═══════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final VoidCallback? onSeeAll;

  const _SectionHeader({
    required this.title,
    this.icon,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Все', style: tt.labelLarge?.copyWith(color: cs.primary)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//                  EMPTY VIDEOS / ADD BANNER
// ═══════════════════════════════════════════════════════════════
class _EmptyVideosCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.video_library_outlined,
                size: 36, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text('Нет видео', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text('Добавьте YouTube-ссылку, чтобы начать обучение',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _AddVideoBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _AddVideoBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: DottedBorder(
        color: cs.primary.withOpacity(0.5),
        radius: 24,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child:
                    Icon(Icons.add_rounded, color: cs.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Добавить своё видео',
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('YouTube-ссылка или прямой .mp4',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Простая dashed-обводка через CustomPaint (без зависимостей).
class DottedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  const DottedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DottedPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DottedPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);

    const dashLen = 6.0;
    const gapLen = 4.0;

    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dashLen).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
