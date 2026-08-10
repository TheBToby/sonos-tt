import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';

class ConfigService {
  static const _storageKey = 'sonos-tt:config';

  /// Path to the optional HA secrets file on the Pi, deployed via
  /// deploy/deploy.sh. Contains `haUrl`, `haToken`, `haEntityId`.
  /// Gitignored — never committed to version control.
  static const _secretsPath = '/opt/sonos-tt/ha-secrets.json';

  Future<AppConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      AppConfig config;
      if (raw == null) {
        config = const AppConfig();
      } else {
        final stored = json.decode(raw) as Map<String, dynamic>;
        config = AppConfig.fromJson(stored);
      }
      // Overlay HA secrets from the deployed file if it exists and the user
      // hasn't manually configured HA in the app settings (UI config wins).
      return _mergeSecrets(config);
    } catch (e) {
      print('[config] Failed to load stored config, using defaults. $e');
      return _mergeSecrets(const AppConfig());
    }
  }

  /// Merge HA credentials from the secrets file into the config.
  ///
  /// Values already set in the app config (via settings UI) take precedence
  /// over the secrets file — the secrets file only fills in missing fields.
  /// This allows the secrets file to provide defaults on the Pi while still
  /// letting the user override via the UI.
  AppConfig _mergeSecrets(AppConfig config) {
    try {
      final file = File(_secretsPath);
      if (!file.existsSync()) return config;

      final raw = file.readAsStringSync();
      final secrets = json.decode(raw) as Map<String, dynamic>;
      final ss = config.ui.screensaver;

      final haUrl = (secrets['haUrl'] as String? ?? '').trim();
      final haToken = (secrets['haToken'] as String? ?? '').trim();
      final haEntityId = (secrets['haEntityId'] as String? ?? '').trim();

      // Only apply secrets if they provide values not already configured.
      if (haUrl.isEmpty && haToken.isEmpty && haEntityId.isEmpty) return config;

      final merged = ss.copyWith(
        haUrl: ss.haUrl.isNotEmpty ? ss.haUrl : haUrl,
        haToken: ss.haToken.isNotEmpty ? ss.haToken : haToken,
        haEntityId: ss.haEntityId.isNotEmpty ? ss.haEntityId : haEntityId,
        // Auto-enable HA backlight if secrets are present and not explicitly disabled.
        haBacklightEnabled: ss.haBacklightEnabled ||
            (haUrl.isNotEmpty && haToken.isNotEmpty && haEntityId.isNotEmpty),
      );

      return config.copyWith(
        ui: UiConfig(
          language: config.ui.language,
          theme: config.ui.theme,
          screensaver: merged,
          turntable: config.ui.turntable,
          overlay: config.ui.overlay,
        ),
      );
    } catch (e) {
      print('[config] Failed to load HA secrets from $_secretsPath: $e');
      return config;
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(config.toJson()));
    } catch (e) {
      print('[config] Failed to persist config. $e');
    }
  }
}
