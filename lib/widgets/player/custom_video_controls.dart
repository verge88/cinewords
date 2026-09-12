import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'quality_menu.dart';

/// Оверлей управления плеером.
///
/// Разметка: «назад» + заголовок сверху, −10/play/+10 по центру, снизу —
/// время, прогресс и ряд кнопок (play · HQ · CC · настройки · поворот).
///
/// Жесты (работают и при скрытом интерфейсе):
///   • одиночный тап — показать/скрыть интерфейс;
///   • двойной тап слева/справа — перемотка на [seekStep] (накапливается);
///   • двойной тап по центру — play/pause;
///   • пинч двумя пальцами — масштаб видео (через [onVideoScaleChanged]).
///
/// О видимости интерфейса сообщает [onVisibilityChanged] — это нужно, чтобы
/// субтитры поднимались над контролами и опускались обратно.
class CustomVideoControls extends StatefulWidget {
  const CustomVideoControls({
    super.key,
    required this.player,
    required this.title,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.onSettingsTap,
    required this.onBackTap,
    this.qualities = const <String>[],
    this.selectedQuality,
    this.onQualityChanged,
    this.isChangingQuality = false,
    this.subtitlesEnabled = true,
    this.onToggleSubtitles,
    this.videoScale = 1.0,
    this.onVideoScaleChanged,
    this.onVideoScaleReset,
    this.onVisibilityChanged,
    this.seekStep = const Duration(seconds: 10),
    this.minScale = 1.0,
    this.maxScale = 3.0,
  });

  final Player player;
  final String title;

  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onSettingsTap;
  final VoidCallback onBackTap;

  /// Доступные разрешения и текущее (null == авто).
  final List<String> qualities;
  final String? selectedQuality;
  final ValueChanged<String?>? onQualityChanged;
  final bool isChangingQuality;

  final bool subtitlesEnabled;
  final VoidCallback? onToggleSubtitles;

  final double videoScale;
  final ValueChanged<double>? onVideoScaleChanged;
  final VoidCallback? onVideoScaleReset;

  final ValueChanged<bool>? onVisibilityChanged;

  final Duration seekStep;
  final double minScale;
  final double maxScale;

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

class _CustomVideoControlsState extends State<CustomVideoControls> {
  static const Duration _autoHide = Duration(seconds: 4);

  bool _isVisible = true;
  Timer? _hideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  /// Позиция, которую пользователь тянет прямо сейчас. Пока ползунок зажат,
  /// слайдер показывает её, а не приходящую из плеера позицию.
  double? _dragValue;

  bool _qualityOpen = false;

  // ── двойной тап ──
  Offset _lastTapDown = Offset.zero;
  int _seekAccumSec = 0;
  bool _seekForward = true;
  Timer? _seekBadgeTimer;

  // ── пинч ──
  bool _zooming = false;
  double _scaleAtGestureStart = 1.0;
  bool _zoomBadgeVisible = false;
  Timer? _zoomBadgeTimer;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();

    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _buffered = widget.player.state.buffer;
    _isPlaying = widget.player.state.playing;
    _isBuffering = widget.player.state.buffering;

    _startHideTimer();

    // Провайдер нельзя уведомлять во время первого build — только после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisibilityChanged?.call(_isVisible);
    });

    _subs.add(widget.player.stream.position.listen((pos) {
      if (mounted && _dragValue == null) setState(() => _position = pos);
    }));
    _subs.add(widget.player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    }));
    _subs.add(widget.player.stream.buffer.listen((buf) {
      if (mounted) setState(() => _buffered = buf);
    }));
    _subs.add(widget.player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    }));
    _subs.add(widget.player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
      if (playing) {
        _startHideTimer();
      } else {
        // На паузе интерфейс не прячем.
        _hideTimer?.cancel();
        _setVisible(true);
      }
    }));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekBadgeTimer?.cancel();
    _zoomBadgeTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  // ─────────────────────────── видимость интерфейса ──────────────────────────

  void _setVisible(bool value) {
    if (_isVisible == value) return;
    setState(() => _isVisible = value);
    widget.onVisibilityChanged?.call(value);
    if (!value) _qualityOpen = false;
  }

  void _toggleVisibility() {
    if (_qualityOpen) {
      setState(() => _qualityOpen = false);
      _startHideTimer();
      return;
    }
    _setVisible(!_isVisible);
    if (_isVisible && _isPlaying) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHide, () {
      if (!mounted || !_isPlaying || _qualityOpen) return;
      _setVisible(false);
    });
  }

  void _onInteraction() {
    if (_isVisible) _startHideTimer();
  }

  // ──────────────────────────────── перемотка ───────────────────────────────

  void _seekBy(Duration delta) {
    final current = widget.player.state.position;
    final total = widget.player.state.duration;
    final target = current + delta;

    if (target < Duration.zero) {
      widget.player.seek(Duration.zero);
    } else if (total > Duration.zero && target > total) {
      widget.player.seek(total);
    } else {
      widget.player.seek(target);
    }
  }

  void _handleDoubleTap(double width) {
    final zone = width / 3;
    final x = _lastTapDown.dx;

    if (x < zone) {
      _accumulateSeek(forward: false);
    } else if (x > width - zone) {
      _accumulateSeek(forward: true);
    } else {
      widget.player.playOrPause();
      _onInteraction();
    }
  }

  void _accumulateSeek({required bool forward}) {
    final step = widget.seekStep.inSeconds;

    // Серия быстрых двойных тапов в одну сторону суммируется: 10 → 20 → 30.
    final continuing = (_seekBadgeTimer?.isActive ?? false) &&
        _seekForward == forward &&
        _seekAccumSec > 0;

    setState(() {
      _seekForward = forward;
      _seekAccumSec = continuing ? _seekAccumSec + step : step;
    });

    _seekBy(Duration(seconds: forward ? step : -step));
    _onInteraction();

    _seekBadgeTimer?.cancel();
    _seekBadgeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _seekAccumSec = 0);
    });
  }

  // ──────────────────────────────── масштаб ─────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount < 2) return;
    _zooming = true;
    _scaleAtGestureStart = widget.videoScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_zooming || d.pointerCount < 2) return;

    final next = (_scaleAtGestureStart * d.scale)
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();

    widget.onVideoScaleChanged?.call(next);
    _flashZoomBadge();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (!_zooming) return;
    _zooming = false;

    // Небольшой «магнит» к 100%.
    if (widget.videoScale < widget.minScale + 0.06) {
      widget.onVideoScaleReset?.call();
    }
    _flashZoomBadge();
  }

  void _flashZoomBadge() {
    if (!_zoomBadgeVisible) setState(() => _zoomBadgeVisible = true);
    _zoomBadgeTimer?.cancel();
    _zoomBadgeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _zoomBadgeVisible = false);
    });
  }

  // ───────────────────────────────── прочее ─────────────────────────────────

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  String get _qualityLabel {
    final q = widget.selectedQuality;
    if (q == null || q.isEmpty) return 'HQ';
    return q;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _ControlMetrics.forSize(constraints.biggest);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Слой жестов: живёт под интерфейсом и работает всегда.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVisibility,
              onDoubleTapDown: (d) => _lastTapDown = d.localPosition,
              onDoubleTap: () => _handleDoubleTap(constraints.maxWidth),
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: const SizedBox.expand(),
            ),

            // 2. Индикатор перемотки двойным тапом.
            if (_seekAccumSec > 0)
              IgnorePointer(
                child: _SeekBadge(
                  seconds: _seekAccumSec,
                  forward: _seekForward,
                ),
              ),

            // 3. Индикатор масштаба.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _zoomBadgeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: _Pill(
                    child: Text(
                      '${(widget.videoScale * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. Буферизация.
            if (_isBuffering || widget.isChangingQuality)
              const IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // 5. Сам интерфейс.
            AnimatedOpacity(
              opacity: _isVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_isVisible,
                child: _chrome(metrics),
              ),
            ),

            // 6. Панель разрешений + перехват тапа вне неё.
            if (_qualityOpen && _isVisible) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _qualityOpen = false);
                    _startHideTimer();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                right: 12,
                bottom: metrics.qualityPanelBottom,
                child: QualityMenuPanel(
                  qualities: widget.qualities,
                  selected: widget.selectedQuality,
                  onSelected: (value) {
                    setState(() => _qualityOpen = false);
                    _startHideTimer();
                    widget.onQualityChanged?.call(value);
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _chrome(_ControlMetrics m) {
    return Column(
      children: [
        _TopBar(
          title: widget.title,
          metrics: m,
          onBackTap: widget.onBackTap,
        ),
        const Spacer(),
        _CenterControls(
          metrics: m,
          isPlaying: _isPlaying,
          onRewind: () {
            _seekBy(-widget.seekStep);
            _onInteraction();
          },
          onForward: () {
            _seekBy(widget.seekStep);
            _onInteraction();
          },
          onPlayPause: () {
            widget.player.playOrPause();
            _onInteraction();
          },
          stepSeconds: widget.seekStep.inSeconds,
        ),
        const Spacer(),
        _BottomBar(
          metrics: m,
          position: _position,
          duration: _duration,
          buffered: _buffered,
          dragValue: _dragValue,
          isPlaying: _isPlaying,
          isFullscreen: widget.isFullscreen,
          subtitlesEnabled: widget.subtitlesEnabled,
          qualityLabel: _qualityLabel,
          qualityActive: _qualityOpen,
          format: _format,
          onPlayPause: () {
            widget.player.playOrPause();
            _onInteraction();
          },
          onDragStart: (v) {
            _hideTimer?.cancel();
            setState(() => _dragValue = v);
          },
          onDragUpdate: (v) => setState(() => _dragValue = v),
          onDragEnd: (v) {
            widget.player.seek(Duration(milliseconds: v.toInt()));
            setState(() {
              _position = Duration(milliseconds: v.toInt());
              _dragValue = null;
            });
            _onInteraction();
          },
          onQualityTap: () {
            _hideTimer?.cancel();
            setState(() => _qualityOpen = !_qualityOpen);
            if (!_qualityOpen) _startHideTimer();
          },
          onSubtitlesTap: () {
            widget.onToggleSubtitles?.call();
            _onInteraction();
          },
          onSettingsTap: () {
            _hideTimer?.cancel();
            widget.onSettingsTap();
          },
          onRotateTap: () {
            _hideTimer?.cancel();
            widget.onToggleFullscreen();
          },
        ),
      ],
    );
  }
}

/// Набор размеров, подобранный под фактическую высоту области видео:
/// во врезке 16:9 на телефоне доступно ~200–260 px.
class _ControlMetrics {
  const _ControlMetrics({
    required this.playButton,
    required this.playIcon,
    required this.seekIcon,
    required this.barIcon,
    required this.glassButton,
    required this.fontSize,
    required this.trackHeight,
    required this.thumbRadius,
    required this.qualityPanelBottom,
    required this.titleSize,
  });

  final double playButton;
  final double playIcon;
  final double seekIcon;
  final double barIcon;
  final double glassButton;
  final double fontSize;
  final double trackHeight;
  final double thumbRadius;
  final double qualityPanelBottom;
  final double titleSize;

  factory _ControlMetrics.forSize(Size size) {
    final h = size.height;

    if (h < 200) {
      return const _ControlMetrics(
        playButton: 44,
        playIcon: 26,
        seekIcon: 22,
        barIcon: 16,
        glassButton: 28,
        fontSize: 10,
        trackHeight: 2,
        thumbRadius: 5,
        qualityPanelBottom: 56,
        titleSize: 12,
      );
    }
    if (h < 320) {
      return const _ControlMetrics(
        playButton: 54,
        playIcon: 32,
        seekIcon: 26,
        barIcon: 18,
        glassButton: 32,
        fontSize: 11,
        trackHeight: 3,
        thumbRadius: 6,
        qualityPanelBottom: 64,
        titleSize: 13,
      );
    }
    return const _ControlMetrics(
      playButton: 68,
      playIcon: 40,
      seekIcon: 32,
      barIcon: 20,
      glassButton: 38,
      fontSize: 12,
      trackHeight: 4,
      thumbRadius: 7,
      qualityPanelBottom: 76,
      titleSize: 15,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.metrics,
    required this.onBackTap,
  });

  final String title;
  final _ControlMetrics metrics;
  final VoidCallback onBackTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _GlassButton(
              size: metrics.glassButton,
              icon: Icons.arrow_back_rounded,
              tooltip: 'Назад',
              onTap: onBackTap,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  title,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.titleSize,
                    fontWeight: FontWeight.w600,
                    shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
            ),
            SizedBox(width: metrics.glassButton),
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
    required this.stepSeconds,
  });

  final _ControlMetrics metrics;
  final bool isPlaying;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onPlayPause;
  final int stepSeconds;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SeekRoundButton(
          size: metrics.seekIcon * 1.6,
          seconds: stepSeconds,
          forward: false,
          onTap: onRewind,
        ),
        SizedBox(width: metrics.playButton * 0.55),
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
        SizedBox(width: metrics.playButton * 0.55),
        _SeekRoundButton(
          size: metrics.seekIcon * 1.6,
          seconds: stepSeconds,
          forward: true,
          onTap: onForward,
        ),
      ],
    );
  }
}

