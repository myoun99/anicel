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

  /// What the current slots were recorded against. Null means "nothing
  /// recorded yet".
  Object? _key;

  /// Drops every recorded slot. Cheap and always safe: the next paint
  /// re-records, which is exactly what the code did before this existed.
  void invalidate() {
    for (final picture in _slots.values) {
      picture.dispose();
    }
    _slots.clear();
    _key = null;
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

  void dispose() => invalidate();

  /// Recorded slot count — the seam the cost test reads.
  @visibleForTesting
  int get slotCount => _slots.length;
}
