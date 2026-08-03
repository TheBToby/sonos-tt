import 'dart:async';

import '../models/app_config.dart';
import '../models/sonos_models.dart';
import '../services/sonos_api.dart';

/// Wraps [SonosApi] and adds a speaker-data cache so that
/// [setActiveSpeaker] can return cached data immediately for instant
/// display, then refresh in the background.
///
/// Also provides [triggerImmediateRefresh] (for event-driven updates) and
/// [schedulePostCommandRefresh] (for rapid polling after a user command)
/// to make the app feel responsive without waiting for the next polling tick.
class SonosRepository {
  final SonosApi _api = SonosApi();

  /// Cache of the last known full state keyed by speaker UID.
  final Map<String, Map<String, dynamic>> _speakerCache = {};

  // Stored polling callbacks — needed for on-demand refresh triggers.
  AppConfig Function()? _getConfig;
  String? Function()? _getActiveSpeakerUid;
  void Function(Map<String, dynamic> data)? _onUpdate;
  void Function(Object error)? _onError;

  // Post-command rapid poll burst state.
  Timer? _postCommandTimer;
  int _postCommandTicks = 0;
  static const _postCommandBurstCount = 8; // 8 ticks ≈ 2.4s
  static const _postCommandInterval = Duration(milliseconds: 300);
  bool _refreshInProgress = false;

  /// Last time a refresh was triggered, to debounce rapid successive calls.
  DateTime? _lastRefreshAt;
  static const _minRefreshGap = Duration(milliseconds: 200);

  // ---- Delegated API helpers ----

  bool isMock(String baseUrl) => _api.isMock(baseUrl);
  bool get hasFallenBackToMock => _api.hasFallenBackToMock;
  void resetRareDataCache() => _api.resetRareDataCache();
  void retryRealConnection() => _api.retryRealConnection();

  // ---- Refresh (polling) ----

  /// Refresh data for [activeSpeakerUid], update caches, and return result.
  Future<Map<String, dynamic>?> refresh(AppConfig cfg, String? activeSpeakerUid) async {
    final data = await _api.refresh(cfg, activeSpeakerUid);
    if (data != null) _cacheResult(data);
    return data;
  }

  /// Returns cached data for [uid] immediately (if available), then
  /// fetches fresh data in the background and returns it via [onRefreshed].
  Map<String, dynamic>? getCachedOrRefresh(
    AppConfig cfg,
    String uid, {
    void Function(Map<String, dynamic> data)? onRefreshed,
  }) {
    final cached = _speakerCache[uid];
    // Fire-and-forget background refresh
    refresh(cfg, uid).then((data) {
      if (data != null) onRefreshed?.call(data);
    });
    return cached;
  }

  // ---- On-demand refresh (event-driven) ----

  /// Trigger a single immediate refresh (debounced).
  ///
  /// Called when a real-time event arrives from the Sonos WebSocket.
  /// If a refresh is already in progress or one was triggered very recently,
  /// this is a no-op — the in-flight or recent refresh will pick up the change.
  void triggerImmediateRefresh() {
    if (_getConfig == null || _onUpdate == null) return;
    if (_refreshInProgress) return;

    final now = DateTime.now();
    if (_lastRefreshAt != null && now.difference(_lastRefreshAt!) < _minRefreshGap) {
      return; // Too soon since last refresh — skip, polling will catch it
    }

    _lastRefreshAt = now;
    _doRefresh();
  }

  /// Schedule a burst of rapid refreshes after a user command (play/pause/etc).
  ///
  /// Polls every 300ms for ~2.4s to quickly catch the state change from the
  /// speaker. This bridges the gap between sending a fire-and-forget command
  /// and the next regular polling tick (which could be seconds away).
  void schedulePostCommandRefresh() {
    if (_getConfig == null || _onUpdate == null) return;

    _postCommandTicks = 0;
    _postCommandTimer?.cancel();
    _postCommandTimer = Timer.periodic(_postCommandInterval, (_) {
      if (_postCommandTicks >= _postCommandBurstCount) {
        _postCommandTimer?.cancel();
        _postCommandTimer = null;
        return;
      }
      _postCommandTicks++;
      _doRefresh();
    });
  }

  Future<void> _doRefresh() async {
    if (_refreshInProgress || _getConfig == null) return;
    _refreshInProgress = true;
    try {
      final cfg = _getConfig!();
      final activeUid = _getActiveSpeakerUid?.call();
      final data = await _api.refresh(cfg, activeUid);
      if (data != null) {
        _cacheResult(data);
        _onUpdate?.call(data);
      }
    } catch (e) {
      _onError?.call(e);
    } finally {
      _refreshInProgress = false;
    }
  }

  // ---- Immediate commands (non-serialized, for instant UI response) ----

  /// Send a play command immediately, bypassing the serialization lock.
  /// Also triggers a post-command refresh burst to pick up the state change.
  Future<void> playCommand(AppConfig cfg, String speakerName) async {
    await _api.playCommand(cfg, speakerName);
    schedulePostCommandRefresh();
  }

  Future<void> pauseCommand(AppConfig cfg, String speakerName) async {
    await _api.pauseCommand(cfg, speakerName);
    schedulePostCommandRefresh();
  }

  Future<void> nextCommand(AppConfig cfg, String speakerName) async {
    await _api.nextCommand(cfg, speakerName);
    schedulePostCommandRefresh();
  }

  Future<void> previousCommand(AppConfig cfg, String speakerName) async {
    await _api.previousCommand(cfg, speakerName);
    schedulePostCommandRefresh();
  }

  Future<void> setVolumeCommand(AppConfig cfg, String speakerName, int volume) async {
    await _api.setVolumeCommand(cfg, speakerName, volume);
    schedulePostCommandRefresh();
  }

  // ---- Serialized actions (for complex multi-step ops) ----

  Future<Map<String, dynamic>?> play(AppConfig cfg, String speakerName) async {
    final data = await _api.play(cfg, speakerName);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<Map<String, dynamic>?> pause(AppConfig cfg, String speakerName) async {
    final data = await _api.pause(cfg, speakerName);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<Map<String, dynamic>?> next(AppConfig cfg, String speakerName) async {
    final data = await _api.next(cfg, speakerName);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<Map<String, dynamic>?> previous(AppConfig cfg, String speakerName) async {
    final data = await _api.previous(cfg, speakerName);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<Map<String, dynamic>?> setVolume(AppConfig cfg, String speakerName, int volume) async {
    final data = await _api.setVolume(cfg, speakerName, volume);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<List<QueueItem>> fetchQueue(AppConfig cfg, String speakerName) =>
      _api.fetchQueue(cfg, speakerName);

  Future<List<PlaylistItem>> fetchPlaylists(AppConfig cfg, String speakerName) =>
      _api.fetchPlaylists(cfg, speakerName);

  Future<Map<String, dynamic>?> playPlaylist(
      AppConfig cfg, String speakerName, String playlistName) async {
    final data = await _api.playPlaylist(cfg, speakerName, playlistName);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<Map<String, dynamic>?> groupSpeakers(
      AppConfig cfg, String coordinatorName, String memberName) async {
    final data = await _api.groupSpeakers(cfg, coordinatorName, memberName);
    if (data != null) _cacheResult(data);
    return data;
  }

  Future<Map<String, dynamic>?> ungroupSpeaker(AppConfig cfg, String speakerName) async {
    final data = await _api.ungroupSpeaker(cfg, speakerName);
    if (data != null) _cacheResult(data);
    return data;
  }

  // ---- Polling ----

  void startPolling(
    AppConfig Function() getConfig,
    String? Function() getActiveSpeakerUid,
    void Function(Map<String, dynamic> data) onUpdate,
    void Function(Object error) onError,
  ) {
    // Store callbacks for on-demand refresh triggers.
    _getConfig = getConfig;
    _getActiveSpeakerUid = getActiveSpeakerUid;
    _onUpdate = onUpdate;
    _onError = onError;

    _api.startPolling(getConfig, getActiveSpeakerUid, (data) {
      _cacheResult(data);
      onUpdate(data);
    }, onError);
  }

  void stopPolling() {
    _postCommandTimer?.cancel();
    _postCommandTimer = null;
    _api.stopPolling();
  }

  // ---- Internal ----

  void _cacheResult(Map<String, dynamic> data) {
    final speakerUid = data['speakerUid'] as String?;
    if (speakerUid != null) {
      _speakerCache[speakerUid] = data;
    }
  }
}
