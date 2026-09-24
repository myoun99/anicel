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

  /// An opaque black box outline [from]..[to] (inclusive) on a clear
  /// surface.
  BitmapSurface outline(int from, int to) {
    final tiles = <TileCoord, Uint8List>{};
    void ink(int x, int y) {
      final buffer = tiles.putIfAbsent(
        TileCoord(x: x ~/ tile, y: y ~/ tile),
        () => Uint8List(tile * tile * 4),
      );
      buffer[((y % tile) * tile + (x % tile)) * 4 + 3] = 255;
    }

    for (var i = from; i <= to; i += 1) {
      ink(i, from);
      ink(i, to);
      ink(from, i);
      ink(to, i);
    }
    return BitmapSurface(
      canvasSize: size,
      tileSize: tile,
      tiles: {
        for (final entry in tiles.entries)
          entry.key: BitmapTile(size: tile, pixels: entry.value),
      },
    );
  }

  Layer cel(String id, {double? scale}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId(id), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId(id), length: 1)},
    transformTrack: scale == null
        ? null
        : TransformTrack.empty().copyWith(
            scale: PropertyTrack<double>.empty().withKey(0, scale),
          ),
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: 'c',
    layers: layers,
    duration: 1,
    canvasSize: size,
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
      space: space,
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
      pose: TransformPose(
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
}
