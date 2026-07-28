import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_surface_edit.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';
import 'package:anicel/src/services/canvas_surface_state_edit.dart';

void main() {
  group('applyBrushSurfaceEditToCanvasSurfaceState', () {
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

    BrushDab dab({int sequence = 0}) {
      return BrushDab(
        center: CanvasPoint(x: 0.5, y: 0.5),
        color: 0xFFFF0000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
      );
    }

    BrushSurfaceEdit changedEditFor(BitmapSurface source) {
      return brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: source,
        sequence: BrushDabSequence([dab()]),
        layerId: layerId,
        frameId: frameId,
      );
    }

    BrushSurfaceEdit noOpEditFor(BitmapSurface source) {
      return brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: source,
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
      );
    }

    test('returns same CanvasSurfaceState instance for no-op edit', () {
      final current = surface();
      final state = CanvasSurfaceState(currentSurface: current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: state,
        edit: noOpEditFor(current),
      );

      expect(identical(result, state), isTrue);
    });

    test('no-op edit preserves existing lastEdit', () {
      final current = surface();
      final existingEdit = changedEditFor(current);
      final state = CanvasSurfaceState(
        currentSurface: current,
        lastEdit: existingEdit,
      );

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: state,
        edit: noOpEditFor(current),
      );

      expect(result.lastEdit, existingEdit);
    });

    test('applies changed BrushSurfaceEdit to currentSurface', () {
      final current = surface();
      final edit = changedEditFor(current);
      final state = CanvasSurfaceState(currentSurface: current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: state,
        edit: edit,
      );

      expect(result.currentSurface, edit.afterSurface);
    });

    test('changed edit sets currentSurface to edit.afterSurface', () {
      final current = surface();
      final edit = changedEditFor(current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(identical(result.currentSurface, edit.afterSurface), isTrue);
    });

    test('changed edit sets lastEdit to edit', () {
      final current = surface();
      final edit = changedEditFor(current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(result.lastEdit, edit);
    });

    test('changed edit preserves immutability of previous state', () {
      final current = surface();
      final state = CanvasSurfaceState(currentSurface: current);
      final edit = changedEditFor(current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: state,
        edit: edit,
      );

      expect(result, isNot(same(state)));
      expect(state.currentSurface, current);
      expect(state.lastEdit, isNull);
    });

    test(
      'throws StateError for stale edit whose beforeSurface differs from state.currentSurface',
      () {
        final edit = changedEditFor(surface());
        final staleState = CanvasSurfaceState(
          currentSurface: surface(width: 6, height: 6),
        );

        expect(
          () => applyBrushSurfaceEditToCanvasSurfaceState(
            state: staleState,
            edit: edit,
          ),
          throwsStateError,
        );
      },
    );

    test('does not mutate original BitmapSurface', () {
      final current = surface();
      final before = BitmapSurface.fromJson(current.toJson());
      final edit = changedEditFor(current);

      applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(current, before);
    });

    test('does not mutate existing BitmapTile', () {
      final seedEdit = changedEditFor(surface());
      final existingTile = seedEdit.afterSurface.tiles.values.single;
      final beforeTile = BitmapTile.fromJson(existingTile.toJson());
      final current = surface(tiles: {existingTile.coord: existingTile});
      final edit = changedEditFor(current);

      applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(existingTile, beforeTile);
    });

    test('does not mutate BrushSurfaceEdit', () {
      final current = surface();
      final edit = changedEditFor(current);
      final before = edit.copyWith();

      applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(edit, before);
    });

    test('does not execute CacheInvalidationPlan', () {
      final current = surface();
      final edit = changedEditFor(current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(result.currentSurface, edit.afterSurface);
      expect(edit.commitResult.cacheInvalidationPlan.layerTiles, isNotEmpty);
    });

    test('does not add undo stack behavior', () {
      final current = surface();
      final edit = changedEditFor(current);

      final result = applyBrushSurfaceEditToCanvasSurfaceState(
        state: CanvasSurfaceState(currentSurface: current),
        edit: edit,
      );

      expect(result.lastEdit, edit);
      expect(result, isA<CanvasSurfaceState>());
    });
  });
}
