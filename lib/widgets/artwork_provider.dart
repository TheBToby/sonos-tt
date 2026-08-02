import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../services/artwork_cache.dart';

/// Image provider that caches the decoded [ui.Image] by URL so that repeated
/// provider instances for the same URL return the same image synchronously
/// via [OneFrameImageStreamCompleter] — preventing flicker when the widget
/// rebuilds every 16ms during the turntable spin animation.
///
/// The cached [ui.Image] is cloned before wrapping in [ImageInfo] so that
/// [OneFrameImageStreamCompleter] can safely dispose its own handle without
/// invalidating the cached original.
class ArtworkImageProvider extends ImageProvider<ArtworkImageProvider> {
  final String url;
  final ArtworkCache cache;

  /// Static cache of decoded images keyed by URL.
  static final Map<String, ui.Image> _imageCache = {};

  ArtworkImageProvider(this.url, this.cache);

  @override
  Future<ArtworkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ArtworkImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(ArtworkImageProvider key, ImageDecoderCallback decode) {
    // If we already have a decoded image for this URL, clone it and return
    // it synchronously via OneFrameImageStreamCompleter. This avoids
    // re-decoding the same bytes on every animation frame.
    final cached = _imageCache[url];
    if (cached != null) {
      final cloned = cached.clone();
      final imageInfo = ImageInfo(image: cloned, scale: 1.0);
      return OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(imageInfo),
        informationCollector: () sync* {
          yield ErrorDescription('ArtworkImageProvider: cached $url');
        },
      );
    }

    // First load: fetch bytes, decode, cache the image, then deliver it.
    return OneFrameImageStreamCompleter(
      _loadAndCache(decode),
      informationCollector: () sync* {
        yield ErrorDescription('ArtworkImageProvider: $url');
      },
    );
  }

  Future<ImageInfo> _loadAndCache(ImageDecoderCallback decode) async {
    final bytes = await cache.get(url);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('No artwork data for $url');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    // Cache the decoded image for future rebuilds.
    _imageCache[url] = frame.image;
    return ImageInfo(image: frame.image, scale: 1.0);
  }

  /// Remove a single URL from the image cache and dispose its image.
  static void evictUrl(String url) {
    final image = _imageCache.remove(url);
    image?.dispose();
  }

  /// Clear the entire image cache (e.g. on config change).
  static void clearCache() {
    for (final image in _imageCache.values) {
      image.dispose();
    }
    _imageCache.clear();
  }
}
