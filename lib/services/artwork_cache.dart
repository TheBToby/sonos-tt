import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

/// In-memory artwork cache for smoother transitions between tracks.
class ArtworkCache {
  final _cache = <String, Uint8List>{};
  static const maxEntries = 12;

  Future<Uint8List?> get(String url) async {
    if (url.isEmpty || kIsWeb) return null;
    if (_cache.containsKey(url)) return _cache[url];
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final builder = BytesBuilder();
      await for (final chunk in response) {
        builder.add(chunk);
      }
      client.close();
      final bytes = builder.toBytes();
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