import 'package:cinewords/config/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/user_progress.dart';
import '../../widgets/progress_ring.dart';
import '../../config/supabase_config.dart'; 

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProgress _progress = const UserProgress();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final p = await SupabaseService.getUserProgress();
      if (mounted) setState(() { _progress = p; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text('Profile', style: tt.headlineMedium),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ─── User Card ───
                Card(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: cs.primary,
                          child: Text(
                            auth.displayName.isNotEmpty
                                ? auth.displayName[0].toUpperCase()
                                : '?',
                            style: tt.headlineMedium?.copyWith(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.displayName,
                                style: tt.titleLarge?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                auth.user?.email ?? '',
                                style: tt.bodyMedium?.copyWith(
                                  color: cs.onPrimaryContainer.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  auth.profile?['english_level']
                                          ?.toString()
                                          .replaceAll('_', ' ')
                                          .toUpperCase() ??
                                      'INTERMEDIATE',
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn().slideY(begin: 0.1),

                const SizedBox(height: 24),

                // ─── Statistics Grid ───
                Text('Statistics', style: tt.titleLarge)
                    .animate(delay: 100.ms)
                    .fadeIn(),
                const SizedBox(height: 12),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                    children: [
                      _StatCard(
                        icon: Icons.local_fire_department_rounded,
                        value: '${_progress.streakDays}',
                        label: 'Day Streak',
                        color: Colors.orange,
                        cs: cs,
                      ),
                      _StatCard(
                        icon: Icons.book_rounded,
                        value: '${_progress.totalWordsLearned}',
                        label: 'Words Learned',
                        color: cs.primary,
                        cs: cs,
                      ),
                      _StatCard(
                        icon: Icons.play_circle_rounded,
                        value: '${_progress.totalWatchMinutes}',
                        label: 'Minutes Watched',
                        color: cs.secondary,
                        cs: cs,
                      ),
                      _StatCard(
                        icon: Icons.replay_rounded,
                        value: '${_progress.wordsToReview}',
                        label: 'To Review',
                        color: cs.tertiary,
                        cs: cs,
                      ),
                    ],
                  ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),

                const SizedBox(height: 24),

                // ─── Daily Goal ───
                Text('Daily Goal', style: tt.titleLarge)
                    .animate(delay: 300.ms)
                    .fadeIn(),
                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        ProgressRing(
                          progress: _progress.dailyProgressPercent,
                          size: 72,
                          strokeWidth: 7,
                          color: cs.primary,
                          backgroundColor: cs.primary.withOpacity(0.12),
                          child: Text(
                            '${(_progress.dailyProgressPercent * 100).round()}%',
                            style: tt.labelLarge?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_progress.todayMinutes} / ${_progress.dailyGoalMinutes} min',
                                style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_progress.todayWords} words added today',
                                style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant),
                              ),
                              Text(
                                '${_progress.todayReviewed} words reviewed today',
                                style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate(delay: 350.ms).fadeIn(),

                const SizedBox(height: 32),

                // ─── Settings ───
                Text('Settings', style: tt.titleLarge)
                    .animate(delay: 400.ms)
                    .fadeIn(),
                const SizedBox(height: 12),

                _SettingsTile(
                  icon: Icons.translate_rounded,
                  title: 'Native Language',
                  subtitle: 'Russian',
                  onTap: () {},
                ),
                _SettingsTile(
                  icon: Icons.timer_outlined,
                  title: 'Daily Goal',
                  subtitle: '${_progress.dailyGoalMinutes} minutes',
                  onTap: () => _showGoalDialog(context),
                ),
                _SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Theme',
                  subtitle: 'System',
                  onTap: () {},
                ),

                const SizedBox(height: 16),

                // Sign out
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Sign Out'),
                        content:
                            const Text('Are you sure you want to sign out?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await auth.signOut();
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withOpacity(0.5)),
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ).animate(delay: 500.ms).fadeIn(),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalDialog(BuildContext context) {
    int goal = _progress.dailyGoalMinutes;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Daily Goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$goal minutes per day',
                  style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Slider(
                value: goal.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '$goal min',
                onChanged: (v) =>
                    setDialogState(() => goal = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await SupabaseConfig.supabase
                    .from('profiles')
                    .update({'daily_goal_minutes': goal}).eq(
                        'id', SupabaseConfig.userId!);
                _loadProgress();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final ColorScheme cs;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
