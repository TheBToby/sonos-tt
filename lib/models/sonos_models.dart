/// Data models for Sonos speakers, playback, groups, and playlists.
library;

class Speaker {
  final String uid;
  final String name;
  final String ip;
  final bool isCoordinator;
  final String groupLabel;
  final int volume;
  final bool muted;

  const Speaker({
    required this.uid,
    required this.name,
    this.ip = '',
    this.isCoordinator = true,
    this.groupLabel = '',
    this.volume = 0,
    this.muted = false,
  });

  Speaker copyWith({
    String? uid,
    String? name,
    String? ip,
    bool? isCoordinator,
    String? groupLabel,
    int? volume,
    bool? muted,
  }) {
    return Speaker(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      isCoordinator: isCoordinator ?? this.isCoordinator,
      groupLabel: groupLabel ?? this.groupLabel,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }
}

class Playback {
  final String state; // 'playing' | 'paused' | 'stopped' | 'transitioning'
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final int duration; // seconds
  final int position; // seconds
  final String trackUri;

  const Playback({
    this.state = 'stopped',
    this.title = '',
    this.artist = '',
    this.album = '',
    this.artworkUrl = '',
    this.duration = 0,
    this.position = 0,
    this.trackUri = '',
  });

  bool get isPlaying => state == 'playing';
  bool get isPaused => state == 'paused';
  bool get isStopped => state == 'stopped';

  Playback copyWith({
    String? state,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    int? duration,
    int? position,
    String? trackUri,
  }) {
    return Playback(
      state: state ?? this.state,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      trackUri: trackUri ?? this.trackUri,
    );
  }
}

class QueueItem {
  final String title;
  final String artist;

  const QueueItem({required this.title, this.artist = ''});
}

class PlaylistItem {
  final String title;
  final int itemId;

  const PlaylistItem({required this.title, required this.itemId});
}

class SonosGroup {
  final String coordinatorUid;
  final List<String> memberUids;

  const SonosGroup({required this.coordinatorUid, required this.memberUids});
}

class SpeakerState {
  final Playback playback;
  final List<QueueItem> queue;
  final List<PlaylistItem> playlists;
  final DateTime? lastUpdated;

  const SpeakerState({
    this.playback = const Playback(),
    this.queue = const [],
    this.playlists = const [],
    this.lastUpdated,
  });

  SpeakerState copyWith({
    Playback? playback,
    List<QueueItem>? queue,
    List<PlaylistItem>? playlists,
    DateTime? lastUpdated,
  }) {
    return SpeakerState(
      playback: playback ?? this.playback,
      queue: queue ?? this.queue,
      playlists: playlists ?? this.playlists,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class SonosState {
  final List<Speaker> speakers;
  final String? activeSpeakerUid;
  final List<SonosGroup> groups;
  final Map<String, SpeakerState> speakerStates;

  const SonosState({
    this.speakers = const [],
    this.activeSpeakerUid,
    this.groups = const [],
    this.speakerStates = const {},
  });

  static const empty = SonosState();

  Speaker? get activeSpeaker =>
      speakers.where((s) => s.uid == activeSpeakerUid).firstOrNull;

  Playback get activePlayback =>
      (speakerStates[activeSpeakerUid] ?? const SpeakerState()).playback;

  List<QueueItem> get activeQueue =>
      (speakerStates[activeSpeakerUid] ?? const SpeakerState()).queue;

  List<PlaylistItem> get activePlaylists =>
      (speakerStates[activeSpeakerUid] ?? const SpeakerState()).playlists;

  SonosState copyWith({
    List<Speaker>? speakers,
    String? activeSpeakerUid,
    List<SonosGroup>? groups,
    Map<String, SpeakerState>? speakerStates,
  }) {
    return SonosState(
      speakers: speakers ?? this.speakers,
      activeSpeakerUid: activeSpeakerUid ?? this.activeSpeakerUid,
      groups: groups ?? this.groups,
      speakerStates: speakerStates ?? this.speakerStates,
    );
  }
}

class ConnectionStatus {
  final bool connected;
  final String? error;
  final DateTime? lastUpdated;
  final bool mock;

  const ConnectionStatus({
    this.connected = false,
    this.error,
    this.lastUpdated,
    this.mock = false,
  });

  ConnectionStatus copyWith({
    bool? connected,
    String? error,
    DateTime? lastUpdated,
    bool? mock,
  }) {
    return ConnectionStatus(
      connected: connected ?? this.connected,
      error: error ?? this.error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      mock: mock ?? this.mock,
    );
  }
}