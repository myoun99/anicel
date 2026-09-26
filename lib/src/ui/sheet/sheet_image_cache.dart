import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../services/import/raster_cel_import.dart' show readImageFileOrNull;

/// The decoded media images the sheets print, by asset path — the company
/// logo (the conte's body pages and the envelope) and the conte's cover
/// picture.
///
/// 🚨THE PAINTER ASKS SYNCHRONOUSLY. A sheet painter's `imageFor` returns a
/// `ui.Image?` right now — it is inside a paint pass and cannot await — so a
/// path it has never seen answers null ONCE, the decode runs off to the side,
/// and the cache NOTIFIES when there is something to draw. A painter hands
/// it to its `repaint`: its compared inputs do not change when a picture
/// lands, so nothing else would bring the frame back. ↩️It used to call back
/// into the workspace, which rebuilt everything — and the painters, seeing
/// equal inputs, did not repaint: a logo showed only after the next pan.
///
/// ⛔A miss is remembered too. A path that fails to decode (deleted file,
/// something that is not an image) must not be retried every paint: that
/// would read the disk on every frame and never succeed. `_images` holding a
/// null IS the memory of that, which is why the lookup asks
/// `containsKey` rather than testing the value.
///
/// ⚠️Sheet images are a handful — a logo, a cover picture — and each
/// decodes once for the life of the workspace. This is not
/// a general image cache and has no eviction; if it ever holds cels it
/// needs one.
class SheetImageCache extends ChangeNotifier {
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
    // A picture whose file went away is not an error the user can act on from
    // here — the sheet simply prints the empty box.
    final image = await readImageFileOrNull(assetPath);
    if (_disposed) {
      image?.dispose();
      return;
    }
    _images[assetPath] = image;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image?.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
