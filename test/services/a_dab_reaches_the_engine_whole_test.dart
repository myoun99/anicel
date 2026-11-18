// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_texture_mode.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

/// 🚨EVERYTHING A DAB IS REACHES THE ENGINE (flip lane ⓒ): the tip, its
/// turn and squeeze, the edge, the paper, the second tip — each case lays
/// a stroke with one thing about its dabs and the same stroke without it,
/// and the two pictures part, so no number is lost on the way to the
/// engine. What each lays is the engine's own pins' (dab/tests.rs).
///
/// ↩️The engine's picture was held to the tile kernel's within rounding
/// till 2026-11-14 (and the tile kernel to the C kernel's byte before ABI
/// 80); the tile kernel went with the commit off the engine's grid (board
/// `the-off-engine-cpu-commit-lives-only-for-tests`), and a field the
/// engine dropped is caught by its picture not moving.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 320, height: 256);

  BrushDab dab(
    int sequence, {
    double x = 90,
    double y = 70,
    double size = 60,
    double hardness = 0.5,
    double opacity = 1,
    double flow = 1,
    int color = 0xFFC86432,
    BrushTipShape tipShape = BrushTipShape.round,
    double roundness = 1,
    double angleDegrees = 0,
    BrushTipMask? tipMask,
    BrushTipMask? textureMask,
    double textureScale = 1,
    double textureDensity = 1,
    BrushTextureMode textureMode = BrushTextureMode.multiply,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
    BrushDualView? dual,
    bool second = false,
    double? pathStep,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: size,
    opacity: opacity,
    flow: flow,
    hardness: hardness,
    tipShape: tipShape,
    pressure: 1,
    sequence: sequence,
    roundness: roundness,
    angleDegrees: angleDegrees,
    tipMask: tipMask,
    textureMask: textureMask,
    textureScale: textureScale,
    textureDensity: textureDensity,
    textureMode: textureMode,
    antiAlias: antiAlias,
    dual: dual,
    second: second,
    pathStep: pathStep,
  );

  BrushTipMask speckled(String id, int size, int seed) {
    final random = Random(seed);
    return BrushTipMask(
      id: id,
      size: size,
      alpha: Uint8List.fromList([
        for (var at = 0; at < size * size; at++) random.nextInt(256),
      ]),
    );
  }

  final tip = speckled('tip', 32, 1);
  final paper = speckled('paper', 24, 2);
  const overlay = BrushDualView(
    compositeMode: SeparableBlendMode.overlay,
    density: 0.5,
  );

  /// Each case: the stroke with the thing, and the same stroke without it.
  final cases = <String, (List<BrushDab>, List<BrushDab>)>{
    'hardness': (
      [dab(0, size: 90, hardness: 0.2)],
      [dab(0, size: 90)],
    ),
    'a round tip\'s squeeze': ([dab(0, roundness: 0.4)], [dab(0)]),
    'a round tip\'s turn': (
      [dab(0, roundness: 0.4, angleDegrees: 33)],
      [dab(0, roundness: 0.4)],
    ),
    'a square tip': ([dab(0, tipShape: BrushTipShape.square)], [dab(0)]),
    'a colour\'s alpha': (
      [dab(0, color: 0x80206040)],
      [dab(0, color: 0xFF206040)],
    ),
    'opacity': ([dab(0, opacity: 0.6)], [dab(0)]),
    'flow': ([dab(0, flow: 0.4)], [dab(0)]),
    'a bitmap tip': ([dab(0, tipMask: tip, size: 64)], [dab(0, size: 64)]),
    'a bitmap tip\'s squeeze': (
      [dab(0, tipMask: tip, size: 64, roundness: 0.5)],
      [dab(0, tipMask: tip, size: 64)],
    ),
    'a bitmap tip\'s turn': (
      [dab(0, tipMask: tip, size: 64, roundness: 0.5, angleDegrees: 70)],
      [dab(0, tipMask: tip, size: 64, roundness: 0.5)],
    ),
    'no anti-alias': (
      [dab(0, hardness: 1, antiAlias: BrushAntiAlias.none)],
      [dab(0, hardness: 1)],
    ),
    'paper': ([dab(0, textureMask: paper, textureDensity: 0.7)], [dab(0)]),
    'the paper\'s scale': (
      [dab(0, textureMask: paper, textureScale: 2, textureDensity: 0.7)],
      [dab(0, textureMask: paper, textureDensity: 0.7)],
    ),
    'the paper\'s density': (
      [dab(0, textureMask: paper, textureDensity: 0.4)],
      [dab(0, textureMask: paper, textureDensity: 0.7)],
    ),
    'paper that cuts by height': (
      [
        dab(
          0,
          textureMask: paper,
          textureDensity: 0.6,
          textureMode: BrushTextureMode.height,
        ),
      ],
      [dab(0, textureMask: paper, textureDensity: 0.6)],
    ),
    'a second tip': (
      [
        dab(0, dual: const BrushDualView()),
        dab(1, x: 96, dual: const BrushDualView(), second: true, size: 30),
      ],
      [dab(0, dual: const BrushDualView())],
    ),
    'a second tip shown otherwise, thin': (
      [dab(0, dual: overlay), dab(1, x: 100, dual: overlay, second: true)],
      [
        dab(0, dual: const BrushDualView()),
        dab(1, x: 100, dual: const BrushDualView(), second: true),
      ],
    ),
    'the share a step is worth': (
      [
        dab(0, opacity: 0.5, flow: 0.5, pathStep: 1),
        dab(1, x: 91, opacity: 0.5, flow: 0.5, pathStep: 1),
      ],
      [
        dab(0, opacity: 0.5, flow: 0.5),
        dab(1, x: 91, opacity: 0.5, flow: 0.5),
      ],
    ),
  };

  /// The stroke the engine piles, over the whole pasteboard row by row.
  Uint8List picture(List<BrushDab> dabs) {
    final wall = canvas.pasteboardAt(PasteboardReach.whole);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: wall,
      tileSize: 128,
    )..blendFrom(dabs, from: 0);
    final width = wall.rightExclusive - wall.left;
    final height = wall.bottomExclusive - wall.top;
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      final row = y * width * 4;
      rasterizer.copyRow(wall.left, wall.top + y, width, pixels, row);
    }
    rasterizer.clear();
    return pixels;
  }

  for (final MapEntry(key: name, value: (withIt, without)) in cases.entries) {
    test(name, () {
      final laid = picture(withIt);
      expect(laid.any((byte) => byte != 0), isTrue, reason: 'it lays');
      expect(laid, isNot(equals(picture(without))));
    });
  }
}
