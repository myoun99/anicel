import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_surface_edit.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_result_revert.dart';
import 'package:anicel/src/services/brush_bitmap_materialization_history_entry_builder.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';

void main() {
  group('brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit', () {
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

    BrushDab onePixelDab({
      required double globalX,
      required double globalY,
      int color = 0xFFFF0000,
      double opacity = 1,
      double flow = 1,
      int sequence = 0,
    }) {
      return BrushDab(
        center: CanvasPoint(x: globalX + 0.5, y: globalY + 0.5),
        color: color,
        size: 1,
        opacity: opacity,
        flow: flow,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
      );
    }

    BrushSurfaceEdit changedEdit({required BitmapSurface source}) {
      return brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: source,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        layerId: layerId,
        frameId: frameId,
      );
    }

    BrushSurfaceEdit noOpEdit({required BitmapSurface source}) {
      return brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: source,
        sequence: BrushDabSequence(),
        layerId: layerId,
        frameId: frameId,
      );
    }

    test('returns null for no-op BrushSurfaceEdit', () {
      expect(
        brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
          edit: noOpEdit(source: surface()),
          layerId: layerId,
          frameId: frameId,
        ),
        isNull,
      );
    });

    test(
      'returns BrushBitmapMaterializationHistoryEntry for changed BrushSurfaceEdit',
      () {
        final edit = changedEdit(source: surface());
        final entry =
            brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
              edit: edit,
              layerId: layerId,
              frameId: frameId,
            );

        expect(entry, isNotNull);
        expect(entry!.commitResult, edit.commitResult);
      },
    );

    test('entry uses provided LayerId and FrameId', () {
      final edit = changedEdit(source: surface());
      const customLayerId = LayerId('custom-layer');
      const customFrameId = FrameId('custom-frame');
      final entry = brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
        edit: edit,
        layerId: customLayerId,
        frameId: customFrameId,
      );

      expect(entry!.layerId, customLayerId);
      expect(entry.frameId, customFrameId);
    });

    test('entry dirtyTiles and changedTileCount mirror edit commitResult', () {
      final edit = changedEdit(source: surface());
      final entry = brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
        edit: edit,
        layerId: layerId,
        frameId: frameId,
      )!;

      expect(entry.dirtyTiles, edit.commitResult.dirtyTiles);
      expect(entry.changedTileCount, edit.commitResult.changedTileCount);
    });

    test(
      'entry can revert applied surface using commitResult through existing revert service',
      () {
        final edit = changedEdit(source: surface());
        final entry =
            brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
              edit: edit,
              layerId: layerId,
              frameId: frameId,
            )!;

        final reverted = revertBrushCommitResultOnBitmapSurface(
          surface: edit.afterSurface,
          result: entry.commitResult,
        );

        expect(reverted, edit.beforeSurface);
      },
    );

    test(
      'does not mutate BrushSurfaceEdit, BrushCommitResult, or surfaces',
      () {
        final edit = changedEdit(source: surface());
        final beforeEdit = edit.copyWith();
        final beforeResult = edit.commitResult.copyWith();
        final beforeSurface = edit.beforeSurface.copyWith();
        final afterSurface = edit.afterSurface.copyWith();

        brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
          edit: edit,
          layerId: layerId,
          frameId: frameId,
        );

        expect(edit, beforeEdit);
        expect(edit.commitResult, beforeResult);
        expect(edit.beforeSurface, beforeSurface);
        expect(edit.afterSurface, afterSurface);
      },
    );

    test(
      'does not execute CacheInvalidationPlan or add undo stack behavior',
      () {
        final edit = changedEdit(source: surface());
        final keyCount = edit.commitResult.cacheInvalidationPlan.totalKeyCount;
        final entry =
            brushBitmapMaterializationHistoryEntryFromBrushSurfaceEdit(
              edit: edit,
              layerId: layerId,
              frameId: frameId,
            )!;

        expect(
          entry.cacheInvalidationPlan,
          edit.commitResult.cacheInvalidationPlan,
        );
        expect(entry.cacheInvalidationPlan.totalKeyCount, keyCount);
        expect(entry.toString(), isNot(contains('UndoStack')));
        expect(entry.toString(), isNot(contains('RedoStack')));
      },
    );
  });
}
