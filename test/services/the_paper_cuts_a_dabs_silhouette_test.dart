import 'dart:math' as math;

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_texture_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️F-451 (유저 2026-10-23): 「사각형이란 dab을 그리면서 그 사각형 지키면서
/// 질감만 바뀌는느낌 … 진짜 연필처럼 중간중간 아예 형태가 선이 일부분? 1px이나
/// 그정도 없다던가」.
///
/// Under [BrushTextureMode.height] the paper decides WHERE a dab lands, not
/// only how dark: where the tip presses less — towards a soft dab's rim —
/// only the paper's peaks are reached, so whole pixels of the silhouette go
/// missing there while the core, pressed hard, stays whole. A multiplied
/// paper leaves every pixel of the silhouette inked.
void main() {
  const radius = 20.0;

  /// The share of a ring's pixels the dab leaves bare, for the core (out to
  /// [radius] × 0.4) and the rim (0.75 to 0.95 of it).
  ({double core, double rim}) bareShares(BrushTextureMode mode) {
    final dab = BrushDab(
      center: CanvasPoint(x: 64, y: 64),
      color: 0xFF000000,
      size: radius * 2,
      opacity: 1,
      flow: 1,
      hardness: 0.3,
      pressure: 1,
      sequence: 0,
      textureMask: graphiteToothTextureMask,
      textureDensity: 0.9,
      textureMode: mode,
    );
    final inked = <(int, int)>{};
    forEachBrushPixelCoverage(dab, (x, y, coverage, _) {
      if (coverage > 0.0) {
        inked.add((x, y));
      }
    });
    var coreAll = 0;
    var coreBare = 0;
    var rimAll = 0;
    var rimBare = 0;
    for (var y = 64 - 21; y <= 64 + 21; y += 1) {
      for (var x = 64 - 21; x <= 64 + 21; x += 1) {
        final reach =
            math.sqrt(math.pow(x + 0.5 - 64, 2) + math.pow(y + 0.5 - 64, 2)) /
            radius;
        final bare = !inked.contains((x, y));
        if (reach < 0.4) {
          coreAll += 1;
          coreBare += bare ? 1 : 0;
        } else if (reach >= 0.75 && reach < 0.95) {
          rimAll += 1;
          rimBare += bare ? 1 : 0;
        }
      }
    }
    return (core: coreBare / coreAll, rim: rimBare / rimAll);
  }

  test('🚨under the paper\'s height a soft dab\'s rim is cut by the paper, '
      'and its core much less', () {
    final multiplied = bareShares(BrushTextureMode.multiply);
    expect(
      multiplied.rim,
      0.0,
      reason: '⛔CONTROL: a multiplied paper leaves the silhouette whole',
    );

    // 🔬Measured as it first shipped (10-23): rim 0.75 bare, core 0.096.
    final height = bareShares(BrushTextureMode.height);
    expect(height.rim, greaterThan(0.5), reason: 'the rim reaches only peaks');
    expect(
      height.core,
      lessThan(height.rim / 2),
      reason: 'the core, pressed hard, reaches into the valleys',
    );
  });
}
