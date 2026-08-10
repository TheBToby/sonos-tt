import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../services/artwork_cache.dart';
import '../widgets/artwork_provider.dart';

class TurntableLayer extends StatefulWidget {
  const TurntableLayer({super.key});
  @override
  State<TurntableLayer> createState() => _TurntableLayerState();
}

class _TurntableLayerState extends State<TurntableLayer> {
  DateTime? _lastTap;
  Offset? _dragStart;
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
    // Single tap: delay to wait for possible double-tap.
    _lastTap = now;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 360), () {
      // No action on single tap (reserved for double-tap detection only)
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
            // ──────────────────────────────────────────────────────────────
            // Rotating vinyl disc.
            //
            // Self-contained rendering via CustomPaint. The disc owns its
            // own Ticker and renders the artwork + grooves directly on a
            // GPU-accelerated canvas. No setState() is called during
            // rotation — a ValueNotifier drives repainting through
            // CustomPaint's `repaint` parameter.
            //
            // The surrounding RepaintBoundary ensures only this layer
            // repaints during rotation. Static elements (text bars, center
            // button, etc.) are never touched by the per-frame animation.
            // ──────────────────────────────────────────────────────────────
            _TurntableDisc(
              artworkUrl: pb.artworkUrl,
              artworkCache: state.artworkCache,
              isPlaying: pb.isPlaying,
              spinDuration: state.config.ui.turntable.spinDuration.toDouble(),
              size: size,
              bgIconColor: c.textDim,
            ),

            // ──────────────────────────────────────────────────────────────
            // Static overlay elements — isolated in their own RepaintBoundary
            // so they NEVER repaint during rotation. They only rebuild when
            // AppState changes (track change, play/pause toggle, etc.).
            // ──────────────────────────────────────────────────────────────
            RepaintBoundary(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Center play/pause button (the "spindle")
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        final state = context.read<AppState>();
                        if (!state.navVisible) {
                          state.togglePlayPause();
                        }
                      },
                      child: Container(
                        width: size * 0.18,
                        height: size * 0.18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.85),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.15),
                              blurRadius: 8,
                              spreadRadius: -2,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          pb.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: size * 0.08,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),

                  // Speaker name at top — moved up 5% for vertical balance
                  if (state.sonos.activeSpeaker?.name.isNotEmpty ?? false)
                    Positioned(
                      top: size * 0.20,
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

                  // Track info at bottom — symmetric with speaker bar
                  Positioned(
                    bottom: size * 0.17,
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: size * 0.028, color: Colors.orange),
                                SizedBox(width: size * 0.008),
                                Text(
                                  state.t('connection.mock_title'),
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: size * 0.022,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh, size: size * 0.022, color: Colors.orange),
                                    SizedBox(width: size * 0.008),
                                    Text(
                                      state.t('connection.retry'),
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: size * 0.019,
                                      ),
                                    ),
                                  ],
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
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _TurntableDisc — Self-contained rotating disc widget
// =============================================================================
//
// Performance architecture (addresses stuttering on Raspberry Pi):
//
// 1. **CustomPaint instead of Transform.rotate + Image widget**
//    The artwork is drawn rotated directly on a GPU-accelerated canvas via
//    `canvas.rotate()` + `canvas.drawImageRect()`. This avoids widget
//    creation, layout, and diffing on every frame.
//
// 2. **ValueNotifier drives repainting (no setState during rotation)**
//    The Ticker updates a ValueNotifier<double> each frame. The CustomPaint's
//    `repaint` parameter listens to this notifier and triggers a canvas
//    repaint WITHOUT rebuilding the widget tree. setState() is only called
//    when the artwork image changes (track change), which is infrequent.
//
// 3. **RepaintBoundary isolates the disc**
//    Only the disc's layer is repainted during rotation. Static elements
//    (text bars, center button) are in a separate RepaintBoundary and are
//    never touched by the animation.
//
// 4. **Pre-scaled artwork images (Option 3)**
//    Images are decoded at the exact display size (e.g. 1080×1080) using
//    Flutter's ResizeImage wrapper. This eliminates per-frame GPU scaling
//    during rotation.
//
// 5. **Merged grooves into the same painter**
//    The vinyl grooves are drawn in the same CustomPaint pass (after the
//    artwork), eliminating a separate paint layer.
// =============================================================================

class _TurntableDisc extends StatefulWidget {
  final String artworkUrl;
  final ArtworkCache artworkCache;
  final bool isPlaying;
  final double spinDuration; // seconds for full 360° rotation
  final double size;
  final Color bgIconColor;

  const _TurntableDisc({
    required this.artworkUrl,
    required this.artworkCache,
    required this.isPlaying,
    required this.spinDuration,
    required this.size,
    required this.bgIconColor,
  });

  @override
  State<_TurntableDisc> createState() => _TurntableDiscState();
}

