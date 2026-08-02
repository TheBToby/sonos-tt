import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Reusable dialog frame with a left sidebar title bar and close button.
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
                      onTap: onClose,
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
              // Content area
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
