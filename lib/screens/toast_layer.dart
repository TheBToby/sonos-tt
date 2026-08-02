import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

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
            padding: EdgeInsets.symmetric(horizontal: size * 0.03, vertical: size * 0.015),
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
