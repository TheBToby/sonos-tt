import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../widgets/utils.dart';

class NavLayer extends StatelessWidget {
  const NavLayer({super.key});

  // Matches Svelte order: volume, next, queue, settings, prev, speakers
  static const _segments = [
    NavSeg(icon: Icons.volume_up, label: 'volume'),
    NavSeg(icon: Icons.skip_next, label: 'next'),
    NavSeg(icon: Icons.queue_music, label: 'queue'),
    NavSeg(icon: Icons.settings, label: 'settings'),
    NavSeg(icon: Icons.skip_previous, label: 'prev'),
    NavSeg(icon: Icons.speaker, label: 'speakers'),
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
    const gap = 2.0;

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
            painter: RadialNavPainter(
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
              colors: NavColors(
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

class NavSeg {
  final IconData icon;
  final String label;
  const NavSeg({required this.icon, required this.label});
}

class NavColors {
  final Color glass, surface, surface2, accent, text, scrim, glassBorder;
  const NavColors({
    required this.glass,
    required this.surface,
    required this.surface2,
    required this.accent,
    required this.text,
    required this.scrim,
    required this.glassBorder,
  });
}

class RadialNavPainter extends CustomPainter {
  final double cx, cy, innerR, outerR, centerR, segAngle, gap;
  final List<NavSeg> segments;
  final bool navVisible, isPlaying;
  final String? volumeMode;
  final NavColors colors;

  RadialNavPainter({
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
      Paint()..color = colors.surface.withValues(alpha: navVisible ? 1.0 : 0.5),
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
      text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
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
  bool shouldRepaint(covariant RadialNavPainter old) =>
      navVisible != old.navVisible || isPlaying != old.isPlaying || volumeMode != old.volumeMode;
}
