// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

/// 🚨H60 (유저 three times — H39 09-11 · I-174 11-14 · I-86 11-15 「팁이
/// 소재면 aa off하면 소재 팁 그대로인거고」): a raster tip at 없음 lays its
/// picture as it is, on the engine and on the tile kernel. A tip of one grey
/// lays that grey: the cut at half coverage laid a grey under half as
/// nothing and one over it as whole.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 256);

  BrushTipMask flat(int grey) => BrushTipMask(
    id: 'flat $grey',
    size: 16,
    alpha: Uint8List.fromList(List.filled(16 * 16, grey)),
  );

  /// The highest alpha one black dab of [tip] at 없음 lays, on the engine
  /// (a 128 tile) or the tile kernel (any other).
  int highest(BrushTipMask tip, {required int tileSize}) {
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    addTearDown(rasterizer.clear);
    rasterizer.blendFrom([
      BrushDab(
        center: CanvasPoint(x: 100, y: 100),
        color: 0xFF000000,
        size: 64,
        opacity: 1,
        flow: 1,
        hardness: 1,
        pressure: 1,
        sequence: 0,
        tipShape: BrushTipShape.round,
        tipMask: tip,
        antiAlias: BrushAntiAlias.none,
      ),
    ], from: 0);
    final pixels = rasterizer.strokePixelsWithinBounds()!;
    var most = 0;
    for (var at = 3; at < pixels.length; at += 4) {
      if (pixels[at] > most) most = pixels[at];
    }
    return most;
  }

  for (final (where, tileSize) in [
    ('the engine', 128),
    ('the tile kernel', 64),
  ]) {
    for (final grey in [64, 200]) {
      test('a tip of grey $grey lays grey $grey on $where', () {
        expect(highest(flat(grey), tileSize: tileSize), closeTo(grey, 1));
      });
    }
  }
}
