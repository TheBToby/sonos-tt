import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../services/artwork_cache.dart';

/// Image provider that caches the [ImageStreamCompleter] by URL so that
/// repeated provider instances for the same URL return the **same**
/// completer. This prevents Flutter's [Image] widget from creating a new
/// stream on every 16 ms animation-frame rebuild, which would otherwise
/// cause flickering and "disposed image" errors.
///
/// [OneFrameImageStreamCompleter] cannot be used here because it disposes
/// the image after a single delivery, making it incompatible with caching
/// the decoded image across rebuilds.
class ArtworkImageProvider extends ImageProvider<ArtworkImageProvider> {
  final String url;
  final ArtworkCache cache;

  /// Cache of stream completers keyed by URL.
  /// [MultiFrameImageStreamCompleter] handles multiple listeners safely.
  static final Map<String, ImageStreamCompleter> _completerCache = {};

  ArtworkImageProvider(this.url, this.cache);

  @override
  Future<ArtworkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ArtworkImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(ArtworkImageProvider key, ImageDecoderCallback decode) {
    final existing = _completerCache[url];
    if (existing != null) return existing;

    final completer = MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      informationCollector: () sync* {
        yield ErrorDescription('ArtworkImageProvider: $url');
      },
    );
    _completerCache[url] = completer;
    return completer;
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final bytes = await cache.get(url);
      if (bytes == null || bytes.isEmpty) {
        _completerCache.remove(url);
        throw Exception('No artwork data for $url');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      _completerCache.remove(url);
      rethrow;
    }
  }

  /// Remove a single URL from the completer cache.
  static void evictUrl(String url) {
    _completerCache.remove(url);
  }

  /// Clear the entire completer cache (e.g. on config change).
  static void clearCache() {
    _completerCache.clear();
  }
}
