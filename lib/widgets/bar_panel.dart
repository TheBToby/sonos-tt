import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Full-screen dialog frame with a left close area, vertical title bar, and content.
///
/// Layout (left to right):
///   [close area] [vertical title bar] [content]
///
/// Design decisions for the circular display:
/// - **Full-screen**: No rounded borders, shadows, or margin. The dialog fills
///   the full screen but the content area keeps its original size/position so
///   it stays within the visible circle.
/// - **Close area**: A proportional area on the left edge with a generously
///   sized back icon and "BACK" label, vertically centered for guaranteed
///   visibility on the circle.
/// - **Back icon**: Uses `Icons.arrow_back` (a left-pointing arrow) instead of
///   an X, following Material design patterns for returning to the previous
///   screen.
class BarPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;

  const BarPanel({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.of(context).size.shortestSide;

    // Content area dimensions — kept the same to preserve visibility on the
    // circular display.
    final contentWidth = size * 0.68;
    final contentHeight = size * 0.72;

    // Title bar — doubled in width for a bolder, more prominent look.
    final titleBarWidth = size * 0.07; // ≈ 76px on a 1080px screen

    // Close area — reduced by 60% from the full remaining width.
    // (Full width would be ~size * 0.25; 40% of that is ~size * 0.10.)
    final closeAreaWidth = (size - contentWidth - titleBarWidth) * 0.4;

    return Container(
      width: size,
      height: size,
      color: c.bg,
      child: Stack(
        children: [
          // ─── Close area (left edge → title bar) ───────────────────────────
          // Full height, back icon vertically centered. This position is at
          // roughly 1/6 of the screen width — well within the visible circle.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: closeAreaWidth,
            child: _CloseArea(onClose: onClose, size: size),
          ),
          // ─── Vertical title bar ───────────────────────────────────────────
          Positioned(
            left: closeAreaWidth,
            top: 0,
            bottom: 0,
            width: titleBarWidth,
            child: Container(
              color: c.surface2,
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: c.accent,
                      fontSize: size * 0.026,
                      fontWeight: FontWeight.w700,
                      letterSpacing: size * 0.005,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ─── Content area ─────────────────────────────────────────────────
          // Positioned to the right of the title bar, vertically centered.
          // Panels handle their own scrolling; the content height is preserved
          // so visibility on the circular display is guaranteed.
          Positioned(
            left: closeAreaWidth + titleBarWidth,
            top: (size - contentHeight) / 2,
            width: contentWidth,
            height: contentHeight,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Tappable close area with a back icon and label.
///
/// Uses `Icons.arrow_back` (a back arrow) instead of a close X, following
/// Material Design's navigation patterns for returning to the parent screen.
/// The icon is vertically centered and provides press-feedback animation.
class _CloseArea extends StatefulWidget {
  final VoidCallback onClose;
  final double size;

  const _CloseArea({required this.onClose, required this.size});

  @override
  State<_CloseArea> createState() => _CloseAreaState();
}

class _CloseAreaState extends State<_CloseArea> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.size;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _pressed ? c.accent.withValues(alpha: 0.2) : Colors.transparent,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back,
              size: s * 0.05,
              color: _pressed ? c.accent : c.textDim,
            ),
            SizedBox(height: s * 0.008),
            Text(
              'BACK',
              style: TextStyle(
                color: _pressed ? c.accent : c.textFaint,
                fontSize: s * 0.016,
                fontWeight: FontWeight.w600,
                letterSpacing: s * 0.0025,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
