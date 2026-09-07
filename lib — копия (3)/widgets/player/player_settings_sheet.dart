import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';

class PlayerSettingsSheet extends StatefulWidget {
  final Future<void> Function(String? quality)? onQualityChanged;

  const PlayerSettingsSheet({super.key, this.onQualityChanged});

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pp = context.watch<PlayerProvider>();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * (isLandscape ? 0.8 : 0.6),
        ),
        padding: EdgeInsets.only(
          top: 8,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + (isLandscape ? 8 : 24),
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle/Indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Tabs
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _TabButton(
                    icon: Icons.high_quality_rounded,
                    label: 'Quality',
                    isActive: _tabIndex == 0,
                    onTap: () => setState(() => _tabIndex = 0),
                  ),
                  _TabButton(
                    icon: Icons.speed_rounded,
                    label: 'Speed',
                    isActive: _tabIndex == 1,
                    onTap: () => setState(() => _tabIndex = 1),
                  ),
                  _TabButton(
                    icon: Icons.subtitles_rounded,
                    label: 'Subtitles',
                    isActive: _tabIndex == 2,
                    onTap: () => setState(() => _tabIndex = 2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Content
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildContent(pp),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(PlayerProvider pp) {
    switch (_tabIndex) {
      case 0:
        return _QualityTab(pp: pp, onQualityChanged: widget.onQualityChanged);
      case 1:
        return _SpeedTab(pp: pp);
      case 2:
        return _SubtitlesTab(pp: pp);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isActive ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _QualityTab extends StatelessWidget {
  final PlayerProvider pp;
  final Future<void> Function(String? quality)? onQualityChanged;
  
  const _QualityTab({required this.pp, this.onQualityChanged});

  @override
  Widget build(BuildContext context) {
    final qualities = [null, ...pp.availableQualities]; // null is Auto
    
    return Column(
      key: const ValueKey('quality'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: qualities.map((q) {
        return RadioListTile<String?>(
          value: q,
          groupValue: pp.selectedQuality,
          title: Text(q == null ? 'Auto (Highest Bitrate)' : q),
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: (val) {
            onQualityChanged?.call(val);
            Navigator.pop(context); // Close sheet
          },
        );
      }).toList(),
    );
  }
}

class _SpeedTab extends StatelessWidget {
  final PlayerProvider pp;
  
  const _SpeedTab({required this.pp});

  @override
  Widget build(BuildContext context) {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    
    return Padding(
      key: const ValueKey('speed'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: speeds.map((s) {
          final isSelected = pp.playbackSpeed == s;
          return ChoiceChip(
            label: Text('${s}x'),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                pp.setPlaybackSpeed(s);
                // Player speed needs to be set from player instance, doing it in PlayerScreen
              }
            },
          );
        }).toList(),
      ),
    );
  }
}

class _SubtitlesTab extends StatelessWidget {
  final PlayerProvider pp;
  
  const _SubtitlesTab({required this.pp});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('subtitles'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Show Subtitles'),
          value: pp.onVideoSubtitlesEnabled,
          onChanged: (_) => pp.toggleOnVideoSubtitles(),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text('Size'),
        ),
        Slider(
          value: pp.subtitleScale,
          min: 0.5,
          max: 2.0,
          divisions: 6,
          label: '${pp.subtitleScale}x',
          onChanged: (v) => pp.setSubtitleScale(v),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text('Position (Height)'),
        ),
        Slider(
          value: pp.subtitleBottomPadding,
          min: 20,
          max: 300,
          onChanged: (v) => pp.setSubtitleBottomPadding(v),
        ),
      ],
    );
  }
}
