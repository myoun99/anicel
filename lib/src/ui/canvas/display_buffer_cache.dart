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

  /// The part of the key that does not move with the live surface, kept
  /// apart so a stroke step can still recognise its own previous frame.
  Object? _staticKey;

  /// What the live surface looked like when the kept image was made, so the
  /// next paint can say WHERE it changed.
  ///
  /// 🚨Here rather than on the painter, and that is forced: a
  /// `CustomPainter` is a fresh object every frame, and a stroke step
  /// repaints WITHOUT a widget rebuild, so neither the painter nor `build`
  /// can hold a "since last time". This object is the only thing on that
  /// path that outlives a frame.
  /// Overlay coordinate → the tile IMAGE it held, so the next paint can
  /// say which tiles a dab actually touched. A bare coordinate SET here
  /// made every step dirty the whole stroke's bounding box — the overlay
  /// accumulates for the stroke's life, so membership alone says "part of
  /// the stroke", not "changed since last paint".
  Map<Object, Object> lastOverlayTokens = const {};
  Map<Object, Object> lastTileTokens = const {};


  /// The kept image for [key] over [rect], or null when there is none.
  ui.Image? imageFor(Object key, Rect rect) {
    if (_key == key && _rect == rect) {
      return _image;
    }
    return null;
  }

  /// Keeps [image] as the answer for [key] over [rect], dropping whatever
  /// was there.
  ///
  /// [staticKey] is the part of [key] that does NOT move with the live
  /// surface: the layer tree, the viewport, the paper. Keeping it apart is
  /// what makes [patchBaseFor] possible — a stroke step changes the live
  /// half and nothing else, and that is the one case where the previous
  /// image is still worth something.
  /// How many stored images were built by PATCHING the previous one, and
  /// how many were composited from nothing.
  ///
  /// 🚨A counter rather than an argument about the design: an optimisation
  /// that never runs looks exactly like one that works, and this session
  /// shipped two that did not (a tile grid whose key never matched, and a
  /// walk that hashed every tile and still missed). The test asserts the
  /// SECOND stroke step patches — if the dirty rect stops being found, this
  /// number says so instead of the frame rate saying it later.
  ///
  /// Not test-only: the geometry field probe reports both in RELEASE
  /// builds (behind the Input Inspector toggle), because "the patch path
  /// stopped running" is precisely the regression a hands-on report needs
  /// to be able to show.
  int patchedCount = 0;
  int fullCount = 0;

  /// The dirty rect the last compose was confined to (canvas space, after
  /// the hairline inflate); null when the compose was full. Probe surface
  /// like the counters: a patch that quietly grows back to the stroke's
  /// whole bounding box is invisible in `patchedCount` — it still counts
  /// as one patch — and THIS is what says how big that patch really was.
  Rect? lastDirtyRect;

  /// ⓔ 5단계 probe: the resolved scale of the last SCALED (below-knee)
  /// store. The s=1 path never touches it — it answers "when the knee
  /// path last ran, what s did it run at", because a scaled path that
  /// silently stops running looks exactly like one that works (the
  /// counters' own law).
  double? lastBufferScale;

  void store(
    Object key,
    Object staticKey,
    Rect rect,
    ui.Image image, {
    bool patched = false,
  }) {
    if (patched) {
      patchedCount += 1;
    } else {
      fullCount += 1;
    }
    if (!identical(_image, image)) {
      _image?.dispose();
    }
    _image = image;
    _rect = rect;
    _key = key;
    _staticKey = staticKey;
  }

  /// The previous image, when the only thing that moved since is the LIVE
  /// surface — so redrawing the dirty part over it is the same picture as
  /// compositing the whole thing again.
  ///
  /// 🚨★★★THIS IS WHAT REPLACED THE TILE GRID. Tiling split the buffer to
  /// avoid recompositing all of it per stroke step; it also gave every
  /// boundary a seam at fractional scale, and made a cold cache cost N
  /// rasters instead of one. Patching the whole buffer keeps the ONE image
  /// (so there is no boundary to seam) and the cold path is untouched (so
  /// the worst case is still today's) — the recomposite is confined to the
  /// dirty rect either way, which was the only thing tiles were for.
  ///
  /// ⛔Null unless [staticKey] AND [rect] both match: a changed layer tree
  /// or a moved viewport means the old pixels are wrong everywhere, not
  /// just where the stroke went.
  ({ui.Image image, Rect rect})? patchBaseFor(Object staticKey, Rect rect) {
    final image = _image;
    if (image == null || _staticKey != staticKey || _rect != rect) {
      return null;
    }
    return (image: image, rect: rect);
  }

  /// The kept image and the rect it ALREADY covers, when the extent has
  /// MOVED but the content behind it has not — a pan, or a zoom that slid
  /// the window over the same picture.
  ///
  /// 🚨★★★A PAN CARRIES WHAT IT ALREADY HAD. [patchBaseFor] refuses a moved
  /// rect, because for a stroke step a moved rect means the old pixels are
  /// in the wrong place. They are not WRONG, though — they are OFFSET. The
  /// buffer is canvas resolution, so one buffer pixel is one canvas pixel at
  /// every zoom, and the overlap can be blitted to its new home exactly.
  /// What is left to composite is the band the pan exposed.
  ///
  /// ⛔ONE IMAGE STILL. The blit and the band land in the SAME recorder and
  /// come out as one `toImageSync` — there is no second image at paint time,
  /// so there is no boundary for a fractional scale to seam (which is what
  /// the tile grid was rejected for, and what a base-plus-patch draw would
  /// bring back).
  ///
  /// ⚠️THE LIVE SURFACE IS NOT IN [staticKey] ON PURPOSE, so the carried
  /// pixels can hold a stale live layer. The caller composites the live
  /// dirty rect along with the exposed band, and must refuse the carry when
  /// it cannot say where the live surface changed.
  ({ui.Image image, Rect rect})? scrollBaseFor(Object staticKey, Rect rect) {
    final image = _image;
    final was = _rect;
    if (image == null || was == null || _staticKey != staticKey) {
      return null;
    }
    if (was == rect) {
      // Not moved: that is [patchBaseFor]'s case, and it knows more.
      return null;
    }
    final overlap = was.intersect(rect);
    if (overlap.isEmpty || overlap.width <= 0 || overlap.height <= 0) {
      return null;
    }
    return (image: image, rect: was);
  }

  /// How many stores carried a moved buffer instead of compositing it whole.
  ///
  /// 🚨The counters' own law: an optimisation that never runs looks exactly
  /// like one that works.
  int scrolledCount = 0;

  /// The canvas-space AREA the last carry actually composited.
  ///
  /// 🚨THE COUNTER SAYS THE CARRY RAN; THIS SAYS IT SAVED SOMETHING. A carry
  /// that blits the overlap and then composites the whole rect anyway is
  /// correct, costs what it always did, and is invisible in every pixel test
  /// — 🧪a mutation shipped exactly that and stayed green.
  double? lastComposedArea;

  void invalidate() {
    _image?.dispose();
    _image = null;
    _rect = null;
    _key = null;
    _staticKey = null;
    // ⛔The snapshots go with the image. Kept across an invalidate they would
    // describe a frame nobody holds any more, and the next paint would
    // "find" a small dirty rect against a base that no longer exists.
    lastOverlayTokens = const {};
    lastTileTokens = const {};
  }

  void dispose() => invalidate();

  /// Whether anything is kept — the seam a cost test reads.
  @visibleForTesting
  bool get isWarm => _image != null;
}
