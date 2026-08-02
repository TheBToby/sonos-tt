import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../widgets/artwork_provider.dart';

class TurntableLayer extends StatefulWidget {
  const TurntableLayer({super.key});
  @override
  State<TurntableLayer> createState() => _TurntableLayerState();
}

class _TurntableLayerState extends State<TurntableLayer> {
  DateTime? _lastTap;
  Offset? _dragStart;
  double _rotation = 0;
  double _currentSpeed = 0;
  DateTime? _lastFrame;
  Timer? _animTimer;

  static const _accelDuration = 1.5; // seconds

  @override
  void initState() {
    super.initState();
    _startAnim();
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  void _startAnim() {
    _lastFrame = DateTime.now();
    _animTimer?.cancel();
    _animTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      final spinSec = state.config.ui.turntable.spinDuration;
      final maxSpeed = 360.0 / spinSec;
      final target = state.sonos.activePlayback.isPlaying ? maxSpeed : 0.0;
      final rate = maxSpeed / _accelDuration;
      final now = DateTime.now();
      final dt = now.difference(_lastFrame!).inMilliseconds / 1000.0;
      _lastFrame = now;
      if (_currentSpeed < target) {
        _currentSpeed =
            (target - _currentSpeed).abs() < rate * dt ? target : _currentSpeed + rate * dt;
      } else if (_currentSpeed > target) {
        _currentSpeed =
            (target - _currentSpeed).abs() < rate * dt ? target : _currentSpeed - rate * dt;
      } else {
        // already at target
      }
      _rotation = (_rotation + _currentSpeed * dt) % 360;
      setState(() {});
    });
  }

  Timer? _doubleTapTimer;

  void _handleTap(TapUpDetails details) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 350) {
      // Double-tap: show nav
      _doubleTapTimer?.cancel();
      _lastTap = null;
      context.read<AppState>().showNav();
      return;
    }
    // Single tap: delay to wait for possible double-tap
    _lastTap = now;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 360), () {
      if (mounted) {
        final state = context.read<AppState>();
        if (!state.navVisible) {
          state.togglePlayPause();
        }
      }
    });
  }

  void _handlePanStart(DragStartDetails details) {
    // Don't handle swipes when nav is visible
    if (context.read<AppState>().navVisible) return;
    _dragStart = details.globalPosition;
  }

  void _handlePanEnd(DragEndDetails details, Size screenSize) {
    if (_dragStart == null) return;
    final dx = details.velocity.pixelsPerSecond.dx;
    final dy = details.velocity.pixelsPerSecond.dy;
    final speed = math.sqrt(dx * dx + dy * dy);
    final state = context.read<AppState>();
    if (speed < 200) return;
    if (dx.abs() > dy.abs()) {
      if (dx < 0) {
        state.nextTrack();
      } else {
        state.previousTrack();
      }
    } else {
      if (dy < 0) {
        state.setVolume((state.sonos.activeSpeaker?.volume ?? 0) + 8);
      } else {
        state.setVolume((state.sonos.activeSpeaker?.volume ?? 0) - 8);
      }
    }
    _dragStart = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pb = state.sonos.activePlayback;
    final c = context.c;
    final size = MediaQuery.of(context).size.shortestSide;
    final screenSize = MediaQuery.of(context).size;

    if (state.view != AppView.turntable) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTap,
      onPanStart: _handlePanStart,
      onPanEnd: (d) => _handlePanEnd(d, screenSize),
      child: Container(
        color: c.bg,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Full-screen rotating vinyl (artwork covers entire disc, like Svelte)
            Transform.rotate(
              angle: _rotation * math.pi / 180,
              child: Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1a1a1a),
                ),
                clipBehavior: Clip.antiAlias,
                child: pb.artworkUrl.isNotEmpty
                    ? Image(
                        image: ArtworkImageProvider(pb.artworkUrl, state.artworkCache),
                        fit: BoxFit.cover,
                        color: Colors.white.withValues(alpha: 0.7),
                        colorBlendMode: BlendMode.modulate,
                      )
                    : Center(
                        child: Icon(Icons.music_note, size: size * 0.15, color: c.textDim),
                      ),
              ),
            ),
            // Vinyl grooves overlay
            Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: CustomPaint(
                painter: VinylGroovesPainter(
                  grooveColor: Colors.white.withValues(alpha: 0.06),
                  ringCount: 40,
                ),
              ),
            ),
            // Center spindle hole
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 3,
                    spreadRadius: -1,
                  ),
                ],
              ),
            ),
            // Speaker name at top
            if (state.sonos.activeSpeaker?.name.isNotEmpty ?? false)
              Positioned(
                top: size * 0.25,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.white.withValues(alpha: 0.7),
                  padding: EdgeInsets.symmetric(vertical: size * 0.01),
                  child: Text(
                    state.sonos.activeSpeaker!.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textDim,
                      fontSize: size * 0.035,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            // Track info at bottom
            Positioned(
              bottom: size * 0.23,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white.withValues(alpha: 0.7),
                padding: EdgeInsets.symmetric(vertical: size * 0.01),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pb.title.isNotEmpty ? pb.title : '—',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: size * 0.038,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      pb.artist.isNotEmpty ? pb.artist : '—',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textDim,
                        fontSize: size * 0.025,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Connection indicator dot
            Positioned(
              top: size * 0.05,
              right: size * 0.05,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.connection.connected
                      ? Colors.green
                      : state.connection.mock
                          ? Colors.orange
                          : Colors.red,
                ),
              ),
            ),
            // Mock mode banner
            if (state.connection.mock)
              Positioned(
                top: size * 0.12,
                left: 0,
                right: 0,
                child: Container(
                  width: size * 0.72,
                  margin: EdgeInsets.symmetric(horizontal: size * 0.14),
                  padding: EdgeInsets.all(size * 0.015),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '⚠️ ${state.t('connection.mock_title')}',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: size * 0.022,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: size * 0.005),
                      Text(
                        state.t('connection.mock_text'),
                        style: TextStyle(
                          color: c.textDim,
                          fontSize: size * 0.018,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: size * 0.006),
                      GestureDetector(
                        onTap: () => state.api.retryRealConnection(),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: size * 0.03,
                            vertical: size * 0.006,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '↻ ${state.t('connection.retry')}',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: size * 0.019,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VinylGroovesPainter extends CustomPainter {
  final Color grooveColor;
  final int ringCount;
  VinylGroovesPainter({required this.grooveColor, required this.ringCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final minR = maxR * 0.36; // label area
    final paint = Paint()
      ..color = grooveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < ringCount; i++) {
      final r = minR + (maxR - minR) * (i / ringCount);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant VinylGroovesPainter old) => grooveColor != old.grooveColor;
}
