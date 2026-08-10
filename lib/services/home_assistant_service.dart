import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Current state of a Home Assistant light entity.
class HaLightState {
  /// `true` if the entity's state is "on".
  final bool on;

  /// Brightness as reported by HA (0–255), or `null` if the entity doesn't
  /// expose brightness (e.g. a plain on/off light). When `null` and [on] is
  /// `true`, consumers should fall back to a default brightness.
  final int? brightness;

  const HaLightState({required this.on, this.brightness});

  /// Convert HA brightness (0–255) to a 0–100 percentage for the backlight.
  int get brightnessPercent {
    if (!on) return 0;
    final b = brightness;
    if (b == null || b <= 0) return 0;
    if (b >= 255) return 100;
    return ((b / 255) * 100).round().clamp(0, 100);
  }

  @override
  String toString() => 'HaLightState(on: $on, brightness: $brightness)';
}

/// Result of a connection test against Home Assistant.
class HaConnectionResult {
  final bool success;
  final String message;
  final HaLightState? state;

  const HaConnectionResult({
    required this.success,
    required this.message,
    this.state,
  });
}

/// Subscribes to a Home Assistant light entity via the WebSocket API.
///
/// Protocol (https://developers.home-assistant.io/docs/api/websocket):
///  1. Connect to `ws://<host>:<port>/api/websocket`
///  2. Receive `{"type": "auth_required"}`
///  3. Send `{"type": "auth", "access_token": "<token>"}`
///  4. Receive `{"type": "auth_ok"}`
///  5. `get_states` (id increments) to fetch the initial entity state.
///  6. `subscribe_events` for `state_changed` to receive live updates.
///  7. Respond to `ping` messages with `pong` to keep the connection alive.
///
/// The service keeps the connection alive with exponential-backoff reconnects
/// and reports entity state changes via [onState]. Connection state changes
/// are reported via [onConnectionChange].
class HomeAssistantService {
  final void Function(HaLightState state)? onState;
  final void Function(bool connected)? onConnectionChange;

  WebSocket? _ws;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  int _nextId = 1;

  String? _url;
  String? _token;
  String? _entityId;

  /// Whether the service currently has an authenticated connection.
  bool _connected = false;
  bool get connected => _connected;

  /// Whether the service is configured to connect (has url + token + entity).
  bool get isConfigured =>
      _url != null &&
      _url!.isNotEmpty &&
      _token != null &&
      _token!.isNotEmpty &&
      _entityId != null &&
      _entityId!.isNotEmpty;

  static const _maxBackoff = Duration(seconds: 30);

  HomeAssistantService({this.onState, this.onConnectionChange});

  /// Start (or restart) the subscription with the given credentials.
  /// Any existing connection is torn down first.
  void connect(String httpBaseUrl, String token, String entityId) {
    final wsUrl = _toWsUrl(httpBaseUrl);

    if (wsUrl == null || wsUrl.isEmpty || token.isEmpty || entityId.isEmpty) {
      disconnect();
      return;
    }

    // Tear down existing connection WITHOUT clearing config (disconnect()
    // with reconnect=false would null out _url/_token/_entityId, which we
    // need for _connect()). We inline the teardown here.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupConnection();
    _reconnectAttempts = 0;
    _setConnected(false);

    // Set config AFTER teardown, then connect.
    _url = wsUrl;
    _token = token;
    _entityId = entityId;
    _connect();
  }

  /// Disconnect and stop listening. When [reconnect] is false (default), any
  /// pending reconnect timer is also cancelled and the service forgets its
  /// configuration so it stays disconnected until [connect] is called again.
  void disconnect({bool reconnect = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupConnection();
    _reconnectAttempts = 0;
    _setConnected(false);
    if (!reconnect) {
      _url = null;
      _token = null;
      _entityId = null;
    }
  }

  /// Permanently dispose of this service.
  void dispose() {
    _disposed = true;
    disconnect();
  }

  // --------------------------------------------------------------------------
  // Internal connection handling
  // --------------------------------------------------------------------------

  Future<void> _connect() async {
    if (_disposed || _url == null || _token == null || _entityId == null) return;

    print('[ha] Connecting to $_url for entity $_entityId…');
    try {
      _ws = await WebSocket.connect(_url!).timeout(const Duration(seconds: 5));
      print('[ha] WebSocket connected, waiting for auth_required…');
      _subscription = _ws!.listen(
        _onMessage,
        onError: (e) {
          print('[ha] WebSocket error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          final code = _ws?.closeCode;
          final reason = _ws?.closeReason;
          print('[ha] WebSocket closed (code=$code, reason=$reason)');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('[ha] WebSocket.connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic>? msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;
    // Verbose logging for debugging the WebSocket protocol.
    // Suppress noisy ping/pong/result (result logged in _handleResult).
    if (type != 'ping' && type != 'pong' && type != 'result') {
      print('[ha] RX: ${_truncate(data)}');
    }
    switch (type) {
      case 'auth_required':
        // Send credentials.
        print('[ha] Sending auth…');
        _sendRaw({'type': 'auth', 'access_token': _token});
        break;

      case 'auth_ok':
        print('[ha] Auth OK — subscribing…');
        _reconnectAttempts = 0;
        _setConnected(true);
        // Fetch the current state immediately, then subscribe to changes.
        _getStates();
        _subscribeStateChanged();
        break;

      case 'auth_invalid':
        print('[ha] Auth INVALID — stopping.');
        // Bad token — no point reconnecting with the same credentials.
        _setConnected(false);
        _cleanupConnection();
        break;

      case 'ping':
        // HA sends periodic pings; we must respond with pong or the server
        // closes the connection after the timeout (default 30s).
        // HA pings include the message id we must echo back.
        _sendRaw({'type': 'pong', 'id': msg['id']});
        break;

      case 'pong':
        // Response to our own ping (if we ever send one). Nothing to do.
        break;

      case 'result':
        _handleResult(msg);
        break;

      case 'event':
        _handleEvent(msg);
        break;
    }
  }

  /// Truncate a raw JSON string for compact logging.
  String _truncate(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  /// Send a message without tracking its id (used for auth, pong).
  void _sendRaw(Map<String, dynamic> payload) {
    if (_ws == null) return;
    try {
      _ws!.add(jsonEncode(payload));
    } catch (_) {
      // ignore — socket will trigger reconnect via onDone
    }
  }

  /// Send a tracked message (get_states, subscribe_events) and record its id.
  void _send(Map<String, dynamic> payload) {
    if (_ws == null) return;
    final id = _nextId++;
    final enriched = <String, dynamic>{'id': id, ...payload};
    _pendingResults[id] = payload['type'] as String?;
    try {
      _ws!.add(jsonEncode(enriched));
    } catch (_) {
      // ignore — socket will trigger reconnect via onDone
    }
  }

  final Map<int, String?> _pendingResults = {};

  void _getStates() {
    _send({'type': 'get_states'});
  }

  void _subscribeStateChanged() {
    _send({'type': 'subscribe_events', 'event_type': 'state_changed'});
  }

  void _handleResult(Map<String, dynamic> msg) {
    final id = msg['id'] as int?;
    if (id == null) return;
    final requestType = _pendingResults.remove(id);
    print('[ha] Result id=$id type=$requestType success=${msg['success']}');
    if (requestType == 'get_states' && msg['success'] == true) {
      // HA returns the entity list directly in the top-level "result" field
      // (not nested under a sub-key).
      final result = msg['result'];
      if (result is List) {
        print('[ha] get_states: ${result.length} entities');
        for (final entity in result) {
          if (entity is Map<String, dynamic> && entity['entity_id'] == _entityId) {
            final state = _parseEntity(entity);
            if (state != null) {
              print('[ha] Initial state: ${describeState(state)}');
              onState?.call(state);
            }
            break;
          }
        }
      }
    } else if (requestType == 'subscribe_events') {
      print('[ha] subscribe_events ${msg['success'] == true ? "confirmed" : "FAILED"}');
    }
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final event = msg['event'];
    if (event is! Map<String, dynamic>) return;
    final data = event['data'];
    if (data is! Map<String, dynamic>) return;
    final evtEntityId = data['entity_id'];
    // Only process state changes for our configured entity.
    if (evtEntityId != _entityId) return;

    final newState = data['new_state'];
    if (newState is! Map<String, dynamic>) return;
    final state = _parseEntity(newState);
    print('[ha] Live update: ${describeState(state)}');
    if (state != null) onState?.call(state);
  }

  HaLightState? _parseEntity(Map<String, dynamic> entity) {
    final stateStr = entity['state'] as String?;
    if (stateStr == null) return null;
    final attributes = entity['attributes'];
    int? brightness;
    if (attributes is Map<String, dynamic>) {
      final b = attributes['brightness'];
      if (b is num) {
        brightness = b.round().clamp(0, 255);
      }
    }
    return HaLightState(
      on: stateStr == 'on',
      brightness: brightness,
    );
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectionChange?.call(value);
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setConnected(false);
    _cleanupConnection();

    _reconnectAttempts++;
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
    _pendingResults.clear();
  }

  String? _toWsUrl(String httpBaseUrl) {
    final trimmed = httpBaseUrl.trim();
    if (trimmed.isEmpty) return null;
    var ws = trimmed.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    // Ensure path ends with /api/websocket
    if (!ws.endsWith('/api/websocket')) {
      ws = ws.endsWith('/') ? '${ws}api/websocket' : '$ws/api/websocket';
    }
    return ws;
  }

  /// Format an HaLightState into a human-readable description for the test
  /// result message, including brightness when available.
  static String describeState(HaLightState? state) {
    if (state == null) return '';
    if (!state.on) return 'off';
    if (state.brightness != null) {
      return 'on (brightness ${state.brightness}/255 = ${state.brightnessPercent}%)';
    }
    return 'on';
  }

  // --------------------------------------------------------------------------
  // Connection testing
  // --------------------------------------------------------------------------

  /// Open a one-shot connection to verify the credentials and that the entity
  /// exists. Closes the socket and returns a human-readable result.
  ///
  /// This does NOT touch the persistent subscription managed by [connect].
  Future<HaConnectionResult> testConnection({
    required String httpBaseUrl,
    required String token,
    required String entityId,
  }) async {
    final wsUrl = _toWsUrl(httpBaseUrl);
    if (wsUrl == null || token.isEmpty || entityId.isEmpty) {
      return const HaConnectionResult(
        success: false,
        message: 'URL, token and entity ID are required.',
      );
    }

    WebSocket? socket;
    final completer = Completer<HaConnectionResult>();
    int? getStatesId;
    bool authOk = false;

    try {
      socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));

      final sub = socket.listen(
        (data) {
          if (data is! String || completer.isCompleted) return;
          Map<String, dynamic>? msg;
          try {
            msg = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          final type = msg['type'] as String?;
          switch (type) {
            case 'auth_required':
              socket?.add(jsonEncode({'type': 'auth', 'access_token': token}));
              break;
            case 'auth_ok':
              authOk = true;
              getStatesId = _nextId++;
              socket?.add(jsonEncode({'id': getStatesId, 'type': 'get_states'}));
              break;
            case 'auth_invalid':
              if (!completer.isCompleted) {
                completer.complete(const HaConnectionResult(
                  success: false,
                  message: 'Authentication failed: invalid or expired token.',
                ));
              }
              break;
            case 'ping':
              // Respond to keep-alive ping during the test handshake.
              socket?.add(jsonEncode({'type': 'pong', 'id': msg['id']}));
              break;
            case 'result':
              final id = msg['id'] as int?;
              if (id == getStatesId && !completer.isCompleted) {
                if (authOk && msg['success'] == true) {
                  final result = msg['result'];
                  HaLightState? found;
                  bool exists = false;
                  if (result is List) {
                    for (final entity in result) {
                      if (entity is Map<String, dynamic> && entity['entity_id'] == entityId) {
                        exists = true;
                        found = _parseEntity(entity);
                        break;
                      }
                    }
                  }
                  if (!exists) {
                    completer.complete(HaConnectionResult(
                      success: false,
                      message: 'Entity "$entityId" not found.',
                    ));
                  } else {
                    completer.complete(HaConnectionResult(
                      success: true,
                      message: 'Connected. Entity "$entityId" is ${describeState(found)}.',
                      state: found,
                    ));
                  }
                } else {
                  completer.complete(HaConnectionResult(
                    success: false,
                    message: msg['error']?['message']?.toString() ?? 'Request failed.',
                  ));
                }
              }
              break;
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.complete(HaConnectionResult(
              success: false,
              message: 'Connection error: $e',
            ));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(HaConnectionResult(
              success: false,
              message: authOk
                  ? 'Connection closed unexpectedly.'
                  : 'Could not reach Home Assistant at $httpBaseUrl.',
            ));
          }
        },
        cancelOnError: true,
      );

      // Timeout guard for the whole handshake + get_states.
      Future.delayed(const Duration(seconds: 8), () {
        if (!completer.isCompleted) {
          completer.complete(const HaConnectionResult(
            success: false,
            message: 'Timed out waiting for a response from Home Assistant.',
          ));
        }
      });

      final result = await completer.future;
      await sub.cancel();
      return result;
    } catch (e) {
      try {
        await socket?.close();
      } catch (_) {}
      return HaConnectionResult(
        success: false,
        message: 'Could not connect to $httpBaseUrl: $e',
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
