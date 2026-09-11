import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

import '../helpers/native_engine_path.dart';

/// H39 (유저 2026-09-11): 「팁 이미지인 브러시는 aa off시 팁 이미지 그대로
/// 되는거 문제없는데, 그게아닌 원형인것들? G펜이나 뭐 펜 그룹에 있는것들
/// … aa off시엔 진짜 안티앨리어싱 완전없었으면 좋겠는데. 지금 off했는데도
/// 이상한 불투명도 남아있거든」.
///
/// A whole STROKE, not one dab: the AA pins already hold a single dab through
/// the reference oracle. A pen stroke is a pressure taper — dabs from a few
/// pixels down to under one — resolved through the tip-stamp cache the way
/// the canvas resolves every dab (`brush_edit_stroke.dart`) and landed by the
/// pen-up commit, through the Dart kernel and, when the engine is built, the
/// C one.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// The roster's G-Pen nib (`builtin-g-pen`): size 10 under a curve that
  /// snaps open — (0, 0.08) (0.6, 0.4) (1, 1).
  double gPenSize(double pressure) {
    final p = pressure.clamp(0.0, 1.0);
    final factor = p <= 0.6
        ? 0.08 + (0.4 - 0.08) * (p / 0.6)
        : 0.4 + (1.0 - 0.4) * ((p - 0.6) / 0.4);
    return 10 * factor;
  }

  /// A 0-1-0 pressure stroke along a wave, spaced the way the roster spaces
  /// the pens, every dab resolved through the stamp cache.
  List<BrushDab> penStroke({
    required double hardness,
    required BrushAntiAlias antiAlias,
  }) {
    final dabs = <BrushDab>[];
    var x = 40.0;
    var sequence = 0;
    while (x < 216) {
      final t = (x - 40) / 176;
      final pressure = math.sin(t * math.pi);
      final size = math.max(0.25, gPenSize(pressure));
      dabs.add(
        BrushDab(
          center: CanvasPoint(x: x, y: 64 + 24 * math.sin(t * 5)),
          color: 0xFF000000,
          size: size,
          opacity: 1,
          flow: 1,
          hardness: hardness,
          pressure: pressure,
          sequence: sequence,
          tipShape: BrushTipShape.round,
          antiAlias: antiAlias,
        ),
      );
      sequence += 1;
      x += math.max(0.3, size * 0.08);
    }
    return BrushTipStampCache.instance.resolveDabs(dabs);
  }

  ({int partly, int solid}) coverageOf(List<BrushDab> dabs) {
    final surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(
        canvasSize: const CanvasSize(width: 256, height: 128),
      ),
      sequence: BrushDabSequence(dabs),
    ).surface;
    var partly = 0;
    var solid = 0;
    for (final tile in surface.tiles.values) {
      tile.readPixels((_, view) {
        for (var i = 3; i < view.length; i += 4) {
          final alpha = view[i];
          if (alpha == 255) {
            solid += 1;
          } else if (alpha > 0) {
            partly += 1;
          }
        }
      });
    }
    return (partly: partly, solid: solid);
  }

  final routes = <({String name, bool native})>[
    (name: 'Dart kernel', native: false),
    if (libraryPath != null) (name: 'C kernel', native: true),
  ];

  for (final route in routes) {
    void useRoute() {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = !route.native;
      debugQaEngineLibraryPathOverride = route.native ? libraryPath : null;
      expect(
        QaNativeEngine.instance != null,
        route.native,
        reason: 'the route must be the one it says it is',
      );
    }

    for (final hardness in [1.0, 0.85]) {
      test('🚨AA none: a pen stroke lays NO partly covered pixel — '
          '${route.name}, hardness $hardness', () {
        useRoute();
        final hard = coverageOf(
          penStroke(hardness: hardness, antiAlias: BrushAntiAlias.none),
        );
        expect(hard.solid, greaterThan(200), reason: 'premise: it drew');
        expect(hard.partly, 0, reason: '「진짜 안티앨리어싱 완전없었으면」');
      });

      test('premise: the counter sees the soft edge AA 3 lays — '
          '${route.name}, hardness $hardness', () {
        useRoute();
        final soft = coverageOf(
          penStroke(hardness: hardness, antiAlias: BrushAntiAlias.high),
        );
        expect(soft.partly, greaterThan(0));
      });
    }
  }
}
