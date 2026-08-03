import 'package:flutter/material.dart';

import 'models/app_config.dart';
import 'models/sonos_models.dart';
import 'repositories/sonos_repository.dart';
import 'services/artwork_cache.dart';
import 'services/config_service.dart';
import 'services/sonos_event_service.dart';

/// View enum matching the Svelte $view store.
enum AppView { turntable, speakers, playlists, users, settings, screensaver }

class AppState extends ChangeNotifier {
  final SonosRepository api = SonosRepository();
  final ConfigService configService = ConfigService();
  final ArtworkCache artworkCache = ArtworkCache();
  SonosEventService? _eventService;

  AppConfig _config = const AppConfig();
  AppConfig get config => _config;

  SonosState _sonos = SonosState.empty;
  SonosState get sonos => _sonos;

  ConnectionStatus _connection = const ConnectionStatus();
  ConnectionStatus get connection => _connection;

  AppView _view = AppView.turntable;
  AppView get view => _view;

  String _toastMessage = '';
  DateTime? _toastAt;
  String get toastMessage => _toastMessage;
  bool get toastVisible =>
      _toastAt != null && DateTime.now().difference(_toastAt!) < const Duration(milliseconds: 2500);

  String? _volumeMode;
  String? get volumeMode => _volumeMode;

  bool _volumeControlVisible = false;
  bool get volumeControlVisible => _volumeControlVisible;

  // --- Optimistic play state (for instant UI response on play/pause) ---
  String? _optimisticPlayState;
  DateTime? _optimisticAppliedAt;
  static const _optimisticTimeout = Duration(seconds: 3);

  bool _navVisible = false;
  bool get navVisible => _navVisible;

  bool _initialized = false;
  bool get initialized => _initialized;

  AppState() {
    _init();
  }

  Future<void> _init() async {
    _config = await configService.loadConfig();
    _startPolling();
    _startEventService();
    _initialized = true;
    notifyListeners();
  }

  void _startEventService() {
    final service = SonosEventService(
      onEvent: _handleSonosEvent,
      onConnectionChange: (connected) {
        // Silent — events are a bonus; polling is the backbone.
        // Could surface a "real-time connected" indicator in the UI later.
      },
    );
    _eventService = service;
    service.connect(_config.socoApi.baseUrl);
  }

  /// Handle a real-time event from the Sonos WebSocket.
  ///
  /// If the event is for the active speaker (or any speaker when topology
  /// changes), trigger an immediate debounced refresh to pick up the new state
  /// without waiting for the next polling tick.
  void _handleSonosEvent(SonosEvent event) {
    final activeUid = _sonos.activeSpeakerUid;

    switch (event.type) {
      case SonosEventType.playback:
        // Track/play state changed. Only refresh if it's for the active
        // speaker (or no speaker specified — refresh anyway to be safe).
        if (event.speaker == null || event.speaker == activeUid) {
          api.triggerImmediateRefresh();
        }
        break;

      case SonosEventType.volume:
        // Volume changed. Refresh to update the speaker list volumes.
        api.triggerImmediateRefresh();
        break;

      case SonosEventType.topology:
        // Groups changed (speaker joined/left/regrouped). Always refresh
        // to update the speakers list and group structure.
        api.triggerImmediateRefresh();
        break;

      case SonosEventType.speaker:
      case SonosEventType.unknown:
        // Generic or unknown event — refresh to be safe, but only if the
        // active speaker might be affected.
        if (event.speaker == null || event.speaker == activeUid) {
          api.triggerImmediateRefresh();
        }
        break;
    }
  }

  void _startPolling() {
    api.startPolling(
      () => _config,
      () => _sonos.activeSpeakerUid,
      (data) => _handleUpdate(data),
      (error) => _handleError(error),
    );
  }

