import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';

/// 🚨★★★ (v) 1단계 — THE PART OF THE COMPOSITE A STROKE CANNOT CHANGE,
/// recorded once and replayed.
///
/// 실측①: one stroke step re-runs the WHOLE composite tree — the paper,
/// every cached layer image, every folder's `saveLayer`, every effect chain
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

  /// What the current slots were recorded against. Null means "nothing
  /// recorded yet".
  Object? _key;

  /// The visible-rect world the recordings were made in.
  ///
  /// 🚨A3 — THE RECORDINGS DEPEND ON THE EXTENT AND THE KEY CANNOT SAY SO.
  /// [keepFor]'s key is built at BUILD time from widget fields, but the
  /// visible rect is a LAYOUT fact: resize the panel at a fixed zoom and
  /// the key is unchanged while every recording is wrong — the record
  /// closures captured the old `groupBounds` (folder `saveLayer` hints,
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
  /// 500 draws and every folder's `saveLayer`. A raster is one blit however
  /// many layers went into it — the difference between a heavy document
  /// being heavy per STROKE STEP and being heavy once (유저 2026-08-15:
  /// 「1500컷이나 500개레이어같은 무거운상황도 생각하면서 가볍게 하고싶다니까?」).
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
  void drawRaster(
    Canvas canvas,
    String id,
    Rect rect,
    void Function(Canvas canvas) record,
  ) {
    final width = rect.width.round();
    final height = rect.height.round();
    if (width <= 0 || height <= 0) {
      return;
    }
    var held = _rasters[id];
    if (held == null) {
      final recorder = ui.PictureRecorder();
      final into = Canvas(recorder);
      into.translate(-rect.left, -rect.top);
      record(into);
      final picture = recorder.endRecording();
      try {
        held = picture.toImageSync(width, height);
      } finally {
        picture.dispose();
      }
      _rasters[id] = held;
    }
    canvas.drawImageRect(
      held,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      rect,
      // 1:1 — the raster is at canvas resolution over the very rect it is
      // drawn into, so there is no resampling here to have a quality. The
      // one resample this stack is entitled to happens when the display
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
}
