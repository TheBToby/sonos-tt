import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// In-memory artwork cache for smoother transitions between tracks.
///
/// On web, Sonos artwork URLs (http://<lan-ip>:1400/getaa?…) cannot be
/// fetched by the browser directly (mixed content from an HTTPS page).
/// They are transparently remapped to the same-origin proxy
/// `/soco-art?url=<encoded>` served by deploy/coder-web-server.py.
class ArtworkCache {
  final _cache = <String, Uint8List>{};
  static const maxEntries = 12;

  /// Remaps a Sonos artwork URL for the current platform.
  /// Native: unchanged. Web: same-origin /soco-art proxy.
  static String resolveArtworkUrl(String url) {
    if (!kIsWeb || url.isEmpty) return url;
    if (url.startsWith('http://')) {
      return '/soco-art?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }

  Future<Uint8List?> get(String url) async {
    if (url.isEmpty) return null;
    final fetchUrl = resolveArtworkUrl(url);
    if (_cache.containsKey(url)) return _cache[url];
    try {
      final response = await http
          .get(Uri.parse(fetchUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final bytes = response.bodyBytes;
      _cache[url] = bytes;
      if (_cache.length > maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  bool isReady(String url) => url.isNotEmpty && _cache.containsKey(url);

  void clear() => _cache.clear();
}