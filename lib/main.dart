import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'app_theme.dart';
import 'models/app_config.dart';
import 'services/artwork_cache.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  FlutterError.onError = (details) {
    print('[FlutterError] ${details.exception}');
    print('[FlutterError] ${details.stack}');
  };
  runApp(
    ChangeNotifierProvider(create: (_) => AppState(), child: const SonosApp()),
  );
}

// =============================================================================
// Gesture detection (ported from gestures.js)
// =============================================================================

enum GestureType { tap, swipeLeft, swipeRight, swipeUp, swipeDown, doubleTap }

GestureType? detectGesture(
    DragStartDetails start, DragEndDetails end, Size screenSize) {
  final dx = end.velocity.pixelsPerSecond.dx;
  final dy = end.velocity.pixelsPerSecond.dy;
  final speed = math.sqrt(dx * dx + dy * dy);
  if (speed < 200) return GestureType.tap;
  if (dx.abs() > dy.abs()) {
    return dx < 0 ? GestureType.swipeLeft : GestureType.swipeRight;
  }
  return dy < 0 ? GestureType.swipeUp : GestureType.swipeDown;
}

// =============================================================================
// SVG wedge path (ported from svgPaths.js)
// =============================================================================

Path wedgePath(double cx, double cy, double innerR, double outerR,
    double startDeg, double endDeg) {
  final startRad = (startDeg - 90) * math.pi / 180;
  final endRad = (endDeg - 90) * math.pi / 180;
  return Path()
    ..moveTo(cx + innerR * math.cos(startRad), cy + innerR * math.sin(startRad))
    ..lineTo(cx + outerR * math.cos(startRad), cy + outerR * math.sin(startRad))
    ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: outerR),
        startRad,
        endRad - startRad,
        false)
    ..lineTo(cx + innerR * math.cos(endRad), cy + innerR * math.sin(endRad))
    ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
        endRad,
        startRad - endRad,
        false)
    ..close();
}

// =============================================================================
// Main App
// =============================================================================

class SonosApp extends StatelessWidget {
  const SonosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String>(
      selector: (_, s) => s.config.ui.theme,
      builder: (context, theme, _) {
        final td = theme == 'light'
            ? AppTheme.light()
            : theme == 'dark'
                ? AppTheme.dark()
                : AppTheme.dark(); // Default dark for kiosk
        return MaterialApp(
          title: 'Sonos TT',
          theme: td,
          debugShowCheckedModeBanner: false,
          home: const CircularShell(),
        );
      },
    );
  }
}

// =============================================================================
// Circular Shell — clips everything to a 1080×1080 circle
// =============================================================================

class CircularShell extends StatefulWidget {
  const CircularShell({super.key});
  @override
  State<CircularShell> createState() => _CircularShellState();
}

class _CircularShellState extends State<CircularShell> {
  DateTime? _lastInteraction;
  Timer? _screensaverTimer;

  @override
  void initState() {
    super.initState();
    _resetScreensaver();
  }