  void _handleUpdate(Map<String, dynamic> data) {
    final newSpeakers = data['speakers'] as List<Speaker>? ?? [];
    final newGroups = data['groups'] as List<SonosGroup>? ?? [];
    final newPlayback = data['playback'] as Playback? ?? const Playback();
    final newPlaylists = data['playlists'] as List<PlaylistItem>? ?? [];

    // Per-speaker playbacks from probing all speakers during the poll.
    // This lets us cache every speaker's metadata so switching is instant.
    final playbacks = data['playbacks'] as Map<String, Playback>? ?? {};

    // dataSpeakerUid is the speaker whose playback was actually fetched by the API.
    // This may differ from the user's selected speaker (e.g., user picked a group
    // member but the API resolved to the coordinator).
    final dataSpeakerUid = data['speakerUid'] as String?;

    // Only auto-set activeSpeakerUid on the very first load (no prior selection).
    // After that, the active speaker is only changed by explicit setActiveSpeaker().
    String? activeUid = _sonos.activeSpeakerUid ?? dataSpeakerUid ?? newSpeakers.firstOrNull?.uid;

    if (activeUid != null) {
      final existingStates = Map<String, SpeakerState>.from(_sonos.speakerStates);

      // Store per-speaker playbacks from the poll so every speaker has fresh
      // metadata. This makes switching the active speaker instant.
      for (final entry in playbacks.entries) {
        final speakerUid = entry.key;
        final pb = entry.value;
        final existing = existingStates[speakerUid] ?? const SpeakerState();
        existingStates[speakerUid] = existing.copyWith(playback: pb);
      }

      // Also store playlists under the data's speaker.
      if (dataSpeakerUid != null) {
        final existing = existingStates[dataSpeakerUid] ?? const SpeakerState();
        existingStates[dataSpeakerUid] = existing.copyWith(playlists: newPlaylists);
      }

      // Build a group lookup to check if active and data speakers share a group.
      final groupOf = <String, String>{};
      for (final g in newGroups) {
        for (final m in g.memberUids) {
          groupOf[m] = g.coordinatorUid;
        }
      }

      // Only mirror playback from dataSpeakerUid to activeUid if they are in
      // the same Sonos group (group members share the coordinator's playback).
      // This prevents stale data from an unrelated speaker overwriting the
      // active speaker's correct metadata when an in-flight poll completes
      // after the user has already switched speakers.
      if (activeUid != dataSpeakerUid &&
          dataSpeakerUid != null &&
          groupOf[activeUid] != null &&
          groupOf[activeUid] == groupOf[dataSpeakerUid]) {
        final existing = existingStates[activeUid] ?? const SpeakerState();
        existingStates[activeUid] =
            existing.copyWith(playback: newPlayback, playlists: newPlaylists);
      }

      // Clear optimistic play-state override if real data matches or is stale.
      if (_optimisticPlayState != null && _optimisticAppliedAt != null) {
        final isStale = DateTime.now().difference(_optimisticAppliedAt!) > _optimisticTimeout;
        final realState = (existingStates[activeUid] ?? const SpeakerState()).playback.state;
        if (isStale || realState == _optimisticPlayState) {
          _optimisticPlayState = null;
          _optimisticAppliedAt = null;
        }
      }

      // Re-apply optimistic play-state if still active. The per-speaker
      // playback loop above may have overwritten the active speaker's state
      // with stale poll data. We force the play state back to the optimistic
      // value while keeping the poll's fresh metadata (title/artist/artwork).
      if (_optimisticPlayState != null) {
        final existing = existingStates[activeUid] ?? const SpeakerState();
        existingStates[activeUid] = existing.copyWith(
          playback: existing.playback.copyWith(state: _optimisticPlayState),
        );
      }

      _sonos = _sonos.copyWith(
        speakers: newSpeakers,
        activeSpeakerUid: activeUid,
        groups: newGroups,
        speakerStates: existingStates,
      );
    } else {
      _sonos = _sonos.copyWith(
        speakers: newSpeakers,
        groups: newGroups,
      );
    }

    _connection = _connection.copyWith(
      connected: true,
      mock: api.isMock(_config.socoApi.baseUrl) || api.hasFallenBackToMock,
      lastUpdated: DateTime.now(),
      error: null,
    );

    // Preload artwork for all speakers' current tracks so artwork appears
    // instantly when switching the active speaker.
    for (final entry in playbacks.entries) {
      final artUrl = entry.value.artworkUrl;
      if (artUrl.isNotEmpty && !artworkCache.isReady(artUrl)) {
        artworkCache.get(artUrl);
      }
    }

    notifyListeners();
  }

  void _handleError(Object error) {
    print('[poll] error: $error');
    _connection = _connection.copyWith(connected: false, error: error.toString());
    notifyListeners();
  }

  void setView(AppView v) {
    if (_view == v) return;
    _view = v;
    _volumeMode = null;
    _navVisible = false;
    notifyListeners();
  }

  void toggleNav() {
    _navVisible = !_navVisible;
    notifyListeners();
  }

  void showNav() {
    if (!_navVisible) {
      _navVisible = true;
      notifyListeners();
    }
  }

  void hideNav() {
    if (_navVisible) {
      _navVisible = false;
      _volumeMode = null;
      notifyListeners();
    }
  }

  void showToast(String message) {
    _toastMessage = message;
    _toastAt = DateTime.now();
    notifyListeners();
    // Auto-hide
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (_toastAt != null &&
          DateTime.now().difference(_toastAt!) >= const Duration(milliseconds: 2400)) {
        _toastAt = null;
        notifyListeners();
      }
    });
  }

  void setVolumeMode(String? mode) {
    _volumeMode = mode;
    notifyListeners();
  }

  void showVolumeControl() {
    if (!_volumeControlVisible) {
      _volumeControlVisible = true;
      notifyListeners();
    }
  }

  void hideVolumeControl() {
    if (_volumeControlVisible) {
      _volumeControlVisible = false;
      notifyListeners();
    }
  }

  // --- Actions ---

  Future<void> togglePlayPause() async {
    final name = _sonos.activeSpeaker?.name;
    if (name == null) return;

    // Optimistic update: flip play state immediately for instant UI response.
    // The post-command refresh burst will confirm or correct this within ~300ms.
    final currentState = _sonos.activePlayback.state;
    final newState = currentState == 'playing' ? 'paused' : 'playing';
    _applyOptimisticPlayState(newState);

    try {
      if (currentState == 'playing') {
        await api.pauseCommand(_config, name);
      } else {
        await api.playCommand(_config, name);
      }
    } catch (e) {
      // Revert optimistic state on error
      _applyOptimisticPlayState(currentState);
      showToast('connection.error');
    }
  }

  /// Apply an optimistic play state to the active speaker for instant UI feedback.
  /// Sets a 3-second override window; incoming refreshes that match will clear it.
  void _applyOptimisticPlayState(String newState) {
    final activeUid = _sonos.activeSpeakerUid;
    if (activeUid == null) return;

    _optimisticPlayState = newState;
    _optimisticAppliedAt = DateTime.now();

    final states = Map<String, SpeakerState>.from(_sonos.speakerStates);
    final current = states[activeUid] ?? const SpeakerState();
    states[activeUid] = current.copyWith(
      playback: current.playback.copyWith(state: newState),
    );
    _sonos = _sonos.copyWith(speakerStates: states);
    notifyListeners();
  }

  Future<void> nextTrack() async {
    final name = _sonos.activeSpeaker?.name;
    if (name == null) return;
    // Preserve the 'playing' state during track transition so the turntable
    // doesn't briefly stop when the Sonos reports a transient state between
    // tracks.
    if (_sonos.activePlayback.isPlaying) {
      _applyOptimisticPlayState('playing');
    }
    try {
      await api.nextCommand(_config, name);
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> previousTrack() async {
    final name = _sonos.activeSpeaker?.name;
    if (name == null) return;
    // Same as nextTrack — preserve 'playing' during the transition.
    if (_sonos.activePlayback.isPlaying) {
      _applyOptimisticPlayState('playing');
    }
    try {
      await api.previousCommand(_config, name);
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> setVolume(int volume) async {
    final name = _sonos.activeSpeaker?.name;
    if (name == null) return;
    try {
      await api.setVolumeCommand(_config, name, volume);
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> setActiveSpeaker(String uid) async {
    if (_sonos.activeSpeakerUid == uid) return;

    // Switch immediately — the new active speaker's metadata is already cached
    // from the last poll's per-speaker playback data (see _handleUpdate).
    // This gives an instant UI update with no network round-trip.
    _sonos = _sonos.copyWith(activeSpeakerUid: uid);
    notifyListeners();

    // Trigger a background refresh to fetch the latest state for the newly
    // active speaker. The result arrives via _handleUpdate.
    api.getCachedOrRefresh(
      _config,
      uid,
      onRefreshed: (data) => _handleUpdate(data),
    );
  }

  Future<void> groupSpeakers(String coord, String member) async {
    try {
      await api.groupSpeakers(_config, coord, member);
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> ungroupSpeaker(String name) async {
    try {
      await api.ungroupSpeaker(_config, name);
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> playPlaylist(String playlistName) async {
    final name = _sonos.activeSpeaker?.name;
    if (name == null) return;
    try {
      await api.playPlaylist(_config, name, playlistName);
      setView(AppView.turntable);
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> fetchPlaylists() async {
    final name = _sonos.activeSpeaker?.name;
    if (name == null) return;
    try {
      final playlists = await api.fetchPlaylists(_config, name);
      final queue = await api.fetchQueue(_config, name);
      final states = Map<String, SpeakerState>.from(_sonos.speakerStates);
      states[name] =
          (states[name] ?? const SpeakerState()).copyWith(playlists: playlists, queue: queue);
      _sonos = _sonos.copyWith(speakerStates: states);
      notifyListeners();
    } catch (e) {
      showToast('connection.error');
    }
  }

  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await configService.saveConfig(newConfig);
    api.resetRareDataCache();
    if (!api.isMock(newConfig.socoApi.baseUrl)) {
      api.retryRealConnection();
    }
    notifyListeners();
  }

  Future<void> resetConfig() async {
    await updateConfig(const AppConfig());
  }

  String t(String key) {
    final lang = _config.ui.language;
    // Inline simple lookup to avoid circular dep
    return _strings[lang]?[key] ?? _strings['de']?[key] ?? key;
  }

  static const _strings = <String, Map<String, String>>{
    'de': {
      'connection.error': 'Verbindung zum SoCo-CLI Server fehlgeschlagen',
      'screensaver.tap_to_wake': 'Tippen zum Aufwecken',
      'playlists.title': 'Playlists',
      'playlists.empty': 'Keine Playlists verfügbar',
      'playlists.queue': 'Warteschlange',
      'speakers.title': 'Lautsprecher',
      'speakers.group': 'Gruppieren',
      'speakers.ungroup': 'Gruppe auflösen',
      'speakers.none_found': 'Keine Lautsprecher gefunden',
      'users.title': 'Spotify-Benutzer',
      'users.current': 'Aktuell',
      'users.switch': 'Wechseln zu',
      'settings.title': 'Einstellungen',
      'settings.save': 'Speichern',
      'settings.reset': 'Auf Standard zurücksetzen',
      'settings.language': 'Sprache',
      'settings.theme': 'Design',
      'settings.screensaver': 'Bildschirmschoner',
      'settings.screensaver.enabled': 'Aktiviert',
      'settings.screensaver.timeout': 'Timeout (Sek.)',
      'settings.screensaver.mode': 'Uhr-Modus',
      'settings.screensaver.brightness': 'Helligkeit',
      'settings.turntable': 'Plattenspieler',
      'settings.turntable.spin': 'Umlaufzeit (Sek.)',
      'settings.api': 'SoCo-CLI API',
      'settings.api.baseUrl': 'Server-URL',
      'settings.api.status': 'Status',
      'settings.api.status.connected': 'Verbunden',
      'settings.api.status.disconnected': 'Getrennt',
      'connection.mock_title': 'Demo-Modus',
      'connection.mock_text': 'SoCo-CLI Server nicht erreichbar.',
      'connection.retry': 'Erneut versuchen',
    },
    'en': {
      'connection.error': 'Failed to connect to SoCo-CLI server',
      'screensaver.tap_to_wake': 'Tap to wake',
      'playlists.title': 'Playlists',
      'playlists.empty': 'No playlists available',
      'playlists.queue': 'Queue',
      'speakers.title': 'Speakers',
      'speakers.group': 'Group',
      'speakers.ungroup': 'Ungroup',
      'speakers.none_found': 'No speakers found',
      'users.title': 'Spotify Users',
      'users.current': 'Current',
      'users.switch': 'Switch to',
      'settings.title': 'Settings',
      'settings.save': 'Save',
      'settings.reset': 'Reset to defaults',
      'settings.language': 'Language',
      'settings.theme': 'Theme',
      'settings.screensaver': 'Screensaver',
      'settings.screensaver.enabled': 'Enabled',
      'settings.screensaver.timeout': 'Timeout (sec)',
      'settings.screensaver.mode': 'Clock mode',
      'settings.screensaver.brightness': 'Brightness',
      'settings.turntable': 'Turntable',
      'settings.turntable.spin': 'Spin duration (sec)',
      'settings.api': 'SoCo-CLI API',
      'settings.api.baseUrl': 'Server URL',
      'settings.api.status': 'Status',
      'settings.api.status.connected': 'Connected',
      'settings.api.status.disconnected': 'Disconnected',
      'connection.mock_title': 'Demo Mode',
      'connection.mock_text': 'SoCo-CLI server unreachable.',
      'connection.retry': 'Retry',
    },
  };

  @override
  void dispose() {
    _eventService?.dispose();
    api.stopPolling();
    super.dispose();
  }
}