class _TurntableDiscState extends State<_TurntableDisc> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;

  /// Drives repainting via CustomPaint's `repaint` parameter.
  /// The Ticker updates this value; CustomPaint repaints without any
  /// widget rebuild.
  final _rotationNotifier = ValueNotifier<double>(0.0);
  double _currentSpeed = 0;

  static const _accelDuration = 1.5; // seconds

  /// Resolved artwork image (pre-scaled to display size for GPU efficiency).
  ui.Image? _artworkImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _ticker.start();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(_TurntableDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkUrl != widget.artworkUrl) {
      _loadArtwork();
    }
  }

  void _cancelImageLoad() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  void _loadArtwork() {
    _cancelImageLoad();

    if (widget.artworkUrl.isEmpty) {
      // No artwork — clear image and rebuild to show fallback icon
      if (_artworkImage != null) {
        final old = _artworkImage;
        _artworkImage = null;
        if (mounted) setState(() {});
        old?.dispose();
      }
      return;
    }

    // Pre-scale the image to the exact display size (Option 3).
    // ResizeImage decodes the image at the specified dimensions, eliminating
    // per-frame GPU scaling during rotation.
    final targetSize = widget.size.round();
    final baseProvider = ArtworkImageProvider(widget.artworkUrl, widget.artworkCache);
    final provider = ResizeImage(baseProvider, width: targetSize, height: targetSize);

    final stream = provider.resolve(const ImageConfiguration());
    _imageStream = stream;

    _imageListener = ImageStreamListener((info, _) {
      if (mounted) {
        final newImage = info.image.clone();
        final oldImage = _artworkImage;
        setState(() {
          _artworkImage = newImage;
        });
        // Dispose old image after the frame to ensure no painter references it
        if (oldImage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            oldImage.dispose();
          });
        }
      }
    }, onError: (error, stack) {
      debugPrint('Error loading artwork: $error');
    });

    stream.addListener(_imageListener!);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    // Ticker provides cumulative time since start; compute delta between frames
    final dt = _lastElapsed == null
        ? elapsed.inMicroseconds / 1000000.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    final maxSpeed = 360.0 / widget.spinDuration;
    final target = widget.isPlaying ? maxSpeed : 0.0;
    final rate = maxSpeed / _accelDuration;

    if (_currentSpeed < target) {
      _currentSpeed =
          (target - _currentSpeed).abs() < rate * dt ? target : _currentSpeed + rate * dt;
    } else if (_currentSpeed > target) {
      _currentSpeed =
          (target - _currentSpeed).abs() < rate * dt ? target : _currentSpeed - rate * dt;
    }

    // Update the notifier — triggers CustomPaint repaint, NOT a widget rebuild
    _rotationNotifier.value = (_rotationNotifier.value + _currentSpeed * dt) % 360;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _cancelImageLoad();
    _artworkImage?.dispose();
    _rotationNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: TurntableDiscPainter(
          image: _artworkImage,
          rotationListenable: _rotationNotifier,
          bgIconColor: widget.bgIconColor,
          iconSize: widget.size * 0.15,
        ),
      ),
    );
  }
}

// =============================================================================
// TurntableDiscPainter — Draws the rotating artwork + vinyl grooves on canvas
// =============================================================================

class TurntableDiscPainter extends CustomPainter {
  final ui.Image? image;
  final ValueListenable<double> rotationListenable;
  final Color bgIconColor;
  final double iconSize;

  TurntableDiscPainter({
    required this.image,
    required this.rotationListenable,
    required this.bgIconColor,
    required this.iconSize,
  }) : super(repaint: rotationListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Clip to circle so artwork stays within the disc
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ),
    );

    // Background fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1a1a1a),
    );

    // Draw rotated artwork
    if (image != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      // Read the current rotation value at paint time — always up-to-date
      canvas.rotate(rotationListenable.value * math.pi / 180.0);

      // Draw image covering the full disc, with 70% opacity modulation
      // (replicates the original Image widget's color + BlendMode.modulate)
      final src = Rect.fromLTWH(
        0,
        0,
        image!.width.toDouble(),
        image!.height.toDouble(),
      );
      final dst = Rect.fromCenter(
        center: Offset.zero,
        width: size.width,
        height: size.height,
      );
      canvas.drawImageRect(
        image!,
        src,
        dst,
        Paint()
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: 0.7),
            BlendMode.modulate,
          ),
      );
      canvas.restore();
    } else {
      // Fallback: draw music note icon via TextPainter
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.music_note.codePoint),
          style: TextStyle(
            fontSize: iconSize,
            color: bgIconColor,
            fontFamily: 'MaterialIcons',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
      );
    }

    // Draw vinyl grooves (concentric circles, NOT rotated — radially symmetric)
    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final minR = radius * 0.36;
    const ringCount = 40;
    for (var i = 0; i < ringCount; i++) {
      final r = minR + (radius - minR) * (i / ringCount);
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant TurntableDiscPainter old) =>
      image != old.image || bgIconColor != old.bgIconColor || iconSize != old.iconSize;
}
