/// Lightweight i18n with German (default) and English.
library;

class Language {
  final String code;
  final String label;
  const Language({required this.code, required this.label});
}

const languages = [
  Language(code: 'de', label: 'Deutsch'),
  Language(code: 'en', label: 'English'),
];

const Map<String, Map<String, String>> strings = {
  'de': {
    'app.title': 'Sonos Plattenspieler',
    'nav.speakers': 'Lautsprecher',
    'nav.playlists': 'Playlists',
    'nav.users': 'Benutzer',
    'nav.settings': 'Einstellungen',
    'nav.close': 'Schließen',
    'playback.play': 'Wiedergabe',
    'playback.pause': 'Pause',
    'playback.next': 'Weiter',
    'playback.previous': 'Zurück',
    'playback.volume': 'Lautstärke',
    'playback.nothing_playing': 'Nichts läuft',
    'playback.unknown': 'Unbekannter Titel',
    'users.title': 'Spotify-Benutzer',
    'users.switch': 'Wechseln zu',
    'users.current': 'Aktuell',
    'users.add_account': 'Bei SoCo-CLI anmelden, um Konto hinzuzufügen',
    'speakers.title': 'Lautsprecher',
    'speakers.group': 'Gruppieren',
    'speakers.ungroup': 'Gruppe auflösen',
    'speakers.grouped_with': 'Gruppiert mit',
    'speakers.none_found': 'Keine Lautsprecher gefunden',
    'playlists.title': 'Playlists',
    'playlists.empty': 'Keine Playlists verfügbar',
    'playlists.queue': 'Warteschlange',
    'settings.title': 'Einstellungen',
    'settings.language': 'Sprache',
    'settings.theme': 'Design',
    'settings.theme.auto': 'System',
    'settings.theme.dark': 'Dunkel',
    'settings.theme.light': 'Hell',
    'settings.screensaver': 'Bildschirmschoner',
    'settings.screensaver.timeout': 'Timeout (Sekunden)',
    'settings.screensaver.mode': 'Uhr-Modus',
    'settings.screensaver.mode.analog': 'Analog',
    'settings.screensaver.mode.digital': 'Digital',
    'settings.screensaver.brightness': 'Helligkeit',
    'settings.screensaver.enabled': 'Aktiviert',
    'settings.turntable': 'Plattenspieler',
    'settings.turntable.spin': 'Umlaufzeit (Sekunden)',
    'settings.api': 'SoCo-CLI API',
    'settings.api.baseUrl': 'Server-URL',
    'settings.api.status': 'Status',
    'settings.api.status.connected': 'Verbunden',
    'settings.api.status.disconnected': 'Getrennt',
    'settings.reset': 'Auf Standard zurücksetzen',
    'settings.save': 'Speichern',
    'connection.error': 'Verbindung zum SoCo-CLI Server fehlgeschlagen',
    'connection.retrying': 'Erneuter Versuch…',
    'connection.mock_title': 'Demo-Modus',
    'connection.mock_text':
        'SoCo-CLI Server nicht erreichbar. Bitte starten Sie „soco-cli http-server --host 0.0.0.0 --port 5001" und prüfen Sie die URL in den Einstellungen.',
    'connection.retry': 'Erneut versuchen',
    'gestures.hint':
        'Tippen: Play/Pause · Wischen: Titel/Lautstärke · Doppeltipp: Menü',
    'screensaver.tap_to_wake': 'Tippen zum Aufwecken',
  },
  'en': {
    'app.title': 'Sonos Turntable',
    'nav.speakers': 'Speakers',
    'nav.playlists': 'Playlists',
    'nav.users': 'Users',
    'nav.settings': 'Settings',
    'nav.close': 'Close',
    'playback.play': 'Play',
    'playback.pause': 'Pause',
    'playback.next': 'Next',
    'playback.previous': 'Previous',
    'playback.volume': 'Volume',
    'playback.nothing_playing': 'Nothing playing',
    'playback.unknown': 'Unknown track',
    'users.title': 'Spotify Users',
    'users.switch': 'Switch to',
    'users.current': 'Current',
    'users.add_account': 'Log in via SoCo-CLI to add an account',
    'speakers.title': 'Speakers',
    'speakers.group': 'Group',
    'speakers.ungroup': 'Ungroup',
    'speakers.grouped_with': 'Grouped with',
    'speakers.none_found': 'No speakers found',
    'playlists.title': 'Playlists',
    'playlists.empty': 'No playlists available',
    'playlists.queue': 'Queue',
    'settings.title': 'Settings',
    'settings.language': 'Language',
    'settings.theme': 'Theme',
    'settings.theme.auto': 'System',
    'settings.theme.dark': 'Dark',
    'settings.theme.light': 'Light',
    'settings.screensaver': 'Screensaver',
    'settings.screensaver.timeout': 'Timeout (seconds)',
    'settings.screensaver.mode': 'Clock mode',
    'settings.screensaver.mode.analog': 'Analog',
    'settings.screensaver.mode.digital': 'Digital',
    'settings.screensaver.brightness': 'Brightness',
    'settings.screensaver.enabled': 'Enabled',
    'settings.turntable': 'Turntable',
    'settings.turntable.spin': 'Spin duration (seconds)',
    'settings.api': 'SoCo-CLI API',
    'settings.api.baseUrl': 'Server URL',
    'settings.api.status': 'Status',
    'settings.api.status.connected': 'Connected',
    'settings.api.status.disconnected': 'Disconnected',
    'settings.reset': 'Reset to defaults',
    'settings.save': 'Save',
    'connection.error': 'Failed to connect to SoCo-CLI server',
    'connection.retrying': 'Retrying…',
    'connection.mock_title': 'Demo Mode',
    'connection.mock_text':
        'SoCo-CLI server unreachable. Please run "soco-cli http-server --host 0.0.0.0 --port 5001" and check the URL in Settings.',
    'connection.retry': 'Retry',
    'gestures.hint':
        'Tap: Play/Pause · Swipe: Track/Volume · Double-tap: Menu',
    'screensaver.tap_to_wake': 'Tap to wake',
  },
};

/// Translate a key in the given language, with optional variable substitution.
/// Missing keys fall back to German, then to the key itself.
String t(String lang, String key, [Map<String, String>? vars]) {
  final dict = strings[lang] ?? strings['de']!;
  var str = dict[key] ?? strings['de']![key] ?? key;
  if (vars != null) {
    for (final entry in vars.entries) {
      str = str.replaceAll('{${entry.key}}', entry.value);
    }
  }
  return str;
}