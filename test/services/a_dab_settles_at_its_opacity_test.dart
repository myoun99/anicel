import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';

import '../helpers/native_engine_path.dart';

/// 🗣️F-205 (유저 2026-09-28): 「브러시 불투명도 필압 인식이 다름. 필압걸어도
/// dab이 쌓이면 최대불투명도치만큼 진해지는데 그게아니라 최대 100%로
/// 해두더라도 필압 약하게하면 해당 선들 겹쳐도 필압에맞춰서 10%만큼만
/// 진해진다던가」.
///
/// A dab's opacity — what the pressure curve (and the jitter) make of it —
/// is the level the stroke settles at where dabs pile up, not a factor that
/// piles up to opaque. A stroke is built on an empty buffer, which is where
/// every case below draws.
///
/// The levels are chosen off the half: a byte that lands on .5 would pin a
/// rounding, not the law.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 64);
  final origin = TileCoord(x: 0, y: 0);
  const blue = 0xFF224488;
  const red = 0xFFAA0000;
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// A hard round dab over the middle of the only tile: full coverage at
  /// the pixel read below.
  BrushDab dab({
    required double opacity,
    double flow = 1,
    int color = blue,
    int sequence = 0,
  }) => BrushDab(
    center: CanvasPoint(x: 32, y: 32),
    color: color,
    size: 12,
    opacity: opacity,
    flow: flow,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  /// The RGBA at the middle of the dab after [dabs] pile up there.
  List<int> pixelAfter(List<BrushDab> dabs) {
    final surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 64),
      sequence: BrushDabSequence(dabs),
    ).surface;
    final tile = surface.tileAt(origin)!;
    final at = tile.byteOffsetForPixel(x: 32, y: 32);
    return tile.pixels.sublist(at, at + 4);
  }

  int alphaAfter(List<BrushDab> dabs) => pixelAfter(dabs)[3];

  List<BrushDab> pile(int count, {required double opacity, double flow = 1}) =>
      [
        for (var i = 0; i < count; i += 1)
          dab(opacity: opacity, flow: flow, sequence: i),
      ];

  void onEachEngine(String name, void Function() body) {
    test('$name — Dart kernel', () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      expect(QaNativeEngine.instance, isNull);
      body();
    });
    test('$name — C kernel', () {
      if (dllPath == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      expect(QaNativeEngine.instance, isNotNull);
      body();
    });
  }

  onEachEngine('a light press piles up to ITS opacity, not to opaque', () {
    // 12% at full flow: the first dab lands 30.6 → 31, and every dab after
    // it finds the pixel already at the ceiling.
    expect(alphaAfter(pile(40, opacity: 0.12)), 31);
    // At half flow it climbs towards the same 12% and stops short of it.
    expect(alphaAfter(pile(40, opacity: 0.12, flow: 0.5)), 30);
    expect(
      alphaAfter(pile(2, opacity: 0.12, flow: 0.5)),
      greaterThan(alphaAfter(pile(1, opacity: 0.12, flow: 0.5))),
      reason: 'flow is still how fast it gets there',
    );
  });

  onEachEngine('the first dab over nothing lands what it always did', () {
    // alpha × opacity × flow: 255 × 0.3 × 0.5 = 38.25 → 38.
    expect(alphaAfter([dab(opacity: 0.3, flow: 0.5)]), 38);
  });

  onEachEngine('a press that grows raises the stroke to the new ceiling, and '
      'a lighter one after it lowers nothing', () {
    expect(
      alphaAfter([...pile(10, opacity: 0.12), ...pile(10, opacity: 0.4)]),
      102,
      reason: '40% settles at 102',
    );
    expect(
      alphaAfter([...pile(10, opacity: 0.4), ...pile(10, opacity: 0.12)]),
      102,
    );
  });

  onEachEngine('an opacity of 1 is plain source-over — a brush no dynamic '
      'touches lands as before', () {
    // (51 + 0.4·x) rounds up to 255 by the seventh dab.
    expect(alphaAfter(pile(40, opacity: 1, flow: 0.6)), 255);
    // Over opaque ink a second colour still mixes in at its flow: nothing
    // holds an opacity-1 dab back.
    expect(
      pixelAfter([
        dab(opacity: 1),
        dab(opacity: 1, flow: 0.5, color: red, sequence: 1),
      ]),
      [102, 34, 68, 255],
    );
  });
}
