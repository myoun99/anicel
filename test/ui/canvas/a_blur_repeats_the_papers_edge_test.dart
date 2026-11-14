import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart' show PasteboardBounds;
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/a_row_laid_on_the_engine.dart';

/// 🗣️I-132-Q14 a (유저 2026-10-28): a Gaussian's Repeat Edge Pixels repeats
/// the PAPER's edge — the canvas's, on a layer and a folder alike, as AE's
/// comp-sized solid and precomp — and what it draws stays on the paper.
///
/// Off, past the paper there is nothing and the edge fades into it; on, the
/// edge holds. Inside the paper the blur spreads as it always did: the edge
/// is the paper's, not the picture's.
///
/// ↩️Drawn through the Flutter chain (`steppedForChain`) until it went
/// (the-flutter-fx-chain-is-a-second-chain). What it held of the edge
/// itself — all ink stays all ink, nothing past the paper, the paper's
/// edge and not the picture's — the engine's own pins hold now
/// (rust/src/kernels/effects/blur/gaussian_tests.rs, and
/// the_engine_lays_a_tree_as_the_walk_paints_it_test's 「a Gaussian
/// repeating the paper's edge puts nothing on the pasteboard, nor reads
/// it」); what is left here is the step's company: the blur it leaves alone
/// and what follows it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const side = 128;
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

  ResolvedLayerEffect gaussian({required bool repeats, double radius = 4}) =>
      ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: [radius, 0, if (repeats) 1 else 0],
      );

  /// A cel of one tile, its paper the whole of it: white wherever the
  /// square [inkFrom]…[inkTo] covers and nothing elsewhere — all of it
  /// white without one.
  BitmapSurface picture({int inkFrom = 0, int inkTo = side}) {
    final pixels = Uint8List(side * side * 4);
    for (var y = inkFrom; y < inkTo; y += 1) {
      pixels.fillRange((y * side + inkFrom) * 4, (y * side + inkTo) * 4, 255);
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: side, height: side),
      tileSize: side,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: side, pixels: pixels)},
    );
  }

  Future<Uint8List> laid(
    BitmapSurface surface,
    List<ResolvedLayerEffect> effects,
  ) => aRowLaidOnTheEngine(composite, letters, surface, effects);

  int alphaAt(Uint8List bytes, int x, int y) => bytes[(y * side + x) * 4 + 3];

  test('the edge is the paper\'s, not the picture\'s: ink clear of it blurs '
      'as it does off', () async {
    final ink = picture(inkFrom: 48, inkTo: 80);
    final on = await laid(ink, [gaussian(repeats: true)]);
    final off = await laid(ink, [gaussian(repeats: false)]);
    expect(
      resolveCompositeEffectPlan(
        [gaussian(repeats: true)],
        paper: ink.canvasSize.canvasRect,
      ).preSteps.single.lead,
      isA<PaperEdgeEffect>(),
      reason: '⛔premise: on, the paper\'s edge is a step of its own',
    );

    expect(
      alphaAt(on, 47, 64),
      greaterThan(0),
      reason: 'it spreads past the ink, inside the paper',
    );
    for (var i = 0; i < on.length; i += 1) {
      expect(on[i], closeTo(off[i], 1), reason: 'byte $i');
    }
  });

  test('what follows it in its step comes after it, on the paper', () async {
    final effects = [
      gaussian(repeats: true),
      ResolvedLayerEffect(
        kind: EffectKind.brightnessContrast,
        values: const [-50, 0],
      ),
      // A key that finds nothing to take — it only closes the step.
      ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: const [0, 0xFF000000, 0, 100],
      ),
    ];
    final plan = resolveCompositeEffectPlan(
      effects,
      paper: const CanvasSize(width: side, height: side).canvasRect,
    );
    expect(plan.preSteps.first.lead, isA<PaperEdgeEffect>(), reason: '⛔premise');
    expect(plan.preSteps.first.then, isNotEmpty, reason: '⛔premise');

    final bytes = await laid(picture(), effects);
    const corner = 0;
    const middle = (64 * side + 64) * 4;
    expect(bytes[corner + 3], 255);
    expect(bytes[corner], lessThan(255), reason: 'darkened after it');
    expect(
      bytes.sublist(corner, corner + 4),
      bytes.sublist(middle, middle + 4),
      reason: 'the corner as the middle: the edge held, then darkened',
    );
  });
}
