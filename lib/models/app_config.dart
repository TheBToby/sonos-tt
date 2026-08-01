/// Application configuration model with defaults and serialization.
library;

class SpotifyAccount {
  final String id;
  final String label;
  final String color;

  const SpotifyAccount({
    required this.id,
    required this.label,
    this.color = '#4fc3f7',
  });

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'color': color};

  factory SpotifyAccount.fromJson(Map<String, dynamic> json) =>
      SpotifyAccount(
        id: json['id'] as String,
        label: json['label'] as String,
        color: json['color'] as String? ?? '#4fc3f7',
      );
}

class ScreensaverConfig {
  final bool enabled;
  final int timeout; // seconds
  final String mode; // 'analog' | 'digital'
  final double brightness; // 0..1

  const ScreensaverConfig({
    this.enabled = true,
    this.timeout = 30,
    this.mode = 'analog',
    this.brightness = 0.18,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'timeout': timeout,
        'mode': mode,
        'brightness': brightness,
      };

  factory ScreensaverConfig.fromJson(Map<String, dynamic> json) =>
      ScreensaverConfig(
        enabled: json['enabled'] as bool? ?? true,
        timeout: json['timeout'] as int? ?? 30,
        mode: json['mode'] as String? ?? 'analog',
        brightness: (json['brightness'] as num?)?.toDouble() ?? 0.18,
      );
}

class TurntableConfig {
  final int spinDuration; // seconds per revolution
  final bool preloadArtwork;

  const TurntableConfig({
    this.spinDuration = 6,
    this.preloadArtwork = true,
  });

  Map<String, dynamic> toJson() => {
        'spinDuration': spinDuration,
        'preloadArtwork': preloadArtwork,
      };

  factory TurntableConfig.fromJson(Map<String, dynamic> json) => TurntableConfig(
        spinDuration: json['spinDuration'] as int? ?? 6,
        preloadArtwork: json['preloadArtwork'] as bool? ?? true,
      );
}

class UiConfig {
  final String language;
  final String theme; // 'auto' | 'dark' | 'light'
  final ScreensaverConfig screensaver;
  final TurntableConfig turntable;
  final bool overlay;

  const UiConfig({
    this.language = 'de',
    this.theme = 'auto',
    this.screensaver = const ScreensaverConfig(),
    this.turntable = const TurntableConfig(),
    this.overlay = true,
  });

  Map<String, dynamic> toJson() => {
        'language': language,
        'theme': theme,
        'screensaver': screensaver.toJson(),
        'turntable': turntable.toJson(),
        'overlay': overlay,
      };

  factory UiConfig.fromJson(Map<String, dynamic> json) => UiConfig(
        language: json['language'] as String? ?? 'de',
        theme: json['theme'] as String? ?? 'auto',
        screensaver: json['screensaver'] != null
            ? ScreensaverConfig.fromJson(json['screensaver'] as Map<String, dynamic>)
            : const ScreensaverConfig(),
        turntable: json['turntable'] != null
            ? TurntableConfig.fromJson(json['turntable'] as Map<String, dynamic>)
            : const TurntableConfig(),
        overlay: json['overlay'] as bool? ?? true,
      );
}

class SocoApiConfig {
  final String baseUrl;
  final int pollInterval; // ms
  final int timeout; // ms per request

  const SocoApiConfig({
    this.baseUrl = 'http://localhost:5001',
    this.pollInterval = 2000,
    this.timeout = 4000,
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'pollInterval': pollInterval,
        'timeout': timeout,
      };

  factory SocoApiConfig.fromJson(Map<String, dynamic> json) => SocoApiConfig(
        baseUrl: json['baseUrl'] as String? ?? 'http://localhost:5001',
        pollInterval: json['pollInterval'] as int? ?? 2000,
        timeout: json['timeout'] as int? ?? 4000,
      );

  SocoApiConfig copyWith({String? baseUrl, int? pollInterval, int? timeout}) =>
      SocoApiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        pollInterval: pollInterval ?? this.pollInterval,
        timeout: timeout ?? this.timeout,
      );
}

class SpotifyConfig {
  final List<SpotifyAccount> accounts;
  final String defaultAccount;

  const SpotifyConfig({
    this.accounts = const [],
    this.defaultAccount = 'tobias',
  });

  Map<String, dynamic> toJson() => {
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'defaultAccount': defaultAccount,
      };

  factory SpotifyConfig.fromJson(Map<String, dynamic> json) => SpotifyConfig(
        accounts: (json['accounts'] as List<dynamic>?)
                ?.map((a) => SpotifyAccount.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [
              SpotifyAccount(id: 'tobias', label: 'Tobias', color: '#4fc3f7'),
              SpotifyAccount(id: 'lena', label: 'Lena', color: '#f06292'),
              SpotifyAccount(id: 'max', label: 'Max', color: '#81c784'),
              SpotifyAccount(id: 'emma', label: 'Emma', color: '#ffb74d'),
              SpotifyAccount(id: 'guest', label: 'Gast', color: '#9575cd'),
            ],
        defaultAccount: json['defaultAccount'] as String? ?? 'tobias',
      );
}

class AppConfig {
  static const defaultAccounts = [
    SpotifyAccount(id: 'tobias', label: 'Tobias', color: '#4fc3f7'),
    SpotifyAccount(id: 'lena', label: 'Lena', color: '#f06292'),
    SpotifyAccount(id: 'max', label: 'Max', color: '#81c784'),
    SpotifyAccount(id: 'emma', label: 'Emma', color: '#ffb74d'),
    SpotifyAccount(id: 'guest', label: 'Gast', color: '#9575cd'),
  ];

  final SocoApiConfig socoApi;
  final SpotifyConfig spotify;
  final UiConfig ui;
  final int version;

  static const int configVersion = 3;

  const AppConfig({
    this.socoApi = const SocoApiConfig(),
    this.spotify = const SpotifyConfig(),
    this.ui = const UiConfig(),
    this.version = configVersion,
  });

  static const defaultConfig = AppConfig();

  Map<String, dynamic> toJson() => {
        'socoApi': socoApi.toJson(),
        'spotify': spotify.toJson(),
        'ui': ui.toJson(),
        '_version': version,
      };

  AppConfig copyWith({
    SocoApiConfig? socoApi,
    SpotifyConfig? spotify,
    UiConfig? ui,
    int? version,
  }) =>
      AppConfig(
        socoApi: socoApi ?? this.socoApi,
        spotify: spotify ?? this.spotify,
        ui: ui ?? this.ui,
        version: version ?? this.version,
      );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final storedVersion = json['_version'] as int? ?? 0;
    final needsMigration = storedVersion < configVersion;

    return AppConfig(
      socoApi: needsMigration
          ? const SocoApiConfig()
          : (json['socoApi'] != null
              ? SocoApiConfig.fromJson(json['socoApi'] as Map<String, dynamic>)
              : const SocoApiConfig()),
      spotify: json['spotify'] != null
          ? SpotifyConfig.fromJson(json['spotify'] as Map<String, dynamic>)
          : const SpotifyConfig(accounts: defaultAccounts),
      ui: json['ui'] != null
          ? UiConfig.fromJson(json['ui'] as Map<String, dynamic>)
          : const UiConfig(),
      version: configVersion,
    );
  }
}