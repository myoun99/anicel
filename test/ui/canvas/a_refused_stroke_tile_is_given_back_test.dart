import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

/// 🚨★★★**A REFUSED LIVE-STROKE TILE IS AN ANSWER, AND THE OVERLAY HAD
/// NOWHERE TO PUT ONE.**
///
/// Every tile upload took two things at the start — a seat in `_decoding`
/// and a tick of the pending counter — and gave both back only through
/// `_adoptDecodedTile`, which runs from the decode callback.
/// `ui.decodeImageFromPixels` does not invoke that callback on a refusal
/// (read in the SDK source), so a refused tile kept its seat for the rest
/// of the stroke — every later dab on that coordinate was parked and never
/// drawn — and the counter, which is 「how many engine answers are still
/// owed」, could only ever go up. `waitForPendingDecodes()` then never
/// completed again for the life of the model.
///
/// Both uploads also freed NATIVE memory inside that callback (a scratch,
/// or the pre-blended tile), so a refusal leaked `tileSize² × 4` — 256 KB
/// at the production tile size, per refused tile, with no finalizer behind
/// it.
///
/// 🚨The refusal arrives through [debugRawRgbaUploader] because the engine
/// under `flutter test` simply never refuses — the harness is
/// `flutter_tester`, and CI runs the same one. (This used to say "because
/// Windows runs Skia in every build"; that stopped being true when 3.47
/// made Impeller the desktop default, 2026-09-16, and the harness — not
/// the platform — was always what the seam is for.) See that setter for
/// why a seam is the honest answer here and not a shortcut.
void main() {
  const canvasSize = CanvasSize(width: 24, height: 8);

  BrushDab dabAt(double x) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  ui.Image aSolidImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 8, 8),
      Paint()..color = const Color(0xFF00FF00),
    );
    return recorder.endRecording().toImageSync(8, 8);
  }

  var uploads = 0;

  void installUploader({required bool refuse}) {
    debugRawRgbaUploader =
        (
          Uint8List rgba, {
          required int width,
          required int height,
          int? targetWidth,
          int? targetHeight,
        }) {
          uploads += 1;
          if (refuse) {
            return Future<ui.Image>.error(
              StateError('the engine refused this upload'),
            );
          }
          return Future<ui.Image>.value(aSolidImage());
        };
  }

  setUp(() => uploads = 0);
  tearDown(() => debugRawRgbaUploader = null);

  /// Drives one dab into [overlay] and waits for the engine to answer,
  /// however it answers.
  ///
  /// ⚠️`.timeout` is the point, not tidiness: every mutation this file
  /// kills turns 「the answer arrives」 into 「the answer never comes」, and
  /// an unguarded await would take the whole run down instead of reddening
  /// one test. A hang IS the failure being asserted against.
  Future<void> strokeAndSettle(
    ActiveStrokeOverlayModel overlay,
    BrushLiveStrokeRasterizer rasterizer,
    double x,
  ) async {
    rasterizer.blendFrom([dabAt(x)], from: 0);
    overlay.updateRegion(
      source: rasterizer,
      region: DirtyRegion.fromXYWH(x: x.round() - 2, y: 2, width: 5, height: 5),
    );
    await overlay
        .waitForPendingDecodes()
        .timeout(const Duration(seconds: 2));
  }

  /// ⛔THE INSTRUMENT FIRST. Everything below is about what a REFUSAL does,
  /// and an overlay that never uploaded at all would satisfy every one of
  /// those assertions for the wrong reason.
  test('the premise: a stroke tile goes through the seam and lands', () async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    installUploader(refuse: false);

    await strokeAndSettle(overlay, rasterizer, 4);

    expect(uploads, greaterThan(0), reason: 'the seam was consulted');
    expect(
      overlay.tileImages,
      isNotEmpty,
      reason: 'and a landed upload became the tile the painter draws',
    );
  });

  test('🚨a refused tile gives back its seat and its tick — the barrier '
      'still closes, and the coordinate can be drawn again', () async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    final captured = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => captured.add(details.exception);
    installUploader(refuse: true);

    // 🚨THIS AWAIT IS THE ASSERTION. Before 2026-09-09 the counter never
    // came back down and this future never completed at all.
    await strokeAndSettle(overlay, rasterizer, 4);
    final afterFirst = uploads;

    // And the seat came back with it: the next dab on the SAME coordinate
    // is uploaded rather than parked. ⛔Not a retry of the old ask — the
    // stroke moved, so these are different pixels, which is why this site
    // needs no refusal ledger at all.
    await strokeAndSettle(overlay, rasterizer, 4);

    FlutterError.onError = previous;

    expect(afterFirst, greaterThan(0), reason: 'fixture: it did upload');
    expect(
      uploads,
      greaterThan(afterFirst),
      reason: 'the coordinate was not gated out for the rest of the stroke',
    );
    expect(captured, isNotEmpty, reason: 'and the refusal is not hidden');
    expect(
      overlay.tileImages,
      isEmpty,
      reason: 'nothing was adopted — a refusal is an answer, not a picture',
    );
  });
}
