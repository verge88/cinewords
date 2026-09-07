import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../models/user_progress.dart';
import '../../models/video_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/video_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/video_card.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/favorites_screen.dart';
import '../catalog/movie_catalog_screen.dart';
import '../dictionary/full_dictionary_screen.dart';
import '../exercises/exercises_hub_screen.dart';
import '../player/player_screen.dart';
import '../profile/profile_screen.dart';
import '../vocabulary/vocabulary_screen.dart';

/// Единая метрика отступов экрана.
const double _gutter = 20;
const double _railHeight = 262;
const double _railItemWidth = 272;

/// Фирменные акценты. Не зависят от dynamic color, поэтому одинаковы
/// на всех устройствах и в обеих темах.
abstract final class _Accent {
  static const violet = Color(0xFF7C6CFF);
  static const teal = Color(0xFF00BFA5);
  static const amber = Color(0xFFFFB74D);
  static const coral = Color(0xFFFF6B4A);
}

enum HomeTab { home, videos, movies, words, profile }

/// Доступ к навигации по табам из любого места главного экрана —
/// чтобы не пушить второй экземпляр экрана, который уже есть в таббаре.
class HomeScope extends InheritedWidget {
  const HomeScope({
    super.key,
    required this.openTab,
    required this.reload,
    required super.child,
  });

  final ValueChanged<HomeTab> openTab;
  final Future<void> Function() reload;

  static HomeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HomeScope>();
    assert(scope != null, 'HomeScope не найден выше в дереве');
    return scope!;
  }

  @override
  bool updateShouldNotify(HomeScope oldWidget) => false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Прогресс живёт в notifier, а не в state: так его обновление
  /// перестраивает только шапку, а не весь таб со списками.
  final ValueNotifier<UserProgress?> _progress = ValueNotifier(null);

  HomeTab _tab = HomeTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHomeData());
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// Грузим только то, что нужно главной: подборки для полок,
  /// словарь для плана дня и прогресс для шапки.
  /// Остальные табы поднимают свои данные сами при первом открытии.
  Future<void> _loadHomeData() async {
    if (!mounted) return;
    final videos = context.read<VideoProvider>();
    final vocabulary = context.read<VocabularyProvider>();

    await Future.wait<void>([
      videos.loadFeatured(),
      videos.loadTrending(),
      vocabulary.loadAll(),
      _loadProgress(),
    ]);
  }

  Future<void> _loadProgress() async {
    final progress = await SupabaseService.getUserProgress();
    if (mounted) _progress.value = progress;
  }

  void _openTab(HomeTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return HomeScope(
      openTab: _openTab,
      reload: _loadHomeData,
      child: Scaffold(
        body: _LazyIndexedStack(
          index: _tab.index,
          builders: [
            (_) => _HomeFeed(progress: _progress),
            (_) => const CatalogScreen(),
            (_) => const MovieCatalogScreen(),
            (_) => const VocabularyScreen(),
            (_) => const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab.index,
          onDestinationSelected: (i) => _openTab(HomeTab.values[i]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Видео',
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie_rounded),
              label: 'Фильмы',
            ),
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school_rounded),
              label: 'Слова',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}

/// IndexedStack, который строит страницу только после первого перехода на неё
/// и после этого сохраняет её состояние.
class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({required this.index, required this.builders});

  final int index;
  final List<WidgetBuilder> builders;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final List<bool> _activated =
      List<bool>.filled(widget.builders.length, false);

  @override
  Widget build(BuildContext context) {
    _activated[widget.index] = true;

    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_activated[i])
            widget.builders[i](context)
          else
            const SizedBox.shrink(),
      ],
    );
  }
}

/// Лента главного экрана.
class _HomeFeed extends StatelessWidget {
  const _HomeFeed({required this.progress});

  final ValueListenable<UserProgress?> progress;

  @override
  Widget build(BuildContext context) {
    final scope = HomeScope.of(context);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: scope.reload,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _HeroSection(progress: progress).entrance(0),
            ),
            SliverToBoxAdapter(
              child: const _QuickAccessGrid().entrance(1),
            ),
            SliverToBoxAdapter(
              child: _DailyPlanSection(progress: progress).entrance(2),
            ),
            SliverToBoxAdapter(
              child: const _ContinueSection().entrance(3),
            ),
            SliverToBoxAdapter(
              child: const _FeaturedSection().entrance(4),
            ),
            SliverToBoxAdapter(
              child: const _TrendingSection().entrance(5),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 28),
                child: _AddVideoBanner(
                  onTap: () => _showAddVideoSheet(context),
                ).entrance(6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна выдержанная анимация появления на секцию — без покадрового
/// стаггера на каждом элементе списков.
extension _Entrance on Widget {
  Widget entrance(int order) => animate(
        delay: Duration(milliseconds: 40 * order),
      )
          .fadeIn(duration: 260.ms, curve: Curves.easeOut)
          .slideY(begin: 0.03, end: 0, curve: Curves.easeOutCubic);
}

// ── Шапка ───────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.progress});

  final ValueListenable<UserProgress?> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProgress?>(
      valueListenable: progress,
      builder: (context, value, _) => _HeroCard(
        progress: value ?? const UserProgress(),
        isLoading: value == null,
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.progress, required this.isLoading});

  final UserProgress progress;
  final bool isLoading;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Доброй ночи';
    if (hour < 12) return 'Доброе утро';
    if (hour < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _HomePalette.of(context);
    final userName = context.select<AuthProvider, String>((a) => a.displayName);
    final scope = HomeScope.of(context);

    final goalReached = progress.dailyProgressPercent >= 1;
    final left =
        (progress.dailyGoalMinutes - progress.todayMinutes).clamp(0, 9999);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.heroSurface, palette.heroSurfaceAlt],
          ),
          border: Border.all(color: palette.heroBorder),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _Avatar(
                  name: userName,
                  onTap: () => scope.openTab(HomeTab.profile),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: palette.heroForegroundMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userName.isEmpty ? 'Гость' : userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: palette.heroForeground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _HeroAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Словарь',
                  palette: palette,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FullDictionaryScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeroAction(
                  icon: Icons.add_rounded,
                  tooltip: 'Добавить видео',
                  palette: palette,
                  onTap: () => _showAddVideoSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ProgressRing(
                  progress: progress.dailyProgressPercent,
                  size: 92,
                  strokeWidth: 8,
                  color: palette.accent,
                  backgroundColor: palette.ringTrack,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${progress.todayMinutes}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: palette.heroForeground,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'мин',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: palette.heroForegroundMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goalReached
                            ? 'Цель дня выполнена'
                            : 'Цель дня · ${progress.dailyGoalMinutes} мин',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: palette.heroForeground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _goalHint(goalReached, left),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: palette.heroForegroundMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(height: 1, color: palette.heroBorder),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: _Accent.coral,
                    value: '${progress.streakDays}',
                    label: _plural(
                      progress.streakDays,
                      'день подряд',
                      'дня подряд',
                      'дней подряд',
                    ),
                    palette: palette,
                    muted: progress.streakDays == 0,
                  ),
                ),
                Container(width: 1, height: 32, color: palette.heroBorder),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: _Accent.teal,
                    value: isLoading ? '—' : '${progress.totalWordsLearned}',
                    label: _plural(
                      progress.totalWordsLearned,
                      'слово изучено',
                      'слова изучено',
                      'слов изучено',
                    ),
                    palette: palette,
                    muted: progress.totalWordsLearned == 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _goalHint(bool goalReached, int left) {
    if (goalReached) return 'Отличный результат, так держать';
    if (progress.todayMinutes == 0) return 'Начните с короткого видео';
    return 'Осталось $left ${_plural(left, 'минута', 'минуты', 'минут')}';
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.palette,
    this.muted = false,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final _HomePalette palette;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 18,
          color: muted ? palette.heroForegroundMuted : iconColor,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: palette.heroForeground,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: palette.heroForegroundMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Профиль',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_Accent.violet, _Accent.teal],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final _HomePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.heroLayer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: palette.heroForeground),
          ),
        ),
      ),
    );
  }
}

