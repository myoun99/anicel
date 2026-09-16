import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';

import '../../models/rgba_image_bytes.dart' show estimatedImageBytes;

/// 🚨★★★ (v) 1단계 — THE PART OF THE COMPOSITE A STROKE CANNOT CHANGE,
/// recorded once and replayed.
///
/// 실측①: one stroke step re-runs the WHOLE composite tree — the paper,
/// every cached layer image, every folder's own offscreen, every effect chain
/// — because `_LayerStackPainter`'s repaint Listenable is the active
/// surface. Everything in that tree except the active layer is static for
/// the duration of the stroke, and this is what stops re-deriving it.
///
/// ★**Pictures, not images.** The obvious reading of "bake" is
/// `toImage()`, and it is the wrong one here:
/// - `PictureRecorder.endRecording()` is **synchronous**. `toImage()` is
///   not, and a stroke cannot wait a frame for its own backdrop
///   ([[stale-tile-flicker-program]] is the record of that hazard).
/// - What a stroke actually pays for in a DEBUG build is the **Dart-side
///   walk**: the switch, `resolveCompositeEffectPaint`, the `saveLayer`
///   calls. `drawPicture` skips exactly that and hands the engine a
///   display list. GPU work is unchanged, which is the right trade when
///   the bar is 「윈도우 디버그」 (유저 2026-08-14).
/// - A display list costs ~nothing resident. A full-resolution image is
///   15.5MB, and picking its resolution is a question stage 2 has to
///   answer — no reason for stage 1 to answer it early.
///
/// ⚠️A recorded picture holds REFERENCES to the `ui.Image`s it draws. The
/// stack view clones those and disposes the clones when a layer's request
/// changes, so a picture that outlives a dispose replays a dead handle.
/// That is why [revision] exists and why the owner bumps it at the dispose
/// sites themselves rather than trusting a comparison to notice.
class StaticCompositeBake {
  final Map<String, ui.Picture> _slots = {};
  final Map<String, ui.Image> _rasters = {};

  /// Told whenever [heldBytes] changes. The view that owns this bake reports
  /// it together with its display buffer — both are that view holding a
  /// raster of itself, and the census cannot reach a widget State.
  void Function()? onHeldBytesChanged;

  int _heldBytes = 0;

  /// What the rasterised slots cost resident: one visible-rect image each
  /// (~9MB at a 1928×1200 view). Counted since 2026-09-11 — until then the
  /// memory readout never saw them.
  int get heldBytes => _heldBytes;

  /// What the current slots were recorded against. Null means "nothing
  /// recorded yet".
  Object? _key;

  /// The visible-rect world the recordings were made in.
  ///
  /// 🚨A3 — THE RECORDINGS DEPEND ON THE EXTENT AND THE KEY CANNOT SAY SO.
  /// [keepFor]'s key is built at BUILD time from widget fields, but the
  /// visible rect is a LAYOUT fact: resize the panel at a fixed zoom and
  /// the key is unchanged while every recording is wrong — the record
  /// closures captured the old `groupBounds` (folder raster bounds,
  /// adjustment scope bounds), and [drawRaster] would take the OLD image
  /// and blit it with a src rect computed from the NEW dimensions. Same
  /// document, two pictures, decided by resize history — the render must
  /// be a function of (artwork, viewport, canvas size), never of what the
  /// panel did five minutes ago.
  Rect? _extent;

  /// Declares the paint-time extent. A change drops the recordings — but
  /// NOT the key: the key is still true, and clearing it would make the
  /// next build's [keepFor] invalidate a second time, throwing away the
  /// slots this very paint just re-recorded.
  void ensureExtent(Rect extent) {
    if (_extent == extent) {
      return;
    }
    _extent = extent;
    _dropRecordings();
  }

  /// Drops every recorded slot. Cheap and always safe: the next paint
  /// re-records, which is exactly what the code did before this existed.
  void invalidate() {
    _dropRecordings();
    _key = null;
    _extent = null;
  }

  void _dropRecordings() {
    for (final picture in _slots.values) {
      picture.dispose();
    }
    _slots.clear();
    for (final image in _rasters.values) {
      image.dispose();
    }
    _rasters.clear();
    if (_heldBytes != 0) {
      _heldBytes = 0;
      onHeldBytesChanged?.call();
    }
  }

  /// Keeps the slots only while [key] is unchanged.
  ///
  /// The owner calls this once per build with everything the recording
  /// depended on. Anything left out of [key] is a slot that goes stale
  /// silently, so it is deliberately the SAME set `shouldRepaint` compares
  /// plus the image revision.
  void keepFor(Object key) {
    if (_key == key) {
      return;
    }
    invalidate();
    _key = key;
  }

