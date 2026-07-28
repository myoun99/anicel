import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';

void main() {
  group('brushCommitResultForBrushDabSequenceOnBitmapSurface', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface() =>
        BitmapSurface(canvasSize: CanvasSize(width: 4, height: 4), tileSize: 2);

    BrushDab onePixelDab({required double globalX, required double globalY}) {
      return BrushDab(
        center: CanvasPoint(x: globalX + 0.5, y: globalY + 0.5),
        color: 0xFFFF0000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      );
    }

    test(
      'empty sequence returns BrushCommitResult.noOp(surface: original)',
      () {
        final original = surface();
        final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
          surface: original,
          sequence: BrushDabSequence(),
          layerId: layerId,
          frameId: frameId,
        );

        expect(result.beforeSurface, original);
        expect(result.afterSurface, original);
        expect(result.isNoOp, isTrue);
        expect(result.dirtyTiles.isEmpty, isTrue);
      },
    );

    test(
      'changed sequence returns surfaces, dirtyTiles, and invalidation plan',
      () {
        final original = surface();
        final sequence = BrushDabSequence([
          onePixelDab(globalX: 0, globalY: 0),
        ]);
        final materialized = materializeBrushDabSequenceOnBitmapSurface(
          surface: original,
          sequence: sequence,
        );

        final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
          surface: original,
          sequence: sequence,
          layerId: layerId,
          frameId: frameId,
        );

        expect(result.beforeSurface, original);
        expect(result.afterSurface, materialized.surface);
        expect(result.dirtyTiles, materialized.dirtyTiles);
        expect(result.cacheInvalidationPlan.isNotEmpty, isTrue);
      },
    );

    test('cache invalidation layer and frame ids match provided ids', () {
      final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        layerId: layerId,
        frameId: frameId,
      );

      final key = result.cacheInvalidationPlan.layerTiles.single;
      expect(key.layerId, layerId);
      expect(key.frameId, frameId);
    });

    test('cache invalidation tile coords match dirtyTiles', () {
      final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 2, globalY: 0)]),
        layerId: layerId,
        frameId: frameId,
      );

      expect(result.dirtyTiles.coords, {TileCoord(x: 1, y: 0)});
      expect(
        result.cacheInvalidationPlan.layerTiles
            .map((key) => key.tileCoord)
            .toSet(),
        result.dirtyTiles.coords,
      );
    });
  });
}
