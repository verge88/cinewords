import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class CustomVideoControls extends StatefulWidget {
  final Player player;
  final String title;
  final VoidCallback onSettingsTap;
  final VoidCallback onBackTap;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const CustomVideoControls({
    super.key,
    required this.player,
    required this.title,
    required this.onSettingsTap,
    required this.onBackTap,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  bool _isVisible = true;
  Timer? _hideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  /// Позиция, которую пользователь тянет прямо сейчас. Пока ползунок зажат,
  /// слайдер показывает её, а не приходящую из плеера позицию — иначе
  /// значение дёргается между пальцем и потоком position.
  double? _dragValue;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _startHideTimer();

    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _isPlaying = widget.player.state.playing;

    _subs.add(widget.player.stream.position.listen((pos) {
      if (mounted && _dragValue == null) setState(() => _position = pos);
    }));
    _subs.add(widget.player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    }));
    _subs.add(widget.player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
      if (playing) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
        setState(() => _isVisible = true);
      }
    }));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _toggleVisibility() {
    setState(() => _isVisible = !_isVisible);
    if (_isVisible && _isPlaying) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) setState(() => _isVisible = false);
    });
  }

  void _onInteraction() {
    if (_isVisible) _startHideTimer();
  }

  void _seekBy(int seconds) {
    _onInteraction();
    final target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) {
      widget.player.seek(Duration.zero);
    } else if (_duration > Duration.zero && target > _duration) {
      widget.player.seek(_duration);
    } else {
      widget.player.seek(target);
    }
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleVisibility,
      behavior: HitTestBehavior.translucent,
      child: MouseRegion(
        onHover: (_) => _onInteraction(),
        child: AnimatedOpacity(
          opacity: _isVisible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !_isVisible,
            // Размеры считаются от фактической высоты области видео,
            // а не от флага полноэкранного режима: во врезке 16:9 на
            // телефоне высоты ~260 px, и прежние иконки 48 с кнопкой
            // 80×80 не вмещались вместе с прогресс-баром.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _ControlMetrics.forHeight(constraints.maxHeight);

                return ColoredBox(
                  color: Colors.black38,
                  child: Column(
                    children: [
                      // Заголовок и «назад» нужны только в полноэкранном
                      // режиме: во врезке их дублирует AppBar экрана.
                      if (widget.isFullscreen)
                        _TopBar(
                          title: widget.title,
                          iconSize: metrics.barIcon,
                          onBackTap: widget.onBackTap,
                        )
                      else
                        const SizedBox(height: 4),

                      Expanded(
                        child: Center(
                          child: _CenterControls(
                            metrics: metrics,
                            isPlaying: _isPlaying,
                            onRewind: () => _seekBy(-10),
                            onForward: () => _seekBy(10),
                            onPlayPause: () {
                              _onInteraction();
                              widget.player.playOrPause();
                            },
                          ),
                        ),
                      ),

                      _BottomBar(
                        metrics: metrics,
                        position: _position,
                        duration: _duration,
                        dragValue: _dragValue,
                        isFullscreen: widget.isFullscreen,
                        format: _format,
                        onDragStart: (value) => setState(() => _dragValue = value),
                        onDragUpdate: (value) => setState(() => _dragValue = value),
                        onDragEnd: (value) {
                          widget.player.seek(Duration(milliseconds: value.toInt()));
                          setState(() {
                            _position = Duration(milliseconds: value.toInt());
                            _dragValue = null;
                          });
                          _onInteraction();
                        },
                        onSettingsTap: () {
                          _hideTimer?.cancel();
                          widget.onSettingsTap();
                        },
                        onToggleFullscreen: widget.onToggleFullscreen,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Набор размеров, подобранный под доступную высоту области видео.
class _ControlMetrics {
  const _ControlMetrics({
    required this.playButton,
    required this.playIcon,
    required this.seekIcon,
    required this.barIcon,
    required this.fontSize,
    required this.trackHeight,
    required this.thumbRadius,
  });

  final double playButton;
  final double playIcon;
  final double seekIcon;
  final double barIcon;
  final double fontSize;
  final double trackHeight;
  final double thumbRadius;

  factory _ControlMetrics.forHeight(double height) {
    if (height < 200) {
      return const _ControlMetrics(
        playButton: 42,
        playIcon: 24,
        seekIcon: 22,
        barIcon: 17,
        fontSize: 10,
        trackHeight: 2,
        thumbRadius: 5,
      );
    }
    if (height < 300) {
      return const _ControlMetrics(
        playButton: 52,
        playIcon: 30,
        seekIcon: 26,
        barIcon: 19,
        fontSize: 11,
        trackHeight: 3,
        thumbRadius: 6,
      );
    }
    return const _ControlMetrics(
      playButton: 68,
      playIcon: 38,
      seekIcon: 32,
      barIcon: 22,
      fontSize: 12,
      trackHeight: 4,
      thumbRadius: 7,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.iconSize,
    required this.onBackTap,
  });

  final String title;
  final double iconSize;
  final VoidCallback onBackTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              iconSize: iconSize,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: onBackTap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.metrics,
    required this.isPlaying,
    required this.onRewind,
    required this.onForward,
    required this.onPlayPause,
  });

  final _ControlMetrics metrics;
  final bool isPlaying;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onRewind,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.replay_10_rounded,
            color: Colors.white,
            size: metrics.seekIcon,
          ),
        ),
        SizedBox(width: metrics.playButton * 0.35),
        SizedBox(
          width: metrics.playButton,
          height: metrics.playButton,
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPlayPause,
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: metrics.playIcon,
                color: Colors.black87,
              ),
            ),
          ),
        ),
        SizedBox(width: metrics.playButton * 0.35),
        IconButton(
          onPressed: onForward,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.forward_10_rounded,
            color: Colors.white,
            size: metrics.seekIcon,
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.metrics,
    required this.position,
    required this.duration,
    required this.dragValue,
    required this.isFullscreen,
    required this.format,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onSettingsTap,
    required this.onToggleFullscreen,
  });

  final _ControlMetrics metrics;
  final Duration position;
  final Duration duration;
  final double? dragValue;
  final bool isFullscreen;
  final String Function(Duration) format;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onSettingsTap;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final value =
        (dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);
    final labelStyle = TextStyle(color: Colors.white, fontSize: metrics.fontSize);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        // Прогресс, время и кнопки собраны в одну строку: два ряда,
        // как было раньше, не вмещались во врезку без обрезки.
        child: Row(
          children: [
            Text(format(position), style: labelStyle),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: metrics.trackHeight,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: metrics.thumbRadius,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: metrics.thumbRadius * 2,
                  ),
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Theme.of(context).colorScheme.primary,
                ),
                child: Slider(
                  value: value,
                  max: maxMs,
                  onChangeStart: onDragStart,
                  onChanged: onDragUpdate,
                  onChangeEnd: onDragEnd,
                ),
              ),
            ),
            Text(format(duration), style: labelStyle),
            const SizedBox(width: 4),
            IconButton(
              iconSize: metrics.barIcon,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              onPressed: onSettingsTap,
            ),
            const SizedBox(width: 12),
            IconButton(
              iconSize: metrics.barIcon,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
              ),
              onPressed: onToggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}