  void _resetScreensaver() {
    _lastInteraction = DateTime.now();
    _screensaverTimer?.cancel();
    final state = context.read<AppState>();
    _screensaverTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final cfg = state.config;
      if (!cfg.ui.screensaver.enabled) return;
      final elapsed = DateTime.now().difference(_lastInteraction!).inSeconds;
      if (elapsed >= cfg.ui.screensaver.timeout &&
          state.view != AppView.screensaver) {
        state.setView(AppView.screensaver);
      }
    });
  }

  void _onInteraction() {
    final state = context.read<AppState>();
    if (state.view == AppView.screensaver) {
      state.setView(AppView.turntable);
    }
    _lastInteraction = DateTime.now();
  }

  @override
  void dispose() {
    _screensaverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.shortestSide;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _onInteraction(),
              onPanStart: (_) => _onInteraction(),
              child: const Stack(
                children: [
                  TurntableLayer(),
                  NavLayer(),
                  DialogLayer(),
                  ScreensaverLayer(),
                  ToastLayer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Turntable Layer
// =============================================================================

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
        _currentSpeed = (target - _currentSpeed).abs() < rate * dt
            ? target
            : _currentSpeed + rate * dt;
      } else if (_currentSpeed > target) {
        _currentSpeed = (target - _currentSpeed).abs() < rate * dt
            ? target
            : _currentSpeed - rate * dt;
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
      if (dx < 0) state.nextTrack();
      else state.previousTrack();
    } else {
      if (dy < 0) state.setVolume((state.sonos.activeSpeaker?.volume ?? 0) + 8);
      else state.setVolume((state.sonos.activeSpeaker?.volume ?? 0) - 8);
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
                        image: _ArtworkProvider(pb.artworkUrl, state.artworkCache),
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: CustomPaint(
                painter: _VinylGroovesPainter(
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

class _VinylGroovesPainter extends CustomPainter {
  final Color grooveColor;
  final int ringCount;
  _VinylGroovesPainter(
      {required this.grooveColor, required this.ringCount});

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
  bool shouldRepaint(covariant _VinylGroovesPainter old) =>
      grooveColor != old.grooveColor;
}

class _ArtworkProvider extends ImageProvider<_ArtworkProvider> {
  final String url;
  final ArtworkCache cache;
  _ArtworkProvider(this.url, this.cache);

  @override
  Future<_ArtworkProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ArtworkProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      _ArtworkProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final bytes = await cache.get(url);
    if (bytes == null) throw Exception('Artwork load failed');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }
}

// =============================================================================
// Navigation Layer — Radial Nav
// =============================================================================

class NavLayer extends StatelessWidget {
  const NavLayer({super.key});

  // Matches Svelte order: volume, next, queue, settings, prev, speakers
  static const _segments = [
    _NavSeg(icon: Icons.volume_up, label: 'volume'),
    _NavSeg(icon: Icons.skip_next, label: 'next'),
    _NavSeg(icon: Icons.queue_music, label: 'queue'),
    _NavSeg(icon: Icons.settings, label: 'settings'),
    _NavSeg(icon: Icons.skip_previous, label: 'prev'),
    _NavSeg(icon: Icons.speaker, label: 'speakers'),
  ];

  int? _hitTest(Offset localPos, double cx, double cy, double innerR, double outerR) {
    final dx = localPos.dx - cx;
    final dy = localPos.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < innerR || dist > outerR) return null;
    // Angle from top (12 o'clock), clockwise
    var angle = math.atan2(dx, -dy) * 180 / math.pi;
    if (angle < 0) angle += 360;
    final segAngle = 360.0 / _segments.length;
    final idx = (angle / segAngle).floor();
    if (idx >= 0 && idx < _segments.length) return idx;
    return null;
  }

  void _handleSegmentTap(AppState state, String label) {
    switch (label) {
      case 'volume':
        state.setVolumeMode(state.volumeMode == 'ring' ? null : 'ring');
        break;
      case 'next':
        state.nextTrack();
        break;
      case 'queue':
        state.setView(AppView.playlists);
        break;
      case 'settings':
        state.setView(AppView.settings);
        break;
      case 'prev':
        state.previousTrack();
        break;
      case 'speakers':
        state.setView(AppView.speakers);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final view = state.view;
    final c = context.c;
    final size = MediaQuery.of(context).size.shortestSide;
    final navVisible = state.navVisible;

    if (view != AppView.turntable) return const SizedBox.shrink();

    final cx = size / 2;
    final cy = size / 2;
    final innerR = size * 0.20;
    final outerR = size * 0.34;
    final centerR = size * 0.18;
    final segAngle = 360.0 / _segments.length;
    final gap = 2.0;

    return IgnorePointer(
      ignoring: !navVisible,
      child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final localPos = details.localPosition;
        final hitIdx = _hitTest(localPos, cx, cy, innerR, outerR);
        if (hitIdx != null) {
          _handleSegmentTap(state, _segments[hitIdx].label);
        } else {
          // Check if tapped center circle
          final dx = localPos.dx - cx;
          final dy = localPos.dy - cy;
          if (math.sqrt(dx * dx + dy * dy) <= centerR) {
            state.togglePlayPause();
          } else {
            // Tapped outside ring — hide nav
            state.hideNav();
          }
        }
      },
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RadialNavPainter(
            cx: cx,
            cy: cy,
            innerR: innerR,
            outerR: outerR,
            centerR: centerR,
            segments: _segments,
            segAngle: segAngle,
            gap: gap,
            navVisible: navVisible,
            isPlaying: state.sonos.activePlayback.isPlaying,
            volumeMode: state.volumeMode,
            colors: _NavColors(
              glass: c.glass,
              surface: c.surface,
              surface2: c.surface2,
              accent: c.accent,
              text: c.text,
              scrim: c.scrim,
              glassBorder: c.glassBorder,
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _NavSeg {
  final IconData icon;
  final String label;
  const _NavSeg({required this.icon, required this.label});
}

class _NavColors {
  final Color glass, surface, surface2, accent, text, scrim, glassBorder;
  const _NavColors({
    required this.glass,
    required this.surface,
    required this.surface2,
    required this.accent,
    required this.text,
    required this.scrim,
    required this.glassBorder,
  });
}

class _RadialNavPainter extends CustomPainter {
  final double cx, cy, innerR, outerR, centerR, segAngle, gap;
  final List<_NavSeg> segments;
  final bool navVisible, isPlaying;
  final String? volumeMode;
  final _NavColors colors;

  _RadialNavPainter({
    required this.cx,
    required this.cy,
    required this.innerR,
    required this.outerR,
    required this.centerR,
    required this.segments,
    required this.segAngle,
    required this.gap,
    required this.navVisible,
    required this.isPlaying,
    required this.volumeMode,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scrim background (semi-transparent when nav visible)
    if (navVisible) {
      canvas.drawCircle(
        Offset(cx, cy),
        size.width / 2,
        Paint()..color = colors.scrim.withValues(alpha: 0.5),
      );
    }

    // Draw segments
    for (var i = 0; i < segments.length; i++) {
      final startDeg = i * segAngle + gap / 2;
      final endDeg = (i + 1) * segAngle - gap / 2;
      final path = wedgePath(cx, cy, innerR, outerR, startDeg, endDeg);
      final isVolumeActive = volumeMode == 'ring' && segments[i].label == 'volume';
      canvas.drawPath(
        path,
        Paint()
          ..color = isVolumeActive
              ? colors.accent.withValues(alpha: 0.5)
              : colors.glass.withValues(alpha: navVisible ? 0.8 : 0.0),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );

      // Draw icon
      if (navVisible) {
        final midDeg = i * segAngle + segAngle / 2;
        final midRad = (midDeg - 90) * math.pi / 180;
        final iconR = (innerR + outerR) / 2;
        final ix = cx + iconR * math.cos(midRad);
        final iy = cy + iconR * math.sin(midRad);
        _drawIcon(canvas, segments[i].icon, ix, iy, 14, colors.text);
      }
    }

    // Volume ring (when active)
    if (volumeMode == 'ring' && navVisible) {
      final volR = outerR + size.width * 0.02;
      canvas.drawCircle(
        Offset(cx, cy),
        volR,
        Paint()
          ..color = colors.surface2.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Center circle (play/pause) — always visible, subtle when nav hidden
    canvas.drawCircle(
      Offset(cx, cy),
      centerR,
      Paint()
        ..color = colors.surface.withValues(alpha: navVisible ? 1.0 : 0.5),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      centerR,
      Paint()
        ..color = colors.glassBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Play/pause icon
    final iconSize = centerR * 0.4;
    if (isPlaying) {
      // Pause: two vertical bars
      final barW = iconSize * 0.25;
      final barH = iconSize * 0.8;
      final gap2 = iconSize * 0.2;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx - gap2, cy), width: barW, height: barH),
        Paint()..color = colors.accent,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx + gap2, cy), width: barW, height: barH),
        Paint()..color = colors.accent,
      );
    } else {
      // Play: triangle
      final triPath = Path()
        ..moveTo(cx - iconSize * 0.3, cy - iconSize * 0.5)
        ..lineTo(cx + iconSize * 0.5, cy)
        ..lineTo(cx - iconSize * 0.3, cy + iconSize * 0.5)
        ..close();
      canvas.drawPath(triPath, Paint()..color = colors.accent);
    }
  }

  void _drawIcon(Canvas canvas, IconData icon, double x, double y, double size, Color color) {
    // Use TextPainter to render Material icon
    final textPainter = TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(
        fontSize: size * 2,
        color: color,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RadialNavPainter old) =>
      navVisible != old.navVisible ||
      isPlaying != old.isPlaying ||
      volumeMode != old.volumeMode;
}

// =============================================================================
// Dialog Layer — Speakers, Playlists, Users, Settings
// =============================================================================

class DialogLayer extends StatelessWidget {
  const DialogLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final view = context.watch<AppState>().view;
    if (view == AppView.turntable || view == AppView.screensaver) {
      return const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: BarPanel(
        key: ValueKey(view),
        view: view,
      ),
    );
  }
}

class BarPanel extends StatelessWidget {
  final AppView view;
  const BarPanel({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final size = MediaQuery.of(context).size.shortestSide;

    String title;
    switch (view) {
      case AppView.speakers:
        title = state.t('speakers.title');
        break;
      case AppView.playlists:
        title = state.t('playlists.title');
        break;
      case AppView.users:
        title = state.t('users.title');
        break;
      case AppView.settings:
        title = state.t('settings.title');
        break;
      default:
        title = '';
    }

    return Container(
      width: size,
      height: size,
      color: c.scrim,
      child: Center(
        child: Container(
          width: size * 0.82,
          height: size * 0.72,
          decoration: BoxDecoration(
            color: c.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Vertical title bar on the left
              Container(
                width: 32,
                color: c.surface2,
                child: Column(
                  children: [
                    // Rotated title
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Center(
                          child: Text(
                            title.toUpperCase(),
                            style: TextStyle(
                              color: c.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Close button at bottom of sidebar
                    GestureDetector(
                      onTap: () => state.setView(AppView.turntable),
                      child: Container(
                        width: 32,
                        height: 32,
                        color: c.surface2,
                        child: Icon(Icons.close, size: 16, color: c.textDim),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable content
              Expanded(
                child: _buildContent(context, state, size),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppState state, double size) {
    switch (view) {
      case AppView.speakers:
        return _SpeakersPanel(size: size);
      case AppView.playlists:
        return _PlaylistsPanel(size: size);
      case AppView.users:
        return _UsersPanel(size: size);
      case AppView.settings:
        return _SettingsPanel(size: size);
      default:
        return const SizedBox.shrink();
    }
  }
}

// =============================================================================
// Speakers Panel
// =============================================================================

class _SpeakersPanel extends StatefulWidget {
  final double size;
  const _SpeakersPanel({required this.size});

  @override
  State<_SpeakersPanel> createState() => _SpeakersPanelState();
}

class _SpeakersPanelState extends State<_SpeakersPanel> {
  String? expandedGroup;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final sonos = state.sonos;
    final s = widget.size;

    // Grouped speakers
    final multiGroups = sonos.groups
        .where((g) => g.memberUids.length > 1)
        .toList();

    // Solo speakers (not in any multi-group)
    final soloSpeakers = sonos.speakers.where((sp) {
      return !multiGroups
          .any((g) => g.memberUids.contains(sp.uid));
    }).toList();

    if (sonos.speakers.isEmpty) {
      return Center(
        child: Text(state.t('speakers.none_found'),
            style: TextStyle(color: c.textDim, fontSize: s * 0.028)),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: s * 0.02, vertical: s * 0.02),
      child: Column(
        children: [
          // Groups
          ...multiGroups.map((g) {
            final coord =
                sonos.speakers.where((s) => s.uid == g.coordinatorUid).firstOrNull;
            final isExpanded = expandedGroup == g.coordinatorUid;
            final isActive = g.coordinatorUid == sonos.activeSpeakerUid;
            return _SpeakerCard(
              name: coord?.name ?? g.coordinatorUid,
              volume: coord?.volume ?? 0,
              isActive: isActive,
              isCoordinator: true,
              suffix: '+${g.memberUids.length - 1}',
              onTap: () => state.setActiveSpeaker(g.coordinatorUid),
              onExpand: () => setState(() =>
                  expandedGroup =
                      expandedGroup == g.coordinatorUid ? null : g.coordinatorUid),
              expanded: isExpanded,
              child: isExpanded
                  ? Column(
                      children: g.memberUids.map((mUid) {
                        final member = sonos.speakers
                            .where((s) => s.uid == mUid)
                            .firstOrNull;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                    member?.name ?? mUid,
                                    style: TextStyle(
                                        color: c.text,
                                        fontSize: s * 0.024)),
                              ),
                              Text('🔊 ${member?.volume ?? 0}',
                                  style: TextStyle(
                                      color: c.textDim,
                                      fontSize: s * 0.02)),
                              if (mUid != g.coordinatorUid)
                                GestureDetector(
                                  onTap: () =>
                                      state.ungroupSpeaker(mUid),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.close,
                                        size: 14, color: c.danger),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  : null,
            );
          }),
          // Solo speakers
          ...soloSpeakers.map((sp) => _SpeakerCard(
                name: sp.name,
                volume: sp.volume,
                isActive: sp.uid == sonos.activeSpeakerUid,
                isCoordinator: true,
                onTap: () => state.setActiveSpeaker(sp.uid),
              )),
        ],
      ),
    );
  }
}

class _SpeakerCard extends StatelessWidget {
  final String name;
  final int volume;
  final bool isActive;
  final bool isCoordinator;
  final String? suffix;
  final VoidCallback onTap;
  final VoidCallback? onExpand;
  final Widget? child;
  final bool expanded;

  const _SpeakerCard({
    required this.name,
    required this.volume,
    required this.isActive,
    required this.isCoordinator,
    this.suffix,
    required this.onTap,
    this.onExpand,
    this.child,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: c.accent, width: 2)
              : null,
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCoordinator ? c.accent : c.textDim,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name${suffix != null ? ' $suffix' : ''}',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('🔊 $volume',
                        style: TextStyle(color: c.textDim, fontSize: 11)),
                    if (onExpand != null) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onExpand,
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18,
                          color: c.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Playlists Panel
// =============================================================================

class _PlaylistsPanel extends StatefulWidget {
  final double size;
  const _PlaylistsPanel({required this.size});

  @override
  State<_PlaylistsPanel> createState() => _PlaylistsPanelState();
}

class _PlaylistsPanelState extends State<_PlaylistsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchPlaylists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final s = widget.size;
    final playlists = state.sonos.activePlaylists;
    final queue = state.sonos.activeQueue;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: s * 0.02, vertical: s * 0.02),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (playlists.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(s * 0.04),
                child: Text(state.t('playlists.empty'),
                    style:
                        TextStyle(color: c.textDim, fontSize: s * 0.028)),
              ),
            )
          else
            ...playlists.map((pl) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: GestureDetector(
                    onTap: () => state.playPlaylist(pl.title),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Text('🎵', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pl.title,
                              style: TextStyle(
                                color: c.text,
                                fontSize: s * 0.026,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
          if (queue.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(
                  top: s * 0.04, bottom: s * 0.02, left: 4),
              child: Text(
                state.t('playlists.queue').toUpperCase(),
                style: TextStyle(
                  color: c.textDim,
                  fontSize: s * 0.022,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
            ...queue.take(6).toList().asMap().entries.map((e) {
              final i = e.key;
              final q = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: i == 0
                        ? Border(left: BorderSide(color: c.accent, width: 3))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: s * 0.024,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis),
                      if (q.artist.isNotEmpty)
                        Text(q.artist,
                            style: TextStyle(
                                color: c.textDim, fontSize: s * 0.02)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Users Panel
// =============================================================================

class _UsersPanel extends StatelessWidget {
  final double size;
  const _UsersPanel({required this.size});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final s = size;
    final accounts = state.config.spotify.accounts;
    final defaultId = state.config.spotify.defaultAccount;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: s * 0.03, vertical: s * 0.03),
      child: Column(
        children: accounts.map((acc) {
          final isCurrent = acc.id == defaultId;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: GestureDetector(
              onTap: () {
                if (!isCurrent) {
                  final newCfg = state.config.copyWith(
                    spotify: SpotifyConfig(
                      accounts: accounts,
                      defaultAccount: acc.id,
                    ),
                  );
                  state.updateConfig(newCfg);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: isCurrent
                      ? Border.all(color: c.accent, width: 2)
                      : null,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _parseColor(acc.color),
                      child: Text(
                        acc.label.isNotEmpty ? acc.label[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: s * 0.024,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(acc.label,
                              style: TextStyle(
                                color: c.text,
                                fontSize: s * 0.028,
                                fontWeight: FontWeight.w600,
                              )),
                          if (isCurrent)
                            Text(state.t('users.current'),
                                style: TextStyle(
                                    color: c.accent, fontSize: s * 0.02)),
                        ],
                      ),
                    ),
                    if (!isCurrent)
                      Icon(Icons.arrow_forward_ios,
                          size: 14, color: c.textDim),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF4fc3f7);
    }
  }
}

// =============================================================================
// Settings Panel
// =============================================================================

class _SettingsPanel extends StatefulWidget {
  final double size;
  const _SettingsPanel({required this.size});

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late TextEditingController _urlController;
  late String _theme;
  late String _language;
  late bool _ssEnabled;
  late double _ssTimeout;
  late String _ssMode;
  late double _ssBrightness;
  late double _spinDuration;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().config;
    _urlController = TextEditingController(text: cfg.socoApi.baseUrl);
    _theme = cfg.ui.theme;
    _language = cfg.ui.language;
    _ssEnabled = cfg.ui.screensaver.enabled;
    _ssTimeout = cfg.ui.screensaver.timeout.toDouble();
    _ssMode = cfg.ui.screensaver.mode;
    _ssBrightness = cfg.ui.screensaver.brightness;
    _spinDuration = cfg.ui.turntable.spinDuration.toDouble();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final s = widget.size;
    final conn = state.connection;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: s * 0.025, vertical: s * 0.02),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // API Status
          _sectionTitle(c, s, state.t('settings.api')),
          _settingRow(c, s, state.t('settings.api.baseUrl'),
              TextField(
                controller: _urlController,
                style: TextStyle(color: c.text, fontSize: s * 0.024),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              )),
          _settingRow(c, s, state.t('settings.api.status'),
              Text(
                conn.mock
                    ? state.t('connection.mock_title')
                    : conn.connected
                        ? state.t('settings.api.status.connected')
                        : state.t('settings.api.status.disconnected'),
                style: TextStyle(
                  color: conn.connected ? c.success : c.danger,
                  fontSize: s * 0.026,
                ),
              )),
          if (conn.mock)
            Padding(
              padding: EdgeInsets.only(bottom: s * 0.02),
              child: Row(
                children: [
                  Expanded(
                    child: Text(state.t('connection.mock_text'),
                        style: TextStyle(
                            color: c.textDim, fontSize: s * 0.02)),
                  ),
                  GestureDetector(
                    onTap: () {
                      state.api.retryRealConnection();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: s * 0.02, vertical: s * 0.01),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(state.t('connection.retry'),
                          style: TextStyle(
                              color: c.accent, fontSize: s * 0.022)),
                    ),
                  ),
                ],
              ),
            ),
          _divider(c, s),
          // Theme
          _sectionTitle(c, s, state.t('settings.theme')),
          _segmentedPicker(c, s, [
            const _SegOption('auto', 'System'),
            const _SegOption('dark', 'Dark'),
            const _SegOption('light', 'Light'),
          ], _theme, (v) => setState(() => _theme = v)),
          _divider(c, s),
          // Language
          _sectionTitle(c, s, state.t('settings.language')),
          _segmentedPicker(c, s, [
            const _SegOption('de', 'Deutsch'),
            const _SegOption('en', 'English'),
          ], _language, (v) => setState(() => _language = v)),
          _divider(c, s),
          // Screensaver
          _sectionTitle(c, s, state.t('settings.screensaver')),
          _switchRow(c, s, state.t('settings.screensaver.enabled'), _ssEnabled,
              (v) => setState(() => _ssEnabled = v)),
          _sliderRow(c, s, state.t('settings.screensaver.timeout'), _ssTimeout,
              5.0, 120.0, (v) => setState(() => _ssTimeout = v),
              suffix: 's'),
          _segmentedPicker(c, s, [
            const _SegOption('analog', 'Analog'),
            const _SegOption('digital', 'Digital'),
          ], _ssMode, (v) => setState(() => _ssMode = v)),
          _sliderRow(c, s, state.t('settings.screensaver.brightness'),
              _ssBrightness, 0.05, 1.0, (v) => setState(() => _ssBrightness = v)),
          _divider(c, s),
          // Turntable
          _sectionTitle(c, s, state.t('settings.turntable')),
          _sliderRow(c, s, state.t('settings.turntable.spin'), _spinDuration,
              2.0, 30.0, (v) => setState(() => _spinDuration = v),
              suffix: 's'),
          const SizedBox(height: 20),
          // Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => state.resetConfig(),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s * 0.02),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(state.t('settings.reset'),
                          style: TextStyle(
                              color: c.textDim, fontSize: s * 0.026)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s * 0.02),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(state.t('settings.save'),
                          style: TextStyle(
                              color: c.bg,
                              fontSize: s * 0.026,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _save() {
    final state = context.read<AppState>();
    state.updateConfig(AppConfig(
      socoApi: state.config.socoApi.copyWith(
        baseUrl: _urlController.text.trim(),
      ),
      ui: UiConfig(
        language: _language,
        theme: _theme,
        screensaver: ScreensaverConfig(
          enabled: _ssEnabled,
          timeout: _ssTimeout.round(),
          mode: _ssMode,
          brightness: _ssBrightness,
        ),
        turntable: TurntableConfig(
          spinDuration: _spinDuration.round(),
        ),
      ),
      spotify: state.config.spotify,
    ));
    state.setView(AppView.turntable);
  }

  Widget _sectionTitle(SonosColors c, double s, String title) => Padding(
        padding: EdgeInsets.only(bottom: s * 0.015),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: c.accent,
            fontSize: s * 0.022,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _divider(SonosColors c, double s) => Padding(
        padding: EdgeInsets.symmetric(vertical: s * 0.015),
        child: Container(height: 1, color: c.glassBorder),
      );

  Widget _settingRow(SonosColors c, double s, String label, Widget child) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.008),
      child: Row(
        children: [
          SizedBox(
            width: s * 0.22,
            child: Text(label,
                style: TextStyle(color: c.textDim, fontSize: s * 0.024)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _switchRow(SonosColors c, double s, String label, bool value,
          ValueChanged<bool> onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.008),
      child: Row(
        children: [
          SizedBox(
            width: s * 0.22,
            child: Text(label,
                style: TextStyle(color: c.textDim, fontSize: s * 0.024)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: c.accent,
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(SonosColors c, double s, String label, double value,
          double min, double max, ValueChanged<double> onChanged,
          {String? suffix}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.006),
      child: Row(
        children: [
          SizedBox(
            width: s * 0.22,
            child: Text(label,
                style: TextStyle(color: c.textDim, fontSize: s * 0.024)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              activeColor: c.accent,
              label: '${value.round()}${suffix ?? ''}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedPicker(SonosColors c, double s,
      List<_SegOption> options, String current, ValueChanged<String> onSelected) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s * 0.008),
      child: Row(
        children: options.map((opt) {
          final active = opt.value == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(opt.value),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: EdgeInsets.symmetric(vertical: s * 0.012),
                decoration: BoxDecoration(
                  color: active ? c.accent : c.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(opt.label,
                      style: TextStyle(
                        color: active ? c.bg : c.textDim,
                        fontSize: s * 0.022,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal,
                      )),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SegOption {
  final String value, label;
  const _SegOption(this.value, this.label);
}

// =============================================================================
// Screensaver Layer
// =============================================================================

class ScreensaverLayer extends StatefulWidget {
  const ScreensaverLayer({super.key});
  @override
  State<ScreensaverLayer> createState() => _ScreensaverLayerState();
}

class _ScreensaverLayerState extends State<ScreensaverLayer> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = context.watch<AppState>().view;
    if (view != AppView.screensaver) return const SizedBox.shrink();

    final cfg = context.watch<AppState>().config.ui.screensaver;
    final size = MediaQuery.of(context).size.shortestSide;

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 600),
      child: Container(
        width: size,
        height: size,
        color: Colors.black,
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix([
            cfg.brightness, 0, 0, 0, 0,
            0, cfg.brightness, 0, 0, 0,
            0, 0, cfg.brightness, 0, 0,
            0, 0, 0, 1.0, 0,
          ]),
          child: cfg.mode == 'analog'
              ? _AnalogClock(now: _now, size: size)
              : _DigitalClock(now: _now, size: size),
        ),
      ),
    );
  }
}

class _AnalogClock extends StatelessWidget {
  final DateTime now;
  final double size;
  const _AnalogClock({required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    final h = now.hour % 12;
    final m = now.minute;
    final s = now.second;
    final hourAngle = (h + m / 60) * 30;
    final minAngle = (m + s / 60) * 6;
    final secAngle = (s * 6).toDouble();
    final clockSize = size * 0.70;

    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(clockSize, clockSize),
          painter: _AnalogPainter(
            hourAngle: hourAngle,
            minAngle: minAngle,
            secAngle: secAngle,
          ),
        ),
        // Wake hint
        Positioned(
          bottom: size * 0.12,
          left: 0,
          right: 0,
          child: Text(
            context.watch<AppState>().t('screensaver.tap_to_wake'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: size * 0.024,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalogPainter extends CustomPainter {
  final double hourAngle, minAngle, secAngle;
  _AnalogPainter({
    required this.hourAngle,
    required this.minAngle,
    required this.secAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 8;

    // Face
    final facePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), r, facePaint);

    // Ticks
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;
      final inner = i % 3 == 0 ? r - 10 : r - 4;
      canvas.drawLine(
        Offset(cx + inner * math.cos(angle), cy + inner * math.sin(angle)),
        Offset(cx + (r - 12) * math.cos(angle),
            cy + (r - 12) * math.sin(angle)),
        tickPaint,
      );
    }

    // Hour hand
    _drawHand(canvas, cx, cy, hourAngle, r * 0.48, 5, Colors.white);
    // Minute hand
    _drawHand(canvas, cx, cy, minAngle, r * 0.68, 3, Colors.white);
    // Second hand
    _drawHand(canvas, cx, cy, secAngle, r * 0.78, 1.5,
        const Color(0xFF4fc3f7));
    // Second tail
    final secRad = (secAngle - 90) * math.pi / 180;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx - r * 0.1 * math.cos(secRad),
          cy - r * 0.1 * math.sin(secRad)),
      Paint()
        ..color = const Color(0xFF4fc3f7)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Pivot
    canvas.drawCircle(Offset(cx, cy), 4,
        Paint()..color = const Color(0xFF4fc3f7));
  }

  void _drawHand(Canvas canvas, double cx, double cy, double angleDeg,
      double length, double width, Color color) {
    final rad = (angleDeg - 90) * math.pi / 180;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + length * math.cos(rad), cy + length * math.sin(rad)),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalogPainter old) =>
      hourAngle != old.hourAngle ||
      minAngle != old.minAngle ||
      secAngle != old.secAngle;
}

class _DigitalClock extends StatelessWidget {
  final DateTime now;
  final double size;
  const _DigitalClock({required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$h:$m',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.12,
                      fontWeight: FontWeight.w200,
                    )),
                const SizedBox(width: 8),
                Text(s,
                    style: TextStyle(
                      color: const Color(0xFF4fc3f7),
                      fontSize: size * 0.048,
                      fontWeight: FontWeight.w300,
                    )),
              ],
            ),
            SizedBox(height: size * 0.01),
            Text(dateStr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: size * 0.03,
                )),
          ],
        ),
        Positioned(
          bottom: size * 0.12,
          left: 0,
          right: 0,
          child: Text(
            context.watch<AppState>().t('screensaver.tap_to_wake'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: size * 0.024,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Toast Layer
// =============================================================================

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.toastVisible) return const SizedBox.shrink();
    final size = MediaQuery.of(context).size.shortestSide;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: size * 0.08),
        child: AnimatedOpacity(
        opacity: state.toastVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: size * 0.03, vertical: size * 0.015),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            state.t(state.toastMessage),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.026,
            ),
          ),
        ),
      ),
      ),
    );
  }
}