// ── Быстрый доступ ──────────────────────────────────────────────────────

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid();

  @override
  Widget build(BuildContext context) {
    final inProgress = context.select<VocabularyProvider, int>(
      (v) => v.newCount + v.learningCount,
    );
    final scope = HomeScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 20),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _QuickAccessTile(
            icon: Icons.fitness_center_rounded,
            title: 'Упражнения',
            subtitle: 'Тренажёры',
            color: _Accent.violet,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExercisesHubScreen()),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.menu_book_rounded,
            title: 'Словарь',
            subtitle: 'Поиск и перевод',
            color: _Accent.teal,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FullDictionaryScreen()),
            ),
          ),
          _QuickAccessTile(
            icon: Icons.school_rounded,
            title: 'Мои слова',
            subtitle:
                inProgress > 0 ? '$inProgress в изучении' : 'Повторение',
            color: _Accent.amber,
            onTap: () => scope.openTab(HomeTab.words),
          ),
          _QuickAccessTile(
            icon: Icons.movie_outlined,
            title: 'Фильмы',
            subtitle: 'Каталог',
            color: _Accent.coral,
            onTap: () => scope.openTab(HomeTab.movies),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _HomePalette.of(context);

    return Material(
      color: palette.cardSurface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 16,
                    color: palette.hint,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── План дня ────────────────────────────────────────────────────────────

class _DailyPlanSection extends StatelessWidget {
  const _DailyPlanSection({required this.progress});

  final ValueListenable<UserProgress?> progress;

  @override
  Widget build(BuildContext context) {
    final queueLength =
        context.select<VocabularyProvider, int>((v) => v.reviewQueue.length);

    return ValueListenableBuilder<UserProgress?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final fromProgress = value?.wordsToReview ?? 0;
        final words = fromProgress > 0 ? fromProgress : queueLength;
        if (words == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 24),
          child: _DailyPlanCard(wordsToReview: words),
        );
      },
    );
  }
}

class _DailyPlanCard extends StatelessWidget {
  const _DailyPlanCard({required this.wordsToReview});

