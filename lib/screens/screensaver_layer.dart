import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

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
            cfg.brightness,
            0,
            0,
            0,
            0,
            0,
            cfg.brightness,
            0,
            0,
            0,
            0,
            0,
            cfg.brightness,
            0,
            0,
            0,
            0,
            0,
            1.0,
            0,
          ]),
          child: cfg.mode == 'analog'
              ? AnalogClock(now: _now, size: size)
              : DigitalClock(now: _now, size: size),
        ),
      ),
    );
  }
}

class AnalogClock extends StatelessWidget {
  final DateTime now;
  final double size;
  const AnalogClock({super.key, required this.now, required this.size});

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
          painter: AnalogPainter(
            hourAngle: hourAngle,
            minAngle: minAngle,
            secAngle: secAngle,
          ),
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

class AnalogPainter extends CustomPainter {
  final double hourAngle, minAngle, secAngle;
  AnalogPainter({
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
        Offset(cx + (r - 12) * math.cos(angle), cy + (r - 12) * math.sin(angle)),
        tickPaint,
      );
    }

    // Hour hand
    _drawHand(canvas, cx, cy, hourAngle, r * 0.48, 5, Colors.white);
    // Minute hand
    _drawHand(canvas, cx, cy, minAngle, r * 0.68, 3, Colors.white);
    // Second hand
    _drawHand(canvas, cx, cy, secAngle, r * 0.78, 1.5, const Color(0xFF4fc3f7));
    // Second tail
    final secRad = (secAngle - 90) * math.pi / 180;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx - r * 0.1 * math.cos(secRad), cy - r * 0.1 * math.sin(secRad)),
      Paint()
        ..color = const Color(0xFF4fc3f7)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Pivot
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = const Color(0xFF4fc3f7));
  }

  void _drawHand(Canvas canvas, double cx, double cy, double angleDeg, double length, double width,
      Color color) {
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
  bool shouldRepaint(covariant AnalogPainter old) =>
      hourAngle != old.hourAngle || minAngle != old.minAngle || secAngle != old.secAngle;
}

class DigitalClock extends StatelessWidget {
  final DateTime now;
  final double size;
  const DigitalClock({super.key, required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

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
