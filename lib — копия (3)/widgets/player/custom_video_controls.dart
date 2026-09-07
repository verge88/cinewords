import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

class _CustomVideoControlsState extends State<CustomVideoControls> with SingleTickerProviderStateMixin {
  bool _isVisible = false;
  Timer? _hideTimer;
  
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _buffer = 0.0;

  late StreamSubscription _positionSub;
  late StreamSubscription _durationSub;
  late StreamSubscription _playingSub;
  late StreamSubscription _bufferSub;

  @override
  void initState() {
    super.initState();
    _isVisible = true;
    _startHideTimer();

    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _isPlaying = widget.player.state.playing;
    _buffer = widget.player.state.buffer.inMilliseconds.toDouble() / (_duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1);

    _positionSub = widget.player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub = widget.player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _playingSub = widget.player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        if (playing) {
          _startHideTimer();
        } else {
          _hideTimer?.cancel();
          setState(() => _isVisible = true);
        }
      }
    });
    _bufferSub = widget.player.stream.buffer.listen((buffer) {
      if (mounted) {
        final total = _duration.inMilliseconds.toDouble();
        if (total > 0) {
          setState(() => _buffer = buffer.inMilliseconds / total);
        }
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _playingSub.cancel();
    _bufferSub.cancel();
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
      if (mounted && _isPlaying) {
        setState(() => _isVisible = false);
      }
    });
  }

  void _onInteraction() {
    if (_isVisible) _startHideTimer();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
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
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !_isVisible,
            child: Container(
              color: Colors.black45, // Dark overlay
              child: Column(
                children: [
                  // Top Bar
                  _buildTopBar(),
                  
                  // Center Play/Pause
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () {
                            _onInteraction();
                            var target = widget.player.state.position - const Duration(seconds: 10);
                            widget.player.seek(target > Duration.zero ? target : Duration.zero);
                          },
                          icon: Icon(Icons.replay_10_rounded, color: Colors.white, size: widget.isFullscreen ? 36 : 48),
                        ),
                        IconButton.filled(
                          onPressed: () {
                            _onInteraction();
                            widget.player.playOrPause();
                          },
                          icon: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: widget.isFullscreen ? 36 : 48,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            fixedSize: widget.isFullscreen ? const Size(34, 34) : const Size(80, 80),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _onInteraction();
                            var target = widget.player.state.position + const Duration(seconds: 10);
                            widget.player.seek(target < _duration ? target : _duration);
                          },
                          icon: Icon(Icons.forward_10_rounded, color: Colors.white, size: widget.isFullscreen ? 36 : 48),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Bar
                  _buildBottomBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              iconSize: widget.isFullscreen ? 20 : 24,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: widget.onBackTap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: widget.isFullscreen ? 15 : 18, 
                  fontWeight: FontWeight.w600
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress Bar
            Row(
              children: [
                Text(_formatDuration(_position), style: TextStyle(color: Colors.white, fontSize: widget.isFullscreen ? 11 : 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: widget.isFullscreen ? 3 : 4,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: widget.isFullscreen ? 4 : 6),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: widget.isFullscreen ? 10 : 14),
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: Slider(
                      value: _position.inMilliseconds.toDouble(),
                      max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1,
                      onChanged: (val) {
                        _onInteraction();
                        widget.player.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatDuration(_duration), style: TextStyle(color: Colors.white, fontSize: widget.isFullscreen ? 11 : 13)),
              ],
            ),
            const SizedBox(height: 4),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  iconSize: widget.isFullscreen ? 20 : 24,
                  icon: const Icon(Icons.settings_rounded, color: Colors.white),
                  onPressed: () {
                    _hideTimer?.cancel();
                    widget.onSettingsTap();
                  },
                ),
                IconButton(
                  iconSize: widget.isFullscreen ? 20 : 24,
                  icon: Icon(
                    widget.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  onPressed: widget.onToggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
