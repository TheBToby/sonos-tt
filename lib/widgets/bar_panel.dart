import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Reusable dialog frame with a left sidebar title bar and close button.
///
/// Layout (left to right):
///   [close bar] [vertical title bar] [content]
///
/// The close bar is a dedicated tappable strip to the LEFT of the title bar.
/// It spans the full dialog height with a vertically centered close icon, so
/// it sits within the visible area of the circular display (the old design
/// put the close button in the bottom corner, which was clipped by the circle).
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
              // Close bar (leftmost) — full height, vertically centered icon.
              // Uses surface3 to distinguish it from the title bar.
              _CloseBar(onClose: onClose),
              // Vertical title bar
              Container(
                width: 32,
                color: c.surface2,
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
              // Content area
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable close bar on the far left of the dialog.
///
/// A 36px-wide strip spanning the full dialog height. The close icon is
/// vertically centered so it stays within the visible circle on the
/// circular display. Provides visual press feedback via [Ink].
class _CloseBar extends StatefulWidget {
  final VoidCallback onClose;

  const _CloseBar({required this.onClose});

  @override
  State<_CloseBar> createState() => _CloseBarState();
}

class _CloseBarState extends State<_CloseBar> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onClose,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 36,
        color: _pressed ? c.accent.withValues(alpha: 0.25) : c.surface3,
        alignment: Alignment.center,
        child: Icon(
          Icons.close,
          size: 22,
          color: _pressed ? c.text : c.textDim,
        ),
      ),
    );
  }
}
