import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';

/// 🚨I-36 — 「이 과정에서 법 다른거 통일」: the fill reads a POSED layer
/// through its pose, as the eyedropper has since R28 #7. P5+P6 skipped posed
/// layers in both tools as a 「v1」; only the fill kept the skip, so line art
/// with a transform key — or inside a folder with one — never walled a fill.
///
/// And the raster lies in the SEED's space: the artwork of the layer the dab
/// lands on. With that layer posed, the other layers are carried into it.
void main() {
  const size = CanvasSize(width: 32, height: 32);
  const tile = 8;

  /// An opaque black box outline [side] wide from ([left], [top]) on a
  /// clear [canvas].
  BitmapSurface box({
    required int left,
    required int top,
    required int side,
    CanvasSize canvas = size,
  }) {
    final tiles = <TileCoord, Uint8List>{};
    void ink(int x, int y) {
      final buffer = tiles.putIfAbsent(
        TileCoord(x: x ~/ tile, y: y ~/ tile),
        () => Uint8List(tile * tile * 4),
      );
      buffer[((y % tile) * tile + (x % tile)) * 4 + 3] = 255;
    }

    for (var i = 0; i <= side; i += 1) {
      ink(left + i, top);
      ink(left + i, top + side);
      ink(left, top + i);
      ink(left + side, top + i);
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: tile,
      tiles: {
        for (final entry in tiles.entries)
          entry.key: BitmapTile(size: tile, pixels: entry.value),
      },
    );
  }

  /// An opaque black box outline [from]..[to] (inclusive) on a clear
  /// surface.
  BitmapSurface outline(int from, int to) =>
      box(left: from, top: from, side: to - from);

  Layer cel(String id, {double? scale, CanvasPoint? position}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId(id), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId(id), length: 1)},
    transformTrack: scale == null && position == null
        ? null
        : TransformTrack.empty().copyWith(
            scale: scale == null
                ? null
                : PropertyTrack<CanvasPoint>.empty().withKey(
                    0,
                    uniformScale(scale),
                  ),
            position: position == null
                ? null
                : PropertyTrack<CanvasPoint>.empty().withKey(0, position),
          ),
  );

  Cut cutOf(List<Layer> layers, {CanvasSize canvas = size}) => Cut(
    id: const CutId('c'),
    name: 'c',
    layers: layers,
    duration: 1,
    canvasSize: canvas,
  );

  (int, int) filledAt(
    CanvasPoint seed,
    Cut cut,
    Map<String, BitmapSurface> surfaces, {
    LayerPoseSample? space,
    String? active,
  }) {
    final dab = buildFillDab(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (layer, _) => surfaces[layer.id.value],
      point: seed,
      color: 0xFF3366CC,
      options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      activeLayerId: active == null ? null : LayerId(active),
      space: space == null ? null : placementOf(space, cut.canvasSize),
    )!;
    return (dab.stamp!.width, dab.stamp!.height);
  }

  test('a posed line layer walls the fill where it is DRAWN — it used to be '
      'skipped, and the fill ran over the whole canvas', () {
    // Artwork box 12..19 scaled 2× about the canvas centre (16,16): drawn
    // over canvas 8..23, its inside canvas 10..21.
    final (width, height) = filledAt(
      CanvasPoint(x: 16, y: 16),
      cutOf([cel('line', scale: 2), cel('paint')]),
      {'line': outline(12, 19)},
      active: 'paint',
    );
    expect(width, lessThan(size.width), reason: 'the skip filled it all');
    expect(width, inInclusiveRange(8, 12));
    expect(height, inInclusiveRange(8, 12));
  });

  test('the raster lies in the space the pen is in: a HALF-SIZED paint '
      'layer fills the line art\'s inside at its own scale', () {
    // Unposed box 8..23: inside canvas 9..22 (14). The paint layer is
    // posed 0.5× about the centre, so that inside is artwork 2..29 (28) in
    // its pixels — where the dab lands.
    final space = (
      pose: TransformPose.uniform(
        center: CanvasPoint(x: 16, y: 16),
        zoom: 0.5,
        rotationDegrees: 0,
      ),
      anchorPoint: null,
    );
    final (width, height) = filledAt(
      // Artwork (16,16) IS canvas (16,16) under a pose about the centre.
      CanvasPoint(x: 16, y: 16),
      cutOf([cel('line'), cel('paint', scale: 0.5)]),
      {'line': outline(8, 23)},
      space: space,
      active: 'paint',
    );
    expect(
      width,
      greaterThan(20),
      reason: 'read in the canvas the region is 14 wide — half the pixels '
          'the paint layer needs to cover the inside',
    );
    expect(width, lessThanOrEqualTo(28));
    expect(height, greaterThan(20));
  });

  test('🚨a layer is read through the SEED\'s placement first and its own '
      'second: a line layer moved sideways walls a half-sized paint layer\'s '
      'fill where it is drawn', () {
    // The box, artwork 9..15 across and 13..19 down, moved 4 right: drawn
    // over canvas 13..19 both ways, its inside canvas 14..18. The paint
    // layer shows at half size about the centre (16, 16), so that inside is
    // its own pixels 12..21 both ways — 10 wide, its middle at 17.
    // ⚠️Read the other way round, the move is halved along with the paint
    // layer: the box walls 2 canvas pixels left of where it is drawn, and
    // the middle of what fills comes out at 13 across.
    final cut = cutOf([
      cel('line', position: CanvasPoint(x: 20, y: 16)),
      cel('paint', scale: 0.5),
    ]);
    final line = box(left: 9, top: 13, side: 6);
    final dab = buildFillDab(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (layer, _) => layer.id.value == 'line' ? line : null,
      // Artwork (16, 16) IS canvas (16, 16) under a pose about the centre.
      point: CanvasPoint(x: 16, y: 16),
      color: 0xFF3366CC,
      options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      activeLayerId: const LayerId('paint'),
      space: placementOf((
        pose: TransformPose.uniform(
          center: CanvasPoint(x: 16, y: 16),
          zoom: 0.5,
        ),
        anchorPoint: null,
      ), cut.canvasSize),
    )!;

    expect(dab.stamp!.width, inInclusiveRange(8, 12));
    expect(dab.stamp!.height, inInclusiveRange(8, 12));
    expect(dab.center.x, closeTo(17, 1.5));
    expect(dab.center.y, closeTo(17, 1.5));
  });

  test('a line layer moved sideways walls the fill where it is drawn — a '
      'compose tile reads the layer across from where it lies, not down', () {
    // A 512 canvas is two compose tiles a side. The box, artwork x 20..40
    // and y 220..240, moved 300 right: drawn over canvas 320..340 across,
    // 220..240 down, in the tile at x 256..512, y 0..256 — which reads the
    // layer's artwork x −44..212 and y 0..256, the box inside it.
    const big = CanvasSize(width: 512, height: 512);
    final (width, height) = filledAt(
      CanvasPoint(x: 330, y: 230),
      cutOf([
        cel('line', position: CanvasPoint(x: 556, y: 256)),
        cel('paint'),
      ], canvas: big),
      {'line': box(left: 20, top: 220, side: 20, canvas: big)},
      active: 'paint',
    );
    expect(width, lessThan(100), reason: 'the walls held');
    expect(width, inInclusiveRange(17, 21));
    expect(height, inInclusiveRange(17, 21));
  });
}
