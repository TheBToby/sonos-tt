import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Event types from the SoCo-CLI WebSocket event stream.
enum SonosEventType {
  playback, // AVTransport: play/pause/track change
  volume, // RenderingControl: volume/mute change
  topology, // ZoneGroupTopology: groups changed, speaker joined/left
  speaker, // Generic per-speaker event
  unknown;

  static SonosEventType fromString(String? s) => switch (s?.toLowerCase()) {
        'playback' || 'avtransport' => playback,
        'volume' || 'renderingcontrol' => volume,
        'topology' || 'zonegrouptopology' => topology,
        'speaker' => speaker,
        _ => unknown,
      };
}

/// A single real-time event received from the SoCo-CLI WebSocket.
class SonosEvent {
  final SonosEventType type;
  final String? speaker;
  final Map<String, dynamic> raw;

  SonosEvent({
    required this.type,
    this.speaker,
    required this.raw,
  });

  /// Parse a JSON message from the SoCo-CLI event WebSocket.
  ///
  /// Expected format:
  /// ```json
  /// {
  ///   "type": "playback" | "volume" | "topology" | "speaker",
  ///   "speaker": "speaker-name",
  ///   "data": { ... }
  /// }
  /// ```
  factory SonosEvent.fromJson(Map<String, dynamic> json) {
    return SonosEvent(
      type: SonosEventType.fromString(json['type'] as String?),
      speaker: json['speaker'] as String? ?? json['player'] as String?,
      raw: json,
    );
  }
}

/// Listens for real-time events from a SoCo-CLI WebSocket endpoint.
///
/// The SoCo-CLI server (extended with event support) exposes a WebSocket
/// at `/events/ws` that forwards UPnP/GENA events from Sonos speakers.
/// This service connects to that endpoint and calls [onEvent] whenever
/// a speaker's state changes — enabling push-based updates instead of
/// polling.
///
/// **Graceful degradation:** If the server doesn't support WebSocket events
/// yet, this service silently retries with exponential backoff. The app
/// continues to work via polling; events simply make it faster.
class SonosEventService {
  /// Called when a real-time event arrives.
  final void Function(SonosEvent event) onEvent;

  /// Called when WebSocket connection state changes.
  /// `true` = connected and receiving events, `false` = disconnected.
  final void Function(bool connected)? onConnectionChange;

  WebSocket? _ws;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  String? _wsUrl;

  static const _maxBackoff = Duration(seconds: 30);

  SonosEventService({
    required this.onEvent,
    this.onConnectionChange,
  });

  /// Start listening for events from the given SoCo-CLI HTTP base URL.
  ///
  /// Converts `http://host:port` to `ws://host:port/events/ws`.
  /// Does nothing for mock URLs.
  void connect(String httpBaseUrl) {
    if (httpBaseUrl.isEmpty || httpBaseUrl.startsWith('mock://')) return;
    disconnect();

    final wsUrl = httpBaseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    _wsUrl = '$wsUrl/events/ws';

    _connect();
  }

  Future<void> _connect() async {
    if (_disposed || _wsUrl == null) return;

    try {
      _ws = await WebSocket.connect(_wsUrl!).timeout(
        const Duration(seconds: 5),
      );
      _reconnectAttempts = 0;
      onConnectionChange?.call(true);

      _subscription = _ws!.listen(
        _onMessage,
        onError: (e) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      // Server doesn't support WebSocket events yet, or network issue.
      // Silent fallback — polling continues to work.
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      if (data is String) {
        final json = jsonDecode(data);
        if (json is Map<String, dynamic>) {
          onEvent(SonosEvent.fromJson(json));
        } else if (json is List) {
          // Batch of events
          for (final item in json) {
            if (item is Map<String, dynamic>) {
              onEvent(SonosEvent.fromJson(item));
            }
          }
        }
      }
    } catch (e) {
      // Malformed message — still trigger a generic refresh signal
      // by emitting an unknown event.
      onEvent(SonosEvent(
        type: SonosEventType.unknown,
        speaker: null,
        raw: {'raw': data.toString()},
      ));
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;

    onConnectionChange?.call(false);
    _cleanupConnection();

    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s, ...
    final delay = Duration(
      milliseconds: (1000 * (1 << (_reconnectAttempts - 1).clamp(0, 5)))
          .clamp(1000, _maxBackoff.inMilliseconds),
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  void _cleanupConnection() {
    _subscription?.cancel();
    _subscription = null;
    _ws?.close();
    _ws = null;
  }

  /// Disconnect and stop listening.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupConnection();
    _reconnectAttempts = 0;
    onConnectionChange?.call(false);
  }

  /// Permanently dispose of this service.
  void dispose() {
    _disposed = true;
    disconnect();
  }
}