  /// Replays slot [id], recording it first if this is its first paint under
  /// the current key.
  ///
  /// [record] must issue exactly the ops it would have issued straight onto
  /// [canvas]. It is recorded from an identity transform and replayed under
  /// whatever transform is current — which is equivalent because the paint
  /// body never reads the transform, only writes to it.
  void draw(Canvas canvas, String id, void Function(Canvas canvas) record) {
    final held = _slots[id];
    if (held != null) {
      canvas.drawPicture(held);
      return;
    }
    final recorder = ui.PictureRecorder();
    record(Canvas(recorder));
    _recordCount += 1;
    final picture = recorder.endRecording();
    _slots[id] = picture;
    canvas.drawPicture(picture);
  }

  /// Replays slot [id] as a RASTER over [rect], rasterising it once.
  ///
  /// 🚨★★★ (v) 2단계 후반부 — WHY A PICTURE IS NOT ENOUGH DOWN HERE.
  ///
  /// A picture skips the Dart-side walk, which was stage 1's whole point.
  /// What it does NOT skip is the ENGINE replaying the display list: with
  /// 500 layers below the active one, every stroke step still re-executes
  /// 500 draws. A raster is one blit however many layers went into it — the
  /// difference between a heavy document being heavy per STROKE STEP and
  /// being heavy once (유저 2026-08-15:
  /// 「1500컷이나 500개레이어같은 무거운상황도 생각하면서 가볍게 하고싶다니까?」).
  ///
  /// ⚠️A FOLDER IS NO LONGER PART OF THAT COST. This used to read "and every
  /// folder's `saveLayer`" — true while a group WAS one, because replaying
  /// the picture re-executed the offscreen every frame. A group rasterises
  /// to a `ui.Image` now and a recorded picture holds its own reference to
  /// what it draws, so the replay redraws a finished image and the folder's
  /// own raster happens ONCE. 🧪Counted: one folder, four stroke steps, one
  /// raster (`the_bake_is_the_group_cache_test`). That IS the per-group
  /// cache, and it is why a second one would be a copy.
  ///
  /// ⛔ONLY SOUND WITH NOTHING BENEATH IT. Replaying a picture applies its
  /// blend modes against whatever is already on the destination; flattening
  /// it into an image and drawing that `srcOver` does not. This is for the
  /// BOTTOM of the stack — the paper plus the siblings below the chain that
  /// encloses the live surface — where the destination is empty and the two
  /// are identical. A slot ABOVE the live surface may hold a multiply that
  /// has to see the stroke, and stays a picture.
  ///
  /// ⚠️Costs one visible-rect image resident (~9MB at a 1928×1200 view), and
  /// it is keyed like everything else here: [keepFor] drops it, so a changed
  /// layer, a new image revision or a viewport move all re-rasterise. Those
  /// are not stroke steps, which is what makes it the right trade.
  ///
  /// [rasterScale] is the buffer's own scale — 1 at canvas resolution,
  /// 1/2^level inside a level buffer (2026-09-16): the raster is made in
  /// the buffer's pixels so its blit back is 1:1 there, whatever the level.
  void drawRaster(
    Canvas canvas,
    String id,
    Rect rect,
    void Function(Canvas canvas) record, {
    double rasterScale = 1,
  }) {
    final width = (rect.width * rasterScale).round();
    final height = (rect.height * rasterScale).round();
    if (width <= 0 || height <= 0) {
      return;
    }
    var held = _rasters[id];
    if (held == null) {
      final recorder = ui.PictureRecorder();
      final into = Canvas(recorder);
      into.scale(rasterScale);
      into.translate(-rect.left, -rect.top);
      record(into);
      _recordCount += 1;
      final picture = recorder.endRecording();
      try {
        held = picture.toImageSync(width, height);
      } finally {
        picture.dispose();
      }
      _rasters[id] = held;
      _heldBytes += estimatedImageBytes(width, height);
      onHeldBytesChanged?.call();
    }
    canvas.drawImageRect(
      held,
      Rect.fromLTWH(0, 0, held.width.toDouble(), held.height.toDouble()),
      rect,
      // 1:1 — the raster is in the buffer's own pixels over the very rect
      // it is drawn into, so there is no resampling here to have a quality.
      // The one resample this stack is entitled to happens when the display
      // buffer meets the viewport transform.
      Paint()..filterQuality = ui.FilterQuality.none,
    );
  }

  void dispose() => invalidate();

  /// Recorded slot count — the seam the cost test reads.
  @visibleForTesting
  int get slotCount => _slots.length;

  /// Rasterised slot count — the seam that says a heavy stack collapsed into
  /// one blit instead of N draws.
  @visibleForTesting
  int get rasterCount => _rasters.length;

  /// Recordings made since this bake was created, pictures and rasters
  /// alike — the seam that tells a replay from a re-record. The slot counts
  /// cannot: a drop followed by the same paint leaves them where they were.
  @visibleForTesting
  int get recordCount => _recordCount;
  int _recordCount = 0;
}
