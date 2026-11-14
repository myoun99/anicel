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

/// 🚨EVERYTHING A DAB IS REACHES THE ENGINE (flip lane ⓒ): one stroke of each
/// kind piled on the engine and on the tile kernel that answers on any other
/// grid (`blendDabTilesDart`) gives the same picture within rounding — the
/// kernels round apart, the engine's in integers, the tile kernel's in
/// floats — so no number was lost on the way to the engine: the tip, its
/// turn and squeeze, the edge, the paper, the second tip.
///
/// ↩️The oracle was the C kernel till it went (ABI 80), and the tile kernel
/// was held to that byte for byte. ⏳Its premise goes with the tile kernel
/// (`the-cpu-brush-is-asked-by-tests-alone`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 320, height: 256);

  /// The most two rounding routes part, in levels of a premultiplied byte.
  const roundsApart = 1;

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

  final kinds = <String, List<BrushDab>>{
    'a soft round tip': [dab(0, size: 90, hardness: 0.2)],
    'a hard round tip across tiles': [dab(0, x: 128, y: 128, hardness: 1)],
    'a turned, squeezed round tip': [
      dab(0, roundness: 0.4, angleDegrees: 33),
    ],
    'a square tip': [dab(0, tipShape: BrushTipShape.square)],
    'a colour\'s alpha, opacity and flow': [
      dab(0, color: 0x80206040, opacity: 0.6, flow: 0.4),
      dab(1, x: 100, color: 0x80206040, opacity: 0.6, flow: 0.4),
    ],
    'a bitmap tip': [dab(0, tipMask: tip, size: 64)],
    'a turned, squeezed bitmap tip': [
      dab(0, tipMask: tip, size: 64, roundness: 0.5, angleDegrees: 70),
    ],
    'no anti-alias': [dab(0, antiAlias: BrushAntiAlias.none)],
    // Under squareReadRadius, their tables read by the pixel's square.
    'small round tips': [
      for (final (at, size) in const [(0, 1.0), (1, 2.0), (2, 3.0), (3, 5.0)])
        dab(at, x: 90.37 + 12.0 * at, y: 70.81, size: size, hardness: 1),
    ],
    'paper that multiplies': [
      dab(0, textureMask: paper, textureScale: 2, textureDensity: 0.7),
    ],
    'paper that cuts by height': [
      dab(
        0,
        textureMask: paper,
        textureDensity: 0.6,
        textureMode: BrushTextureMode.height,
      ),
    ],
    'a second tip': [
      dab(0, dual: const BrushDualView()),
      dab(1, x: 96, dual: const BrushDualView(), second: true, size: 30),
    ],
    'a second tip shown otherwise, thin': [
      dab(
        0,
        dual: const BrushDualView(
          compositeMode: SeparableBlendMode.overlay,
          density: 0.5,
        ),
      ),
      dab(
        1,
        x: 100,
        dual: const BrushDualView(
          compositeMode: SeparableBlendMode.overlay,
          density: 0.5,
        ),
        second: true,
      ),
    ],
    'the share a step is worth': [
      dab(0, opacity: 0.5, flow: 0.5, pathStep: 1),
      dab(1, x: 91, opacity: 0.5, flow: 0.5, pathStep: 1),
    ],
  };

  /// How far apart two pictures' premultiplied levels are at the most.
  int farthest(Uint8List a, Uint8List b) {
    var most = 0;
    for (var at = 0; at < a.length; at += 4) {
      for (var channel = 0; channel < 4; channel += 1) {
        int level(Uint8List bytes) => channel == 3
            ? bytes[at + 3]
            : (bytes[at + channel] * bytes[at + 3] / 255).round();
        most = max(most, (level(a) - level(b)).abs());
      }
    }
    return most;
  }

  Uint8List? stroke(List<BrushDab> dabs, {required int tileSize}) {
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    )..blendFrom(dabs, from: 0);
    final pixels = rasterizer.strokePixelsWithinBounds();
    rasterizer.clear();
    return pixels;
  }

  for (final MapEntry(key: name, value: dabs) in kinds.entries) {
    test(name, () {
      final onEngine = stroke(dabs, tileSize: 128)!;
      expect(onEngine.any((byte) => byte != 0), isTrue);
      final offEngine = stroke(dabs, tileSize: 64)!;
      expect(onEngine.length, offEngine.length);
      expect(farthest(onEngine, offEngine), lessThanOrEqualTo(roundsApart));
    });
  }
}
