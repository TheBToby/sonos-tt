import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';

/// Full-screen dimmed overlay with a circular volume slider.
///
/// Shows the current volume as a circular arc with a draggable handle and
/// the numeric value in the center. Auto-hides after 5 seconds of no
/// interaction. Can be triggered by the nav volume button or a 3-finger tap.
class VolumeControlLayer extends StatefulWidget {
  const VolumeControlLayer({super.key});

  @override
  State<VolumeControlLayer> createState() => _VolumeControlLayerState();
}

class _VolumeControlLayerState extends State<VolumeControlLayer> {
  Timer? _autoHideTimer;
  static const _autoHideDuration = Duration(seconds: 5);
  bool _wasVisible = false;

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_autoHideDuration, () {
      if (mounted) {
        context.read<AppState>().hideVolumeControl();
      }
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final size = MediaQuery.of(context).size.shortestSide;
    final visible = state.volumeControlVisible;

    // Detect visibility transitions to start/cancel the timer without
    // resetting on every polling-driven rebuild.
    if (visible && !_wasVisible) {
      // Just became visible — start the auto-hide countdown.
      _resetAutoHideTimer();
    } else if (!visible && _wasVisible) {
      // Just hidden — cancel any pending timer.
      _autoHideTimer?.cancel();
    }
    _wasVisible = visible;

    if (!visible) return const SizedBox.shrink();

    final volume = state.sonos.activeSpeaker?.volume ?? 0;

    return GestureDetector(
      // Any tap resets the auto-hide timer.
      onTapDown: (_) => _resetAutoHideTimer(),
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: _CircularVolumeSlider(
            value: volume,
            radius: size * 0.32,
            strokeWidth: size * 0.04,
            accent: c.accent,
            surface2: c.surface2,
            text: c.text,
            textDim: c.textDim,
            onChanged: (v) {
              state.setVolume(v);
              _resetAutoHideTimer();
            },
            onClose: () => state.hideVolumeControl(),
          ),
        ),
      ),
    );
  }
}

/// A circular slider for volume control.
///
/// Drag anywhere on the ring to change the volume (0–100). The arc fills
/// clockwise from the top (12 o'clock). A handle marks the current position.
class _CircularVolumeSlider extends StatefulWidget {
  final int value;
  final double radius;
  final double strokeWidth;
  final Color accent;
  final Color surface2;
  final Color text;
  final Color textDim;
  final ValueChanged<int> onChanged;
  final VoidCallback onClose;

  const _CircularVolumeSlider({
    required this.value,
    required this.radius,
    required this.strokeWidth,
    required this.accent,
    required this.surface2,
    required this.text,
    required this.textDim,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<_CircularVolumeSlider> createState() => _CircularVolumeSliderState();
}

class _CircularVolumeSliderState extends State<_CircularVolumeSlider> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _CircularVolumeSlider old) {
    super.didUpdateWidget(old);
    // Sync from external changes (e.g. polling refresh) when not dragging.
    if (old.value != widget.value) {
      _value = widget.value;
    }
  }

  void _updateFromPosition(Offset localPos, double cx, double cy) {
    final dx = localPos.dx - cx;
    final dy = localPos.dy - cy;
    // Angle from top (12 o'clock), clockwise.
    var angle = math.atan2(dx, -dy) * 180 / math.pi;
    if (angle < 0) angle += 360;
    final newVolume = (angle / 360 * 100).round().clamp(0, 100);
    if (newVolume != _value) {
      setState(() => _value = newVolume);
      widget.onChanged(newVolume);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;

    return GestureDetector(
      onPanStart: (details) {
        _updateFromPosition(details.localPosition, widget.radius, widget.radius);
      },
      onPanUpdate: (details) {
        _updateFromPosition(details.localPosition, widget.radius, widget.radius);
      },
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(diameter, diameter),
              painter: _CircularVolumePainter(
                value: _value,
                radius: widget.radius,
                strokeWidth: widget.strokeWidth,
                accent: widget.accent,
                trackColor: widget.surface2,
              ),
            ),
            // Volume value with % in center
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Volume value with % sign
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$_value',
                        style: TextStyle(
                          color: widget.text,
                          fontSize: widget.radius * 0.48,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: '%',
                        style: TextStyle(
                          color: widget.textDim,
                          fontSize: widget.radius * 0.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: widget.radius * 0.18),
                // Close button
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    padding: EdgeInsets.all(widget.radius * 0.08),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.surface2.withValues(alpha: 0.8),
                    ),
                    child: Icon(
                      Icons.close,
                      size: widget.radius * 0.16,
                      color: widget.textDim,
                    ),
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

class _CircularVolumePainter extends CustomPainter {
  final int value;
  final double radius;
  final double strokeWidth;
  final Color accent;
  final Color trackColor;

  _CircularVolumePainter({
    required this.value,
    required this.radius,
    required this.strokeWidth,
    required this.accent,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Track (full circle)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Filled arc (from top, clockwise, proportional to value)
    final sweepAngle = (value / 100) * 2 * math.pi;
    if (sweepAngle > 0.01) {
      // Handle value == 0 edge case (don't draw arc)
      // Use 100% if value == 100 for full circle.
      final useSweep = value >= 100 ? 2 * math.pi - 0.001 : sweepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // start at top (12 o'clock)
        useSweep,
        false,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    // Handle (knob at the end of the arc)
    final handleAngle = -math.pi / 2 + sweepAngle;
    final handleX = center.dx + radius * math.cos(handleAngle);
    final handleY = center.dy + radius * math.sin(handleAngle);
    canvas.drawCircle(
      Offset(handleX, handleY),
      strokeWidth * 0.7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(handleX, handleY),
      strokeWidth * 0.7,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularVolumePainter old) =>
      value != old.value || accent != old.accent;
}
