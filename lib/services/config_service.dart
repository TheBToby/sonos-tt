import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';

class ConfigService {
  static const _storageKey = 'sonos-tt:config';

  Future<AppConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return const AppConfig();
      final stored = json.decode(raw) as Map<String, dynamic>;
      return AppConfig.fromJson(stored);
    } catch (e) {
      print('[config] Failed to load stored config, using defaults. $e');
      return const AppConfig();
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