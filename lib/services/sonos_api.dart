/// Sonos control via the SoCo-CLI HTTP API server.
/// Ported from src/lib/sonosApi.js — see that file for API docs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/app_config.dart';
import '../models/sonos_models.dart';

// ---------------------------------------------------------------------------
// Parsing helpers (pure functions, ported from JS)
// ---------------------------------------------------------------------------

int parseTimeToSeconds(String str) {
  final parts = str.split(':').map(int.parse).toList();
  if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length == 2) return parts[0] * 60 + parts[1];
  return parts.firstOrNull ?? 0;
}

Map<String, dynamic> parseTrackResult(String? text) {
  if (text == null || text.isEmpty) return {};
  final info = <String, String>{};
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    final m = RegExp(r'^(\w[\w\s]*?):\s+(.+)$').firstMatch(trimmed);
    if (m != null) {
      info[m[1]!.trim().toLowerCase()] = m[2]!.trim();
    }
  }
  final result = <String, dynamic>{
    'title': info['title'] ?? info['track'] ?? info['episode'] ?? info['podcast'] ?? '',
    'artist': info['artist'] ?? info['channel'] ?? '',
    'album': info['album'] ?? info['podcast'] ?? '',
    // Fallback: use podcast name as artist if no artist (for turntable display)
    '_podcast': info['podcast'] ?? '',
    'artworkUrl': info['album art'] ?? info['artwork'] ?? '',
  };
  if (info['duration'] != null) {
    result['duration'] = parseTimeToSeconds(info['duration']!);
  }
  if (info['elapsed'] != null) {
    result['position'] = parseTimeToSeconds(info['elapsed']!);
  }
  return result;
}

String parseStateResult(String? text) {
  final s = (text ?? '').trim().toUpperCase();
  if (s.contains('PLAY') && !s.contains('PAUSE')) return 'PLAYING';
  if (s.contains('PAUSE')) return 'PAUSED_PLAYBACK';
  if (s.contains('TRANSITION')) return 'TRANSITIONING';
  return 'STOPPED';
}

int parseVolumeResult(String? text) {
  final m = RegExp(r'^(\d+)').firstMatch((text ?? '').trim());
  return m != null ? int.parse(m[1]!) : 0;
}

List<PlaylistItem> parsePlaylistsResult(String? text) {
  final items = <PlaylistItem>[];
  if (text == null || text.isEmpty) return items;
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(\d+):\s*(.+)$').firstMatch(line.trim());
    if (m != null) {
      items.add(PlaylistItem(
        title: m[2]!.trim(),
        itemId: int.parse(m[1]!),
      ));
    }
  }
  return items;
}

List<QueueItem> parseQueueResult(String? text) {
  final items = <QueueItem>[];
  if (text == null || text.isEmpty) return items;
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(\*?\s*)(\d+):\s*(.+)$').firstMatch(line.trim());
    if (m != null) {
      items.add(QueueItem(title: m[3]!.trim(), artist: ''));
    }
  }
  return items;
}

List<Map<String, dynamic>> parseGroupsResult(String? text) {
  final groups = <Map<String, dynamic>>[];
  if (text == null || text.isEmpty) return groups;
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(.+?):\s*(.*)$').firstMatch(line.trim());
    if (m != null) {
      final coord = m[1]!.trim();
      final membersStr = m[2]!.trim();
      final members = membersStr.isNotEmpty
          ? membersStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
          : [coord];
      groups.add({'coordinator': coord, 'members': members});
    }
  }
  return groups;
}

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> apiGet(String baseUrl, String path, int timeoutMs) async {
  final client = HttpClient();
  client.connectionTimeout = Duration(milliseconds: timeoutMs);
  try {
    final uri = Uri.parse('$baseUrl$path');
    final request = await client.getUrl(uri);
    request.headers.set('Accept', 'application/json');
    final response = await request.close().timeout(
          Duration(milliseconds: timeoutMs),
          onTimeout: () => throw Exception('timeout'),
        );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} ${response.reasonPhrase}');
    }
    final body = await response.transform(utf8.decoder).join();
    return json.decode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// Mock provider
// ---------------------------------------------------------------------------

class _MockState {
  List<Map<String, dynamic>> speakers;
  List<Map<String, dynamic>> groups;
  Map<String, dynamic> playback;
  List<Map<String, dynamic>> queue;
  List<Map<String, dynamic>> playlists;

