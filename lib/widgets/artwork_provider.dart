import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../services/artwork_cache.dart';

/// Image provider that loads artwork from a URL via [ArtworkCache] (which
/// caches the raw bytes) and lets Flutter's [ImageCache] handle caching of
/// the decoded image.
///
/// **Critical**: [operator ==] and [hashCode] are defined based on [url]
/// so that [ImageCache] reuses the same completer across rebuilds. Without
/// these overrides, a new provider/key would be created on each track
/// change, causing the old completer to be disposed while [ImageCache]
/// still holds a reference — producing the "Bad state: Stream has been
/// disposed" error.
class ArtworkImageProvider extends ImageProvider<ArtworkImageProvider> {
  final String url;
  final ArtworkCache cache;

  ArtworkImageProvider(this.url, this.cache);

  @override
  Future<ArtworkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ArtworkImageProvider>(this);

  @override
  bool operator ==(Object other) => other is ArtworkImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  ImageStreamCompleter loadImage(
    ArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
    ArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await key.cache.get(key.url);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('No artwork data for ${key.url}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }
}
