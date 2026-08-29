import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The decoded logo and 도장 the cut envelope prints, by asset path.
///
/// 🚨THE PAINTER ASKS SYNCHRONOUSLY. `CutEnvelopePainter.imageFor` returns a
/// `ui.Image?` right now — it is inside a paint pass and cannot await — so a
/// path it has never seen answers null ONCE, the decode runs off to the side,
/// and [onLoaded] brings the frame back when there is something to draw.
///
/// ⛔A miss is remembered too. A path that fails to decode (deleted file,
/// something that is not an image) must not be retried every paint: that
/// would read the disk on every frame and never succeed. `_images` holding a
/// null IS the memory of that, which is why the lookup asks
/// `containsKey` rather than testing the value.
///
/// ⚠️Envelope images are a handful — one logo and one stamp per role — and
/// each decodes once for the life of the workspace. This is not a general
/// image cache and has no eviction; if it ever holds cels it needs one.
class EnvelopeImageCache {
  EnvelopeImageCache({required this.onLoaded});

  /// Called after a decode lands, so the host can repaint with it.
  final VoidCallback onLoaded;

  final Map<String, ui.Image?> _images = <String, ui.Image?>{};

  /// The image for [assetPath], or null while it is still being read — and
  /// null forever if it cannot be read.
  ui.Image? imageFor(String assetPath) {
    if (_images.containsKey(assetPath)) {
      return _images[assetPath];
    }
    // Claimed before the await, so a second paint in the same frame does not
    // start the same decode twice.
    _images[assetPath] = null;
    unawaited(_load(assetPath));
    return null;
  }

  Future<void> _load(String assetPath) async {
    ui.Image? image;
    try {
      final bytes = await File(assetPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Object {
      // A stamp whose file went away is not an error the user can act on
      // from here — the envelope simply prints the empty box, which is the
      // same thing it printed before anyone chose one.
      image = null;
    }
    if (_disposed) {
      image?.dispose();
      return;
    }
    _images[assetPath] = image;
    onLoaded();
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image?.dispose();
    }
    _images.clear();
  }
}