  _MockState()
      : speakers = [
          {'name': 'Büro', 'volume': 27, 'muted': false},
          {'name': 'Finn', 'volume': 35, 'muted': false},
          {'name': 'Lena', 'volume': 20, 'muted': false},
          {'name': 'Lounge', 'volume': 45, 'muted': false},
          {'name': 'Move', 'volume': 30, 'muted': false},
          {'name': 'Nils', 'volume': 25, 'muted': false},
        ],
        groups = [],
        playback = {
          'state': 'PAUSED_PLAYBACK',
          'title': '5 Minuten Harry Podcast #30',
          'artist': 'Coldmirror',
          'album': '5 Minuten Harry Podcast',
          'artworkUrl': '',
          'duration': 3732,
          'position': 0,
        },
        queue = [
          {'title': '5 Min Harry Podcast #30', 'artist': 'Coldmirror'},
          {'title': '5 Min Harry Podcast #26', 'artist': 'Coldmirror'},
          {'title': '5 Min Harry Podcast #25', 'artist': 'Coldmirror'},
        ],
        playlists = [
          {'title': 'Bibi Kampf um Kartoffelbrei', 'item_id': 1},
          {'title': 'Claudia', 'item_id': 2},
          {'title': 'Finn Playlist von Lena', 'item_id': 4},
          {'title': 'Jan & Henry', 'item_id': 5},
          {'title': 'Kids Dance', 'item_id': 7},
          {'title': 'Maluna', 'item_id': 8},
          {'title': 'Samstag – Nachmittagsmix', 'item_id': 9},
          {'title': 'Sternenschweif', 'item_id': 11},
          {'title': 'Yakari', 'item_id': 13},
        ];

  void tick() {
    if (playback['state'] == 'PLAYING') {
      playback['position'] = (playback['position'] as int) + 1;
      if (playback['position'] >= playback['duration']) {
        playback['position'] = 0;
      }
    }
  }

  Map<String, dynamic> clone() => {
        'speakers': speakers.map((s) => Map<String, dynamic>.from(s)).toList(),
        'groups': groups.map((g) => Map<String, dynamic>.from(g)).toList(),
        'playback': Map<String, dynamic>.from(playback),
        'queue': queue.map((q) => Map<String, dynamic>.from(q)).toList(),
        'playlists': playlists.map((p) => Map<String, dynamic>.from(p)).toList(),
      };
}

// ---------------------------------------------------------------------------
// SonosApi — main service class
// ---------------------------------------------------------------------------

class SonosApi {
  final _mock = _MockState();
  int _consecutiveFailures = 0;
  bool _fallbackToMock = false;
  Timer? _pollTimer;

