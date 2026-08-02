import 'dart:math' as math;

import 'package:flutter/material.dart';

enum GestureType { tap, swipeLeft, swipeRight, swipeUp, swipeDown, doubleTap }

GestureType? detectGesture(DragStartDetails start, DragEndDetails end, Size screenSize) {
  final dx = end.velocity.pixelsPerSecond.dx;
  final dy = end.velocity.pixelsPerSecond.dy;
  final speed = math.sqrt(dx * dx + dy * dy);
  if (speed < 200) return GestureType.tap;
  if (dx.abs() > dy.abs()) {
    return dx < 0 ? GestureType.swipeLeft : GestureType.swipeRight;
  }
  return dy < 0 ? GestureType.swipeUp : GestureType.swipeDown;
}

Path wedgePath(double cx, double cy, double innerR, double outerR, double startDeg, double endDeg) {
  final startRad = (startDeg - 90) * math.pi / 180;
  final endRad = (endDeg - 90) * math.pi / 180;
  return Path()
    ..moveTo(cx + innerR * math.cos(startRad), cy + innerR * math.sin(startRad))
    ..lineTo(cx + outerR * math.cos(startRad), cy + outerR * math.sin(startRad))
    ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: outerR), startRad, endRad - startRad, false)
    ..lineTo(cx + innerR * math.cos(endRad), cy + innerR * math.sin(endRad))
    ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: innerR), endRad, startRad - endRad, false)
    ..close();
}
