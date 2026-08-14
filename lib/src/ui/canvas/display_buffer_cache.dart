import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';

/// 🚨★★★ (v) — THE COMPOSITE BUFFER, KEPT WHILE NOTHING HAS CHANGED.
///
/// The single buffer made sampling a property of the display: everything
/// composites at canvas resolution and the finished image is resampled
/// ONCE. What it did not do was remember: every paint rasterised the whole
/// visible rect again, including the paints where nothing had moved — a
/// hover, a cursor blink, a neighbouring panel's rebuild.
///
/// ⛔A MISS COSTS EXACTLY WHAT TODAY COSTS, and that is the property that
/// makes this safe to try. The tiled buffer that came before it failed on
/// the other side of that line: a cold tile cache rasterised the composite
/// once PER TILE, so the thing meant to make strokes cheap made panning N
/// times dearer, and it had to be reverted. One image cannot do that —
/// worst case it does the work the untiled path already did.
///
/// ⚠️It also cannot go stale silently in a small way: if the key misses
/// something, the whole canvas freezes rather than one corner of it, which
/// is the failure everybody notices in the first second.
class DisplayBufferCache {
  ui.Image? _image;
  Rect? _rect;
  Object? _key;

  /// The kept image for [key] over [rect], or null when there is none.
  ui.Image? imageFor(Object key, Rect rect) {
    if (_key == key && _rect == rect) {
      return _image;
    }
    return null;
  }

  /// Keeps [image] as the answer for [key] over [rect], dropping whatever
  /// was there.
  void store(Object key, Rect rect, ui.Image image) {
    if (!identical(_image, image)) {
      _image?.dispose();
    }
    _image = image;
    _rect = rect;
    _key = key;
  }

  void invalidate() {
    _image?.dispose();
    _image = null;
    _rect = null;
    _key = null;
  }

  void dispose() => invalidate();

  /// Whether anything is kept — the seam a cost test reads.
  @visibleForTesting
  bool get isWarm => _image != null;
}
