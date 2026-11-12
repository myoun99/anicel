import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

/// 🚨WHAT A DAB ANSWERS IS ALL IT MOVED (F-533). A step goes into the frame's
/// picture as far as the stroke says it moved
/// (`ActiveStrokeOverlayModel.movedSince`), so a byte past that is a byte the
/// picture never shows until the pen comes up. A tile hid it while a step
/// was tiles: only ink over a tile's edge could have shown one.
///
/// Every byte the stroke shows over its cel, each tile's result as the
/// overlay pictures it, is compared before and after each dab, wherever it
/// lies, for every kind of dab there is — a kind added here is a kind that
/// cannot write past its rect. The bytes alone say nothing of the picture:
/// `a_step_writes_what_its_dabs_moved_test` does that.
void main() {
  const canvasSize = CanvasSize(width: 96, height: 64);
  const tileSize = 16;
  const reach = 2 * tileSize;
  final wall = canvasSize.pasteboardAt(PasteboardReach.whole);
  final width = canvasSize.width + 2 * reach;
  final height = canvasSize.height + 2 * reach;

  final tip = BrushTipMask(
    id: 'a-dab-tells-all-it-moved',
    size: 8,
    alpha: Uint8List.fromList([
      for (var index = 0; index < 64; index += 1) (index * 5) % 256,
    ]),
  );

  /// A line over the tiles' edges and past the page's, fractions and all.
  List<BrushDab> lineOf(
    BrushDab Function(CanvasPoint center, int sequence) dab,
  ) => [
    for (var i = 0; i < 24; i += 1)
      dab(CanvasPoint(x: -4.3 + i * 4.7, y: 30.4 + 34 * math.sin(i * 0.7)), i),
  ];

  BrushDab plain(
    CanvasPoint center,
    int sequence, {
    double size = 13.7,
    double hardness = 0.4,
    BrushTipShape tipShape = BrushTipShape.round,
    BrushTipMask? tipMask,
    BrushTipMask? textureMask,
    BrushDualView? dual,
    bool blurs = false,
  }) => BrushDab(
    center: center,
    color: 0xFF2A5599,
    size: size,
    opacity: 0.8,
    flow: 0.7,
    hardness: hardness,
    tipShape: tipShape,
    pressure: 1,
    sequence: sequence,
    tipMask: tipMask,
    textureMask: textureMask,
    textureScale: textureMask == null ? 1 : 1.3,
    textureDensity: textureMask == null ? 0 : 0.4,
    dual: dual,
    blurs: blurs,
  );

  /// The cel a stroke shows over, every pixel of it something to move.
  final celPixels = {
    for (var y = 0; y < 4; y += 1)
      for (var x = 0; x < 6; x += 1)
        TileCoord(x: x, y: y): Uint8List.fromList([
          for (var index = 0; index < tileSize * tileSize; index += 1) ...[
            (index * 11) % 256,
            (index * 7) % 256,
            (index * 3) % 256,
            255,
          ],
        ]),
  };
  final cel = BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (final MapEntry(key: coord, value: pixels) in celPixels.entries)
        coord: BitmapTile(size: tileSize, pixels: pixels),
    },
  );

  /// Every byte [stroke] shows over [cel], row after row: the tiles it
  /// touched as it shows them, and the others as the cel does.
  Uint8List shown(BrushLiveStrokeRasterizer stroke) {
    final coords = [
      for (var y = 0; y < height ~/ tileSize; y += 1)
        for (var x = 0; x < width ~/ tileSize; x += 1)
          TileCoord(x: x - reach ~/ tileSize, y: y - reach ~/ tileSize),
    ];
    final tiles = stroke.preBlendedOverlayTiles(
      coords: coords,
      base: cel,
      mode: BrushBlendMode.color,
      erase: false,
    );
    final bytes = Uint8List(width * height * 4);
    void lay(TileCoord coord, List<int> pixels) {
      for (var row = 0; row < tileSize; row += 1) {
        final at =
            ((coord.y * tileSize + reach + row) * width +
                coord.x * tileSize +
                reach) *
            4;
        bytes.setRange(at, at + tileSize * 4, pixels, row * tileSize * 4);
      }
    }

    for (var i = 0; i < coords.length; i += 1) {
      final tile = tiles[i];
      if (tile == null) {
        if (celPixels[coords[i]] case final pixels?) {
          lay(coords[i], pixels);
        }
        continue;
      }
      tile.readStraight((straight) => lay(coords[i], straight));
    }
    return bytes;
  }

  /// The pixels at which [a] and [b] differ past [told].
  List<(int, int)> movedPast(Uint8List a, Uint8List b, DirtyRegion? told) => [
    for (var y = 0; y < height; y += 1)
      for (var x = 0; x < width; x += 1)
        if (Iterable<int>.generate(4).any(
              (channel) =>
                  a[(y * width + x) * 4 + channel] !=
                  b[(y * width + x) * 4 + channel],
            ) &&
            !(told?.containsPixel(x: x - reach, y: y - reach) ?? false))
          (x - reach, y - reach),
  ];

  for (final (kind, dab) in <(String, BrushDab Function(CanvasPoint, int))>[
    ('a soft round', plain),
    ('a pixel', (at, i) => plain(at, i, size: 1, hardness: 1)),
    ('a wide one', (at, i) => plain(at, i, size: 61.3)),
    (
      'a square',
      (at, i) => plain(at, i, tipShape: BrushTipShape.square, hardness: 1),
    ),
    ('a sampled tip', (at, i) => plain(at, i, tipMask: tip)),
    ('a textured one', (at, i) => plain(at, i, textureMask: tip)),
    (
      'a second tip',
      (at, i) => plain(at, i, dual: const BrushDualView(density: 0.35)),
    ),
    ('a blur', (at, i) => plain(at, i, blurs: true)),
  ]) {
    test('$kind moves no byte past what it tells', () {
      final stroke = BrushLiveStrokeRasterizer(
        pasteboard: wall,
        tileSize: tileSize,
      );
      final dabs = lineOf(dab);
      if (dabs.first.blurs) {
        stroke.blurOver(cel);
      }
      var moved = 0;
      var before = shown(stroke);
      for (var from = 0; from < dabs.length; from += 1) {
        final told = stroke.blendFrom(
          dabs.sublist(0, from + 1),
          from: from,
        );
        final after = shown(stroke);
        expect(
          movedPast(before, after, told),
          isEmpty,
          reason: 'dab $from told $told',
        );
        moved += movedPast(before, after, null).length;
        before = after;
      }
      expect(moved, greaterThan(0), reason: 'LIVENESS: the dabs moved ink');
    });
  }
}
