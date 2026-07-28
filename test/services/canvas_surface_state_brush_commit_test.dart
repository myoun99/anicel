import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_result_revert.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';
import 'package:anicel/src/services/canvas_surface_state_brush_commit.dart';
import 'package:anicel/src/services/canvas_surface_state_edit.dart';

void main() {
  group('commitBrushDabSequenceToCanvasSurfaceState', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface({
      int width = 4,
      int height = 4,
      int tileSize = 2,
      Map<TileCoord, BitmapTile> tiles = const {},
    }) {
      return BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: tileSize,
        tiles: tiles,
      );
    }

    BrushDab dab({
      double globalX = 0,
      double globalY = 0,
      int color = 0xFFFF0000,
      double opacity = 1,
      double flow = 1,
      double size = 1,
      int sequence = 0,
    }) {
      return BrushDab(
        center: CanvasPoint(x: globalX + 0.5, y: globalY + 0.5),
        color: color,
        size: size,
        opacity: opacity,
        flow: flow,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
      );
    }

    BrushDab squareDab({
      required double centerX,
      required double centerY,
      int color = 0xFFFF0000,
      int sequence = 0,
    }) {
      return BrushDab(
        center: CanvasPoint(x: centerX, y: centerY),
        color: color,
        size: 2,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: sequence,
      );
    }

    CanvasSurfaceState commit({
      required CanvasSurfaceState state,
      required BrushDabSequence sequence,
      LayerId overrideLayerId = layerId,
      FrameId overrideFrameId = frameId,
    }) {
      return commitBrushDabSequenceToCanvasSurfaceState(
        state: state,
        sequence: sequence,
        layerId: overrideLayerId,
        frameId: overrideFrameId,
      );
    }

    test('returns same state for no-op empty sequence', () {
      final current = surface();
      final state = CanvasSurfaceState(currentSurface: current);

      final result = commit(state: state, sequence: BrushDabSequence());

      expect(identical(result, state), isTrue);
      expect(result.currentSurface, current);
      expect(result.lastEdit, isNull);
    });

    test('no-op sequence preserves existing lastEdit', () {
      final current = surface();
      final existingEdit = brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: current,
        sequence: BrushDabSequence([dab()]),
        layerId: layerId,
        frameId: frameId,
      );
      final state = CanvasSurfaceState(
        currentSurface: current,
        lastEdit: existingEdit,
      );

      final result = commit(state: state, sequence: BrushDabSequence());

      expect(identical(result, state), isTrue);
      expect(result.lastEdit, existingEdit);
    });

    test('returns same state for non-effective dab', () {
      final current = surface();
      final state = CanvasSurfaceState(currentSurface: current);
      final sequence = BrushDabSequence([dab(opacity: 0)]);

      final result = commit(state: state, sequence: sequence);

      expect(identical(result, state), isTrue);
      expect(result.currentSurface, current);
      expect(result.lastEdit, isNull);
    });

    test('changed sequence updates currentSurface', () {
      final current = surface();
      final sequence = BrushDabSequence([dab()]);

      final result = commit(
        state: CanvasSurfaceState(currentSurface: current),
        sequence: sequence,
      );

      expect(result.currentSurface, isNot(current));
      expect(result.currentSurface.tileAt(TileCoord(x: 0, y: 0)), isNotNull);
    });

    test('changed sequence records lastEdit', () {
      final current = surface();
      final sequence = BrushDabSequence([dab()]);

      final result = commit(
        state: CanvasSurfaceState(currentSurface: current),
        sequence: sequence,
      );

      expect(result.lastEdit, isNotNull);
      expect(result.lastEdit!.beforeSurface, current);
      expect(result.lastEdit!.afterSurface, result.currentSurface);
      expect(result.lastEdit!.hasChanges, isTrue);
    });

    test(
      'matches manual BrushSurfaceEdit builder plus state apply composition',
      () {
        final current = surface();
        final state = CanvasSurfaceState(currentSurface: current);
        final sequence = BrushDabSequence([dab()]);
        final edit = brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
          surface: current,
          sequence: sequence,
          layerId: layerId,
          frameId: frameId,
        );
        final expected = applyBrushSurfaceEditToCanvasSurfaceState(
          state: state,
          edit: edit,
        );

        final actual = commit(state: state, sequence: sequence);

        expect(actual, expected);
      },
    );

    test('lastEdit can be reverted back to the original surface', () {
      final current = surface();
      final result = commit(
        state: CanvasSurfaceState(currentSurface: current),
        sequence: BrushDabSequence([dab()]),
      );

      final reverted = revertBrushCommitResultOnBitmapSurface(
        surface: result.currentSurface,
        result: result.lastEdit!.commitResult,
      );

      expect(reverted, current);
    });

    test('multi-tile dab updates multiple tiles', () {
      final result = commit(
        state: CanvasSurfaceState(
          currentSurface: surface(width: 4, height: 4, tileSize: 2),
        ),
        sequence: BrushDabSequence([squareDab(centerX: 2, centerY: 1)]),
      );

      expect(result.lastEdit!.commitResult.changedTileCount, greaterThan(1));
      for (final coord in result.lastEdit!.commitResult.dirtyTiles.coords) {
        expect(result.currentSurface.tileAt(coord), isNotNull);
      }
    });

    test('cache invalidation plan uses provided LayerId and FrameId', () {
      const customLayerId = LayerId('custom-layer');
      const customFrameId = FrameId('custom-frame');

      final result = commit(
        state: CanvasSurfaceState(currentSurface: surface()),
        sequence: BrushDabSequence([dab()]),
        overrideLayerId: customLayerId,
        overrideFrameId: customFrameId,
      );

      final invalidatedLayerTile =
          result.lastEdit!.commitResult.cacheInvalidationPlan.layerTiles.single;
      expect(invalidatedLayerTile.layerId, customLayerId);
      expect(invalidatedLayerTile.frameId, customFrameId);
    });

    test('does not mutate original state, surface, tile, sequence, or dab', () {
      final seed = commit(
        state: CanvasSurfaceState(currentSurface: surface()),
        sequence: BrushDabSequence([dab()]),
      );
      final existingTile = seed.currentSurface.tiles.values.single;
      final beforeTile = BitmapTile.fromJson(existingTile.toJson());
      final current = surface(tiles: {existingTile.coord: existingTile});
      final beforeSurface = BitmapSurface.fromJson(current.toJson());
      final state = CanvasSurfaceState(currentSurface: current);
      final oneDab = dab(color: 0xFF0000FF, sequence: 1);
      final beforeDab = BrushDab.fromJson(oneDab.toJson());
      final sequence = BrushDabSequence([oneDab]);
      final beforeSequence = BrushDabSequence.fromJson(sequence.toJson());

      final result = commit(state: state, sequence: sequence);

      expect(result, isNot(same(state)));
      expect(state.currentSurface, current);
      expect(state.lastEdit, isNull);
      expect(current, beforeSurface);
      expect(existingTile, beforeTile);
      expect(sequence, beforeSequence);
      expect(oneDab, beforeDab);
    });

    test('does not execute cache invalidation or add undo stack behavior', () {
      final result = commit(
        state: CanvasSurfaceState(currentSurface: surface()),
        sequence: BrushDabSequence([dab()]),
      );

      expect(result.lastEdit, isNotNull);
      expect(
        result.lastEdit!.commitResult.cacheInvalidationPlan.isNotEmpty,
        isTrue,
      );
      expect(result, isA<CanvasSurfaceState>());
    });
  });
}
