import '../models/app_config.dart';
import '../models/sonos_models.dart';
import '../services/sonos_api.dart';

/// Wraps [SonosApi] and adds a speaker-data cache so that
/// [setActiveSpeaker] can return cached data immediately for instant
/// display, then refresh in the background.
class SonosRepository {
  final SonosApi _api = SonosApi();

  /// Cache of the last known full state keyed by speaker UID.
  final Map<String, Map<String, dynamic>> _speakerCache = {};

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

  // ---- Actions (delegate to API, cache the refresh result) ----

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
    _api.startPolling(getConfig, getActiveSpeakerUid, (data) {
      _cacheResult(data);
      onUpdate(data);
    }, onError);
  }

  void stopPolling() => _api.stopPolling();

  // ---- Internal ----

  void _cacheResult(Map<String, dynamic> data) {
    final speakerUid = data['speakerUid'] as String?;
    if (speakerUid != null) {
      _speakerCache[speakerUid] = data;
    }
  }
}