/// Круглая кнопка перемотки с цифрой внутри — как на макете.
class _SeekRoundButton extends StatelessWidget {
  const _SeekRoundButton({
    required this.size,
    required this.seconds,
    required this.forward,
    required this.onTap,
  });

  final double size;
  final int seconds;
  final bool forward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.black.withValues(alpha: 0.28),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                forward ? Icons.refresh_rounded : Icons.refresh_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: size * 0.86,
                textDirection: forward ? TextDirection.ltr : TextDirection.rtl,
              ),
              Text(
                '$seconds',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.metrics,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.dragValue,
    required this.isPlaying,
    required this.isFullscreen,
    required this.subtitlesEnabled,
    required this.qualityLabel,
    required this.qualityActive,
    required this.format,
    required this.onPlayPause,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onQualityTap,
    required this.onSubtitlesTap,
    required this.onSettingsTap,
    required this.onRotateTap,
  });

  final _ControlMetrics metrics;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double? dragValue;
  final bool isPlaying;
  final bool isFullscreen;
  final bool subtitlesEnabled;
  final String qualityLabel;
  final bool qualityActive;
  final String Function(Duration) format;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onQualityTap;
  final VoidCallback onSubtitlesTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onRotateTap;

  @override
  Widget build(BuildContext context) {
    final maxMs =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value =
        (dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);
    final shown = Duration(milliseconds: value.toInt());
    final labelStyle = TextStyle(
      color: Colors.white,
      fontSize: metrics.fontSize,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Время по краям, как на макете.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(format(shown), style: labelStyle),
                  Text(format(duration), style: labelStyle),
                ],
              ),
            ),
            SizedBox(
              height: metrics.thumbRadius * 4,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: metrics.trackHeight,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: metrics.thumbRadius,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: metrics.thumbRadius * 2.2,
                  ),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  secondaryActiveTrackColor: Colors.white38,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: value,
                  max: maxMs,
                  secondaryTrackValue:
                      buffered.inMilliseconds.toDouble().clamp(0.0, maxMs),
                  onChangeStart: onDragStart,
                  onChanged: onDragUpdate,
                  onChangeEnd: onDragEnd,
                ),
              ),
            ),
            Row(
              children: [
                _GlassButton(
                  size: metrics.glassButton,
                  icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  tooltip: isPlaying ? 'Пауза' : 'Играть',
                  onTap: onPlayPause,
                ),
                const Spacer(),
                // Отдельная кнопка разрешения.
                _GlassButton(
                  size: metrics.glassButton,
                  label: qualityLabel,
                  tooltip: 'Разрешение',
                  isActive: qualityActive,
                  onTap: onQualityTap,
                ),
                const SizedBox(width: 8),
                _GlassButton(
                  size: metrics.glassButton,
                  icon: subtitlesEnabled
                      ? Icons.closed_caption_rounded
                      : Icons.closed_caption_off_rounded,
                  tooltip: 'Субтитры',
                  isActive: subtitlesEnabled,
                  onTap: onSubtitlesTap,
                ),
                const SizedBox(width: 8),
                _GlassButton(
                  size: metrics.glassButton,
                  icon: Icons.settings_rounded,
                  tooltip: 'Настройки',
                  onTap: onSettingsTap,
                ),
                const SizedBox(width: 8),
                _GlassButton(
                  size: metrics.glassButton,
                  icon: isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.screen_rotation_rounded,
                  tooltip: isFullscreen ? 'Выйти' : 'Полный экран',
                  onTap: onRotateTap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Полупрозрачная кнопка-«стекло» со скруглением (иконка или короткий текст).
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.size,
    required this.onTap,
    this.icon,
    this.label,
    this.tooltip,
    this.isActive = false,
  }) : assert(icon != null || label != null);

  final double size;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.white.withValues(alpha: isActive ? 0.30 : 0.16),
      borderRadius: BorderRadius.circular(size * 0.3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: size,
          width: label == null ? size : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 10),
            child: Center(
              child: icon != null
                  ? Icon(icon, color: Colors.white, size: size * 0.55)
                  : Text(
                      label!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

/// Индикатор «−10 сек / +10 сек» при двойном тапе.
class _SeekBadge extends StatelessWidget {
  const _SeekBadge({required this.seconds, required this.forward});

  final int seconds;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: _Pill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '$seconds сек',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: child,
        ),
      ),
    );
  }
}