  // Mutex: ensures all API calls run sequentially — no parallel requests to
  // the SoCo-CLI server, which prevents out-of-order responses from
  // overwriting each other and causing flickering playback data.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final prev = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return prev.then((_) => fn()).whenComplete(() => completer.complete());
  }

  // Rare data cache
  List<Map<String, dynamic>>? _groupsCache;
  List<PlaylistItem>? _playlistsCache;
  int _pollCount = 0;
  static const _rareDataTtlPolls = 15;

  bool isMock(String baseUrl) => baseUrl.isEmpty || baseUrl.startsWith('mock://');

  /// Whether we've fallen back to mock mode after repeated failures.
  bool get hasFallenBackToMock => _fallbackToMock;

  bool _shouldUseMock(AppConfig cfg) => isMock(cfg.socoApi.baseUrl) || _fallbackToMock || kIsWeb;

  void resetRareDataCache() {
    _groupsCache = null;
    _playlistsCache = null;
    _pollCount = 0;
  }

  void retryRealConnection() {
    _consecutiveFailures = 0;
    _fallbackToMock = false;
  }

  // ---- Refresh (polling) ---------------------------------------------------

  Future<Map<String, dynamic>?> refresh(AppConfig cfg, String? activeSpeakerName) {
    return _serialized(() => _refreshImpl(cfg, activeSpeakerName));
  }

  Future<Map<String, dynamic>?> _refreshImpl(AppConfig cfg, String? activeSpeakerName) async {
    final useMock = _shouldUseMock(cfg);

    try {
      Map<String, dynamic> data;

      if (useMock) {
        _mock.tick();
        data = _mock.clone();
        if (activeSpeakerName == null && (_mock.speakers as List).isNotEmpty) {
          activeSpeakerName = _mock.speakers[0]['name'] as String;
        }
      } else {
        // 1. Get speaker list
        final speakersRes = await apiGet(cfg.socoApi.baseUrl, '/speakers', cfg.socoApi.timeout);
        final speakerNames =
            (speakersRes['speakers'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [];
        if (speakerNames.isEmpty) throw Exception('No speakers found');
        activeSpeakerName ??= speakerNames.first;

        // 2. Volume for each speaker
        final speakerInfos = <Map<String, dynamic>>[];
        for (final name in speakerNames) {
          final enc = Uri.encodeComponent(name);
          int volume = 0;
          try {
            final volRes = await apiGet(cfg.socoApi.baseUrl, '/$enc/volume', cfg.socoApi.timeout);
            volume = parseVolumeResult(volRes['result'] as String?);
          } catch (_) {
            volume = 0;
          }
          speakerInfos.add({'name': name, 'volume': volume, 'muted': false});
        }

        // 3. Probe all speakers for state+track, prefer actively playing ones
        final probed = <Map<String, dynamic>>[];
        for (final name in speakerNames) {
          final enc = Uri.encodeComponent(name);
          String st = 'STOPPED';
          Map<String, dynamic> ti = {};
          try {
            final stateRes = await apiGet(cfg.socoApi.baseUrl, '/$enc/state', cfg.socoApi.timeout);
            if (stateRes['exit_code'] != 0 &&
                (stateRes['error_msg'] as String?)?.isNotEmpty == true) {
              continue;
            }
            st = stateRes['result'] as String? ?? 'STOPPED';
          } catch (_) {
            continue;
          }

          try {
            final trackRes = await apiGet(cfg.socoApi.baseUrl, '/$enc/track', cfg.socoApi.timeout);
            ti = parseTrackResult(trackRes['result'] as String?);
          } catch (_) {}

          try {
            final artRes =
                await apiGet(cfg.socoApi.baseUrl, '/$enc/album_art', cfg.socoApi.timeout);
            final artUrl = (artRes['result'] as String?)?.trim() ?? '';
            if ((ti['artworkUrl'] == null || (ti['artworkUrl'] as String).isEmpty) &&
                artUrl.startsWith('http')) {
              ti['artworkUrl'] = artUrl;
            }
          } catch (_) {}

          final parsedState = parseStateResult(st);
          final hasTrackInfo = (ti['title'] as String?)?.isNotEmpty == true;
          probed.add({
            'name': name,
            'state': parsedState,
            'stateText': st,
            'trackInfo': ti,
            'hasTrackInfo': hasTrackInfo
          });
        }

        if (probed.isEmpty) {
          throw Exception('No working speaker found among ${speakerNames.length} speakers');
        }

        // Use the requested active speaker if it's a working speaker (even if idle)
        // Smart selection only applies for initial auto-selection (activeSpeakerName == null)
        final active = probed.where((p) => p['name'] == activeSpeakerName).firstOrNull;
        String? workingSpeaker = active != null ? (active['name'] as String?) : null;
        // Auto-select: only when no active speaker was specified
        workingSpeaker ??= probed
            .where((p) => p['state'] == 'PLAYING' && p['hasTrackInfo'] == true)
            .firstOrNull?['name'] as String?;
        workingSpeaker ??=
            probed.where((p) => p['hasTrackInfo'] == true).firstOrNull?['name'] as String?;
        workingSpeaker ??= probed.first['name'] as String;

        final chosen = probed.firstWhere((p) => p['name'] == workingSpeaker);
        activeSpeakerName = chosen['name'] as String;
        final stateText = chosen['stateText'] as String;
        final trackInfo = chosen['trackInfo'] as Map<String, dynamic>;
        final encActive = Uri.encodeComponent(activeSpeakerName);

        // 4. Rare data
        _pollCount++;
        final needRare =
            _pollCount % _rareDataTtlPolls == 0 || _groupsCache == null || _playlistsCache == null;

        if (needRare) {
          try {
            final groupsRes =
                await apiGet(cfg.socoApi.baseUrl, '/$encActive/groups', cfg.socoApi.timeout);
            _groupsCache = parseGroupsResult(groupsRes['result'] as String?);
          } catch (_) {}
          try {
            final playlistsRes =
                await apiGet(cfg.socoApi.baseUrl, '/$encActive/playlists', cfg.socoApi.timeout);
            _playlistsCache = parsePlaylistsResult(playlistsRes['result'] as String?);
          } catch (_) {}
        }

        data = {
          'speakers': speakerInfos,
          'groups': _groupsCache ?? [],
          'playback': {
            'state': parseStateResult(stateText),
            ...trackInfo,
          },
          'queue': <dynamic>[],
          'playlists':
              _playlistsCache?.map((p) => {'title': p.title, 'item_id': p.itemId}).toList() ?? [],
        };
      }

      final speakerPlayback = _buildPlayback(data['playback'] as Map<String, dynamic>);
      final speakerUid = activeSpeakerName ?? (data['speakers'] as List).firstOrNull?['name'];

      final groupLookup = <String, Map<String, dynamic>>{};
      for (final g in (data['groups'] as List)) {
        final gm = g as Map<String, dynamic>;
        for (final member in (gm['members'] as List)) {
          groupLookup[member as String] = {
            'isCoordinator': member == gm['coordinator'],
            'groupLabel': gm['coordinator'],
          };
        }
      }

      return {
        'speakerUid': speakerUid,
        'playback': speakerPlayback,
        'speakers': (data['speakers'] as List).map((sp) {
          final m = sp as Map<String, dynamic>;
          final group =
              groupLookup[m['name'] as String] ?? {'isCoordinator': true, 'groupLabel': m['name']};
          return Speaker(
            uid: m['name'] as String,
            name: m['name'] as String,
            ip: m['ip'] as String? ?? '',
            isCoordinator: group['isCoordinator'] as bool,
            groupLabel: group['groupLabel'] as String,
            volume: m['volume'] as int,
            muted: m['muted'] as bool? ?? false,
          );
        }).toList(),
        'groups': (data['groups'] as List).map((g) {
          final gm = g as Map<String, dynamic>;
          return SonosGroup(
            coordinatorUid: gm['coordinator'] as String,
            memberUids: (gm['members'] as List).cast<String>(),
          );
        }).toList(),
        'playlists': (data['playlists'] as List?)?.map((p) {
              final pm = p as Map<String, dynamic>;
              return PlaylistItem(
                title: pm['title'] as String,
                itemId: pm['item_id'] as int,
              );
            }).toList() ??
            [],
      };
    } catch (err) {
      _consecutiveFailures++;
      if (!isMock(cfg.socoApi.baseUrl) && !_fallbackToMock && _consecutiveFailures >= 5) {
        _fallbackToMock = true;
        print(
            '[sonosApi] SoCo-CLI unreachable after $_consecutiveFailures attempts — falling back to mock mode.');
        return _refreshImpl(cfg, activeSpeakerName);
      }

      if (_fallbackToMock) {
        _mock.tick();
        final activeName = activeSpeakerName ?? (_mock.speakers as List).firstOrNull?['name'];
        return {
          'speakerUid': activeName,
          'playback': _buildPlayback(_mock.playback),
          'speakers': (_mock.speakers as List).map((s) {
            final m = s as Map<String, dynamic>;
            return Speaker(
              uid: m['name'] as String,
              name: m['name'] as String,
              ip: '',
              isCoordinator: true,
              groupLabel: m['name'] as String,
              volume: m['volume'] as int,
              muted: m['muted'] as bool,
            );
          }).toList(),
          'groups': <SonosGroup>[],
          'playlists': (_mock.playlists as List).map((p) {
            final pm = p as Map<String, dynamic>;
            return PlaylistItem(
              title: pm['title'] as String,
              itemId: pm['item_id'] as int,
            );
          }).toList(),
        };
      }

      rethrow;
    }
  }

  Playback _buildPlayback(Map<String, dynamic> raw) {
    final rawState = raw['state'] as String? ?? 'STOPPED';
    String state;
    if (rawState == 'PLAYING') {
      state = 'playing';
    } else if (rawState == 'PAUSED_PLAYBACK') {
      state = 'paused';
    } else if (rawState == 'TRANSITIONING') {
      state = 'transitioning';
    } else {
      state = 'stopped';
    }
    final artist = raw['artist'] as String? ?? '';
    return Playback(
      state: state,
      title: raw['title'] as String? ?? '',
      artist: artist.isNotEmpty ? artist : (raw['_podcast'] as String? ?? ''),
      album: raw['album'] as String? ?? '',
      artworkUrl: raw['artworkUrl'] as String? ?? '',
      duration: raw['duration'] as int? ?? 0,
      position: raw['position'] as int? ?? 0,
    );
  }

  // ---- Immediate commands (non-serialized, fire-and-forget) ------------------
  // These bypass the serialization lock so user actions are never delayed
  // behind a polling refresh. The polling loop will pick up state changes.

  /// Sends a single command HTTP request immediately (not serialized).
  Future<void> playCommand(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['state'] = 'PLAYING';
      return;
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/play', cfg.socoApi.timeout);
  }

  Future<void> pauseCommand(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['state'] = 'PAUSED_PLAYBACK';
      return;
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/pause', cfg.socoApi.timeout);
  }

  Future<void> nextCommand(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['position'] = 0;
      return;
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/next', cfg.socoApi.timeout);
  }

  Future<void> previousCommand(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['position'] = 0;
      return;
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/previous', cfg.socoApi.timeout);
  }

  Future<void> setVolumeCommand(AppConfig cfg, String speakerName, int volume) async {
    final v = volume.clamp(0, 100);
    if (_shouldUseMock(cfg)) {
      final sp = _mock.speakers.where((s) => s['name'] == speakerName).firstOrNull;
      if (sp != null) sp['volume'] = v;
      return;
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/volume/$v', cfg.socoApi.timeout);
  }

  // ---- Legacy actions (serialized, used for complex multi-step ops) ----------

  Future<Map<String, dynamic>?> play(AppConfig cfg, String speakerName) {
    return _serialized(() => _playImpl(cfg, speakerName));
  }

  Future<Map<String, dynamic>?> _playImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['state'] = 'PLAYING';
      return _refreshImpl(cfg, speakerName);
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/play', cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<Map<String, dynamic>?> pause(AppConfig cfg, String speakerName) {
    return _serialized(() => _pauseImpl(cfg, speakerName));
  }

  Future<Map<String, dynamic>?> _pauseImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['state'] = 'PAUSED_PLAYBACK';
      return _refreshImpl(cfg, speakerName);
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/pause', cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<Map<String, dynamic>?> next(AppConfig cfg, String speakerName) {
    return _serialized(() => _nextImpl(cfg, speakerName));
  }

  Future<Map<String, dynamic>?> _nextImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['position'] = 0;
      return _refreshImpl(cfg, speakerName);
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/next', cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<Map<String, dynamic>?> previous(AppConfig cfg, String speakerName) {
    return _serialized(() => _previousImpl(cfg, speakerName));
  }

  Future<Map<String, dynamic>?> _previousImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['position'] = 0;
      return _refreshImpl(cfg, speakerName);
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/previous', cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<Map<String, dynamic>?> setVolume(AppConfig cfg, String speakerName, int volume) {
    return _serialized(() => _setVolumeImpl(cfg, speakerName, volume));
  }

  Future<Map<String, dynamic>?> _setVolumeImpl(
      AppConfig cfg, String speakerName, int volume) async {
    final v = volume.clamp(0, 100);
    if (_shouldUseMock(cfg)) {
      final sp = _mock.speakers.where((s) => s['name'] == speakerName).firstOrNull;
      if (sp != null) sp['volume'] = v;
      return _refreshImpl(cfg, speakerName);
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/volume/$v', cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<List<QueueItem>> fetchQueue(AppConfig cfg, String speakerName) {
    return _serialized(() => _fetchQueueImpl(cfg, speakerName));
  }

  Future<List<QueueItem>> _fetchQueueImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      return (_mock.queue as List)
          .map((q) => QueueItem(
                title: (q as Map<String, dynamic>)['title'] as String,
                artist: (q)['artist'] as String? ?? '',
              ))
          .toList();
    }
    final res = await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/queue', cfg.socoApi.timeout);
    return parseQueueResult(res['result'] as String?);
  }

  Future<List<PlaylistItem>> fetchPlaylists(AppConfig cfg, String speakerName) {
    return _serialized(() => _fetchPlaylistsImpl(cfg, speakerName));
  }

  Future<List<PlaylistItem>> _fetchPlaylistsImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      return (_mock.playlists as List)
          .map((p) => PlaylistItem(
                title: (p as Map<String, dynamic>)['title'] as String,
                itemId: (p)['item_id'] as int,
              ))
          .toList();
    }
    final res = await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/playlists', cfg.socoApi.timeout);
    return parsePlaylistsResult(res['result'] as String?);
  }

  Future<Map<String, dynamic>?> playPlaylist(
      AppConfig cfg, String speakerName, String playlistName) {
    return _serialized(() => _playPlaylistImpl(cfg, speakerName, playlistName));
  }

  Future<Map<String, dynamic>?> _playPlaylistImpl(
      AppConfig cfg, String speakerName, String playlistName) async {
    if (_shouldUseMock(cfg)) {
      _mock.playback['state'] = 'PLAYING';
      final pl = _mock.playlists.where((p) => (p)['title'] == playlistName).firstOrNull;
      if (pl != null) _mock.playback['title'] = pl['title'];
      return _refreshImpl(cfg, speakerName);
    }
    try {
      await apiGet(cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/clear_queue',
          cfg.socoApi.timeout);
    } catch (_) {}
    await apiGet(
        cfg.socoApi.baseUrl,
        '/${Uri.encodeComponent(speakerName)}/add_playlist_to_queue/${Uri.encodeComponent(playlistName)}',
        cfg.socoApi.timeout);
    await apiGet(cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/play_from_queue/1',
        cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<Map<String, dynamic>?> groupSpeakers(
      AppConfig cfg, String coordinatorName, String memberName) {
    return _serialized(() => _groupSpeakersImpl(cfg, coordinatorName, memberName));
  }

  Future<Map<String, dynamic>?> _groupSpeakersImpl(
      AppConfig cfg, String coordinatorName, String memberName) async {
    if (_shouldUseMock(cfg)) {
      var g = _mock.groups.where((x) => x['coordinator'] == coordinatorName).firstOrNull;
      if (g == null) {
        g = {
          'coordinator': coordinatorName,
          'members': [coordinatorName]
        };
        _mock.groups.add(g);
      }
      if (!(g['members'] as List).contains(memberName)) {
        (g['members'] as List).add(memberName);
      }
      return _refreshImpl(cfg, coordinatorName);
    }
    await apiGet(
        cfg.socoApi.baseUrl,
        '/${Uri.encodeComponent(memberName)}/group/${Uri.encodeComponent(coordinatorName)}',
        cfg.socoApi.timeout);
    return _refreshImpl(cfg, coordinatorName);
  }

  Future<Map<String, dynamic>?> ungroupSpeaker(AppConfig cfg, String speakerName) {
    return _serialized(() => _ungroupSpeakerImpl(cfg, speakerName));
  }

  Future<Map<String, dynamic>?> _ungroupSpeakerImpl(AppConfig cfg, String speakerName) async {
    if (_shouldUseMock(cfg)) {
      for (final g in _mock.groups) {
        (g['members'] as List).remove(speakerName);
      }
      _mock.groups.add({
        'coordinator': speakerName,
        'members': [speakerName]
      });
      return _refreshImpl(cfg, speakerName);
    }
    await apiGet(
        cfg.socoApi.baseUrl, '/${Uri.encodeComponent(speakerName)}/ungroup', cfg.socoApi.timeout);
    return _refreshImpl(cfg, speakerName);
  }

  Future<void> switchSpotifyAccount(AppConfig cfg, String speakerName, String account) async {
    // SoCo-CLI doesn't have a direct Spotify account switch in the HTTP API
    // Return a message for the caller to show as toast
  }

  // ---- Polling loop ----------------------------------------------------------

  void startPolling(
    AppConfig Function() getConfig,
    String? Function() getActiveSpeakerUid,
    void Function(Map<String, dynamic> data) onUpdate,
    void Function(Object error) onError,
  ) {
    stopPolling();
    String? autoSelectedName;

    Future<void> tick() async {
      final cfg = getConfig();
      // Prefer user-selected speaker, fall back to auto-selected
      final activeName = getActiveSpeakerUid() ?? autoSelectedName;
      try {
        final data = await refresh(cfg, activeName);
        if (data != null) {
          autoSelectedName ??= data['speakerUid'] as String?;
          _consecutiveFailures = 0;
          onUpdate(data);
        }
      } catch (e) {
        onError(e);
      }
    }

    tick();
    _pollTimer = Timer.periodic(
      Duration(milliseconds: getConfig().socoApi.pollInterval),
      (_) => tick(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
