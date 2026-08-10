import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'app_theme.dart';
import 'screens/dialog_layer.dart';
import 'screens/nav_layer.dart';
import 'screens/screensaver_layer.dart';
import 'screens/toast_layer.dart';
import 'screens/turntable_screen.dart';
import 'screens/volume_control_layer.dart';

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
  final _activePointers = <int>{};

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
      if (elapsed >= cfg.ui.screensaver.timeout && state.view != AppView.screensaver) {
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

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _onInteraction();
    // 3-finger touch anywhere shows the volume control overlay.
    if (_activePointers.length >= 3) {
      context.read<AppState>().showVolumeControl();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
  }

  @override
  void dispose() {
    _screensaverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.shortestSide;
    // Force the area outside the circular display to be black so the
    // anti-aliased edge of ClipOval never blends with a theme-colored
    // (e.g. white) background, which showed up as a thin ring on the
    // Raspberry Pi display.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              onPointerCancel: (e) => _activePointers.remove(e.pointer),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _onInteraction(),
                onPanStart: (_) => _onInteraction(),
                child: const Stack(
                  children: [
                    TurntableLayer(),
                    NavLayer(),
                    VolumeControlLayer(),
                    DialogLayer(),
                    ScreensaverLayer(),
                    ToastLayer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
