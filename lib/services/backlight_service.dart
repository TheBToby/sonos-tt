import 'dart:io';

/// Controls the Waveshare display backlight brightness via a Python helper
/// script that communicates with the display's USB controller.
///
/// Hardware dimming is an optional enhancement for the screensaver. When
/// enabled, the display's physical backlight is dimmed (saving power and
/// reducing light emission) in addition to the software color-matrix dimming.
///
/// The Python script (`brightness.py`) is deployed to `/opt/sonos-tt/` on the
/// Pi. It requires `python3-usb` and a udev rule for non-root USB access.
///
/// On non-Linux platforms (e.g., macOS dev), all calls are no-ops.
class BacklightService {
  static const _scriptPath = '/opt/sonos-tt/brightness.py';
  static const _dimBrightness = 10; // % during screensaver
  static const _normalBrightness = 100; // % when active

  bool _isDimmed = false;
  bool _available = false;

  /// Whether hardware dimming is supported on this platform.
  /// Only Linux is supported (the Pi runs Linux; macOS dev is a no-op).
  bool get isSupported => Platform.isLinux;

  /// Whether the backlight is currently dimmed.
  bool get isDimmed => _isDimmed;

  /// Check if the brightness script exists and is executable.
  Future<void> init() async {
    if (!isSupported) {
      _available = false;
      return;
    }
    final script = File(_scriptPath);
    _available = await script.exists();
    if (!_available) {
      print('[backlight] Script not found at $_scriptPath — '
          'hardware dimming disabled.');
    }
  }

  /// Dim the backlight to a low level (screensaver mode).
  Future<void> dim() async {
    if (!isSupported || !_available || _isDimmed) return;
    await _setBrightness(_dimBrightness);
    _isDimmed = true;
  }

  /// Restore the backlight to full brightness.
  Future<void> restore() async {
    if (!isSupported || !_available || !_isDimmed) return;
    await _setBrightness(_normalBrightness);
    _isDimmed = false;
  }

  Future<void> _setBrightness(int percent) async {
    try {
      final result = await Process.run(
        'python3',
        [_scriptPath, percent.toString()],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        // Non-fatal — hardware dimming is best-effort.
        if (result.stderr.toString().isNotEmpty) {
          print('[backlight] stderr: ${result.stderr}');
        }
      }
    } catch (e) {
      // Non-fatal — the display may not be connected, pyusb may be missing,
      // or the script may not be deployed yet.
      print('[backlight] Failed to set brightness: $e');
    }
  }
}