  final int wordsToReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      color: cs.primary,
      child: InkWell(
        onTap: () {
          context.read<VocabularyProvider>().preparePractice();
          HomeScope.of(context).openTab(HomeTab.words);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [cs.primary, Color.alphaBlend(
                cs.tertiary.withValues(alpha: 0.35),
                cs.primary,
              )],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ПЛАН НА СЕГОДНЯ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimary.withValues(alpha: 0.8),
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$wordsToReview '
                      '${_plural(wordsToReview, 'слово', 'слова', 'слов')} '
                      'к повторению',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Займёт около 5 минут',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: cs.onPrimary,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Полки с видео ───────────────────────────────────────────────────────

class _ContinueSection extends StatelessWidget {
  const _ContinueSection();

  @override
  Widget build(BuildContext context) {
    final favorites =
        context.select<VideoProvider, List<VideoItem>>((v) => v.favoriteVideos);
    if (favorites.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        _SectionHeader(
          title: 'Продолжить',
          icon: Icons.play_circle_outline_rounded,
          actionLabel: 'Все',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FavoritesScreen()),
          ),
        ),
        _VideoRail(videos: favorites),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _FeaturedSection extends StatelessWidget {
  const _FeaturedSection();

  @override
  Widget build(BuildContext context) {
    final featured =
        context.select<VideoProvider, List<VideoItem>>((v) => v.featuredVideos);
    final isLoading = context.select<VideoProvider, bool>((v) => v.isLoading);
    final scope = HomeScope.of(context);

    return Column(
      children: [
        _SectionHeader(
          title: 'Рекомендуем',
          icon: Icons.auto_awesome_rounded,
          actionLabel: featured.isEmpty ? null : 'Все',
          onAction: featured.isEmpty ? null : () => scope.openTab(HomeTab.videos),
        ),
        if (featured.isEmpty && isLoading)
          const _RailSkeleton()
        else if (featured.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: _EmptyLibraryCard(
              onAdd: () => _showAddVideoSheet(context),
            ),
          )
        else
          _VideoRail(videos: featured),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _TrendingSection extends StatelessWidget {
  const _TrendingSection();

  @override
  Widget build(BuildContext context) {
    final trending =
        context.select<VideoProvider, List<VideoItem>>((v) => v.trendingVideos);
    final isLoading = context.select<VideoProvider, bool>((v) => v.isLoading);
    final scope = HomeScope.of(context);

    if (trending.isEmpty && isLoading) {
      return Column(
        children: const [
          _SectionHeader(title: 'В тренде', icon: Icons.trending_up_rounded),
          _ListSkeleton(),
          SizedBox(height: 20),
        ],
      );
    }
    if (trending.isEmpty) return const SizedBox.shrink();

    final items = trending.take(5).toList(growable: false);

    return Column(
      children: [
        _SectionHeader(
          title: 'В тренде',
          icon: Icons.trending_up_rounded,
          actionLabel: 'Все',
          onAction: () => scope.openTab(HomeTab.videos),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: Column(
            children: [
              for (final video in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VideoCard(
                    video: video,
                    onTap: () => _openPlayer(context, video),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _VideoRail extends StatelessWidget {
  const _VideoRail({required this.videos});

  final List<VideoItem> videos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final video = videos[index];
          return SizedBox(
            width: _railItemWidth,
            child: VideoCard(
              video: video,
              onTap: () => _openPlayer(context, video),
            ),
          );
        },
      ),
    );
  }
}

void _openPlayer(BuildContext context, VideoItem video) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PlayerScreen(video: video)),
  );
}

// ── Заголовок секции ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _HomePalette.of(context);
    final hasAction = actionLabel != null && onAction != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter, 0, hasAction ? 10 : _gutter, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: palette.iconChip,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: palette.iconChipForeground),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (hasAction)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

// ── Пустые состояния и скелетоны ────────────────────────────────────────

class _EmptyLibraryCard extends StatelessWidget {
  const _EmptyLibraryCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _HomePalette.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _Accent.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.video_library_outlined,
              size: 26,
              color: _Accent.violet,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Здесь появятся подборки',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Добавьте первое видео — приложение подберёт похожие '
            'и соберёт из них словарь',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.onSurfaceMuted),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Добавить видео'),
          ),
        ],
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => const _SkeletonBox(
          width: _railItemWidth,
          height: _railHeight,
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter),
      child: Column(
        children: [
          _SkeletonBox(height: 96),
          SizedBox(height: 12),
          _SkeletonBox(height: 96),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = _HomePalette.of(context);

    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.cardBorder),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 700.ms, begin: 0.45);
  }
}

// ── CTA «Добавить видео» ────────────────────────────────────────────────

class _AddVideoBanner extends StatelessWidget {
  const _AddVideoBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final palette = _HomePalette.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: cs.primary.withValues(alpha: 0.45),
          radius: 22,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.add_rounded, color: cs.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Своё видео',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ссылка на YouTube или прямой .mp4 / .m3u8',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: palette.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.hint),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );

    const dash = 6.0;
    const gap = 5.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ── Импорт видео ────────────────────────────────────────────────────────

enum _VideoSource { youtube, direct, vidApi }

_VideoSource _detectSource(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.contains('vidapi.xyz') || value.startsWith('tt')) {
    return _VideoSource.vidApi;
  }
  if (value.contains('youtube.com') || value.contains('youtu.be')) {
    return _VideoSource.youtube;
  }
  if (value.endsWith('.mp4') ||
      value.endsWith('.m3u8') ||
      value.startsWith('http')) {
    return _VideoSource.direct;
  }
  return _VideoSource.youtube;
}

Future<void> _showAddVideoSheet(BuildContext context) async {
  final video = await showModalBottomSheet<VideoItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _AddVideoSheet(),
  );

  if (video == null || !context.mounted) return;
  _openPlayer(context, video);
}

class _AddVideoSheet extends StatefulWidget {
  const _AddVideoSheet();

  @override
  State<_AddVideoSheet> createState() => _AddVideoSheetState();
}

class _AddVideoSheetState extends State<_AddVideoSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Вставьте ссылку на видео');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    final videos = context.read<VideoProvider>();
    VideoItem? video;
    try {
      video = switch (_detectSource(raw)) {
        _VideoSource.vidApi => await videos.importVidApiVideo(raw),
        _VideoSource.direct => await videos.importCustomVideo(raw),
        _VideoSource.youtube => await videos.importYouTubeVideo(raw),
      };
    } catch (_) {
      video = null;
    }

    if (!mounted) return;

    if (video == null) {
      setState(() {
        _isBusy = false;
        _error = 'Не удалось загрузить видео. Проверьте ссылку.';
      });
      return;
    }

    Navigator.of(context).pop(video);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Добавить видео',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Поддерживаются ссылки YouTube и прямые файлы .mp4 / .m3u8',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isBusy,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Ссылка',
              hintText: 'https://…',
              errorText: _error,
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _isBusy ? null : _submit,
            child: _isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Импортировать и смотреть'),
          ),
        ],
      ),
    );
  }
}

// ── Палитра и утилиты ───────────────────────────────────────────────────

/// Все решения «светлая / тёмная тема» собраны в одном месте,
/// чтобы виджеты не разъезжались по стилю.
@immutable
class _HomePalette {
  const _HomePalette({
    required this.accent,
    required this.heroSurface,
    required this.heroSurfaceAlt,
    required this.heroBorder,
    required this.heroLayer,
    required this.heroForeground,
    required this.heroForegroundMuted,
    required this.ringTrack,
    required this.cardSurface,
    required this.cardBorder,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.hint,
    required this.iconChip,
    required this.iconChipForeground,
  });

  final Color accent;
  final Color heroSurface;
  final Color heroSurfaceAlt;
  final Color heroBorder;
  final Color heroLayer;
  final Color heroForeground;
  final Color heroForegroundMuted;
  final Color ringTrack;
  final Color cardSurface;
  final Color cardBorder;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color hint;
  final Color iconChip;
  final Color iconChipForeground;

  factory _HomePalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (theme.brightness == Brightness.dark) {
      return _HomePalette(
        accent: _Accent.violet,
        heroSurface: const Color(0xFF1C1B22),
        heroSurfaceAlt: const Color(0xFF141318),
        heroBorder: Colors.white.withValues(alpha: 0.08),
        heroLayer: Colors.white.withValues(alpha: 0.10),
        heroForeground: Colors.white,
        heroForegroundMuted: Colors.white.withValues(alpha: 0.62),
        ringTrack: Colors.white.withValues(alpha: 0.12),
        cardSurface: const Color(0xFF16151C),
        cardBorder: Colors.white.withValues(alpha: 0.07),
        onSurface: Colors.white,
        onSurfaceMuted: Colors.white.withValues(alpha: 0.60),
        hint: Colors.white.withValues(alpha: 0.32),
        iconChip: Colors.white.withValues(alpha: 0.10),
        iconChipForeground: Colors.white,
      );
    }

    return _HomePalette(
      accent: cs.primary,
      heroSurface: cs.primaryContainer,
      heroSurfaceAlt: Color.alphaBlend(
        cs.tertiaryContainer.withValues(alpha: 0.55),
        cs.primaryContainer,
      ),
      heroBorder: cs.onPrimaryContainer.withValues(alpha: 0.10),
      heroLayer: cs.surface.withValues(alpha: 0.55),
      heroForeground: cs.onPrimaryContainer,
      heroForegroundMuted: cs.onPrimaryContainer.withValues(alpha: 0.70),
      ringTrack: cs.primary.withValues(alpha: 0.16),
      cardSurface: cs.surfaceContainerLow,
      cardBorder: cs.outlineVariant.withValues(alpha: 0.40),
      onSurface: cs.onSurface,
      onSurfaceMuted: cs.onSurfaceVariant,
      hint: cs.onSurfaceVariant.withValues(alpha: 0.55),
      iconChip: cs.primaryContainer,
      iconChipForeground: cs.onPrimaryContainer,
    );
  }
}

/// Русская плюрализация: 1 слово, 2 слова, 5 слов.
String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}
