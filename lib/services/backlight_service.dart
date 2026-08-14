import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Controls the Waveshare display backlight brightness via a Python helper
/// script that communicates with the display's USB controller.
///
/// Hardware dimming is an optional enhancement for the screensaver. When
/// enabled, the display's physical backlight is dimmed (saving power and
/// reducing light emission) in addition to the software color-matrix dimming.
///
/// The Python script (`brightness.py`) is deployed to `/opt/sonos-tt/` on the
/// Pi. It communicates via hidraw (NOT pyusb) to avoid disrupting the
/// touchscreen on the composite USB device.
///
/// On non-Linux platforms (e.g., macOS dev) and on web, all calls are no-ops.
/// (kIsWeb guards prevent dart:io Platform/File/Process from being touched
/// in the browser, where they throw UnsupportedError.)
class BacklightService {
  static const _scriptPath = '/opt/sonos-tt/brightness.py';
  static const _dimBrightness = 10; // % during screensaver
  static const _normalBrightness = 100; // % when active
  static const _debounceDelay = Duration(milliseconds: 300);

  bool _isDimmed = false;
  bool _isOff = false;
  int _currentPercent = _normalBrightness;
  bool _available = false;

  // Debounce: coalesce rapid brightness changes into a single process call.
  // When HA sends multiple state events in quick succession (e.g., brightness
  // slider drag), this prevents spawning many python3 processes that fight
  // over the USB device and potentially corrupt the touchscreen.
  Timer? _debounceTimer;
  Completer<void>? _debounceCompleter;
  int _pendingPercent = _normalBrightness;

  /// Whether hardware dimming is supported on this platform.
  /// Only Linux is supported (the Pi runs Linux; macOS dev and web are no-ops).
  bool get isSupported => !kIsWeb && Platform.isLinux;

  /// Whether the brightness script was found during init.
  bool get isAvailable => _available;

  /// Whether the backlight is currently dimmed (or off) by this service.
  bool get isDimmed => _isDimmed;

  /// Whether the backlight is currently turned off entirely.
  bool get isOff => _isOff;

  /// The last brightness percent applied to the backlight.
  int get currentPercent => _currentPercent;

  /// Check if the brightness script exists and is executable.
  Future<void> init() async {
    if (!isSupported) {
      _available = false;
      print('[backlight] Not supported on this platform (web or non-Linux).');
      return;
    }
    final script = File(_scriptPath);
    _available = await script.exists();
    print('[backlight] init: supported=true, available=$_available, script=$_scriptPath');
    if (!_available) {
      print('[backlight] Script not found at $_scriptPath — '
          'hardware dimming disabled.');
    }
  }

  /// Dim the backlight to a low level (screensaver mode).
  Future<void> dim() async {
    if (!isSupported || !_available) return;
    // Set flags BEFORE the async call to prevent race conditions with
    // restore() — if a touch wakes the screen during the Process.run gap,
    // restore() must see _isDimmed == true.
    _isDimmed = true;
    _isOff = false;
    await _setBrightness(_dimBrightness);
  }

  /// Turn the backlight off entirely (0%).
  ///
  /// Used when the Home Assistant light entity is off during screensaver mode.
  Future<void> off() async {
    if (!isSupported || !_available) return;
    _isDimmed = true;
    _isOff = true;
    await _setBrightness(0);
  }

  /// Set the backlight to an explicit brightness percentage (0–100).
  ///
  /// Used when linking the screensaver backlight to a Home Assistant light
  /// entity whose brightness drives the display. Debounced to coalesce rapid
  /// state changes from HA into a single USB write.
  Future<void> setBrightness(int percent) async {
    if (!isSupported || !_available) return;
    final clamped = percent.clamp(0, 100);
    _currentPercent = clamped;
    _isDimmed = clamped < _normalBrightness;
    _isOff = clamped == 0;
    await _setBrightnessDebounced(clamped);
  }

  /// Restore the backlight to full brightness.
  ///
  /// Called when exiting the screensaver (user touched the screen). Always
  /// executes immediately (no debounce) and cancels any pending debounced
  /// call — waking the display is a critical operation that must not be
  /// delayed or skipped.
  Future<void> restore() async {
    if (!isSupported || !_available) return;
    // Cancel any pending debounced brightness change.
    _debounceTimer?.cancel();
    _debounceCompleter?.complete();
    _debounceCompleter = null;
    _isDimmed = false;
    _isOff = false;
    await _setBrightness(_normalBrightness);
  }

  /// Set brightness immediately (no debounce). Used by dim(), off(), and
  /// restore() — operations that should take effect immediately.
  Future<void> _setBrightness(int percent) async {
    _currentPercent = percent;
    try {
      final result = await Process.run(
        'python3',
        [_scriptPath, percent.toString()],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        // Non-fatal — hardware dimming is best-effort.
        final stderr = result.stderr.toString().trim();
        if (stderr.isNotEmpty) {
          print('[backlight] Failed to set $percent%: $stderr');
        }
      }
    } catch (e) {
      // Non-fatal — the display may not be connected or the script may not
      // be deployed yet.
      print('[backlight] Failed to set brightness: $e');
    }
  }

  /// Set brightness with debouncing. Coalesces rapid successive calls into
  /// a single process invocation to avoid USB contention.
  ///
  /// Used by setBrightness() for HA-driven updates which can fire rapidly.
  Future<void> _setBrightnessDebounced(int percent) async {
    // If there's already a debounced call pending, update the target value
    // and wait for the same completer.
    if (_debounceCompleter != null) {
      _pendingPercent = percent;
      return _debounceCompleter!.future;
    }

    // Start a new debounced call.
    _pendingPercent = percent;
    _debounceCompleter = Completer<void>();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () async {
      final target = _pendingPercent;
      await _setBrightness(target);
      final c = _debounceCompleter;
      _debounceCompleter = null;
      c?.complete();
    });

    return _debounceCompleter!.future;
  }

  /// Cancel any pending debounce timer. Called on dispose.
  void dispose() {
    _debounceTimer?.cancel();
    _debounceCompleter?.complete();
    _debounceCompleter = null;
  }
}