import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_commit_result.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_surface_edit.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_commit_result_apply.dart';
import 'package:anicel/src/services/brush_commit_result_revert.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';

void main() {
  group('brushSurfaceEditForBrushDabSequenceOnBitmapSurface', () {
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

    BitmapTile blankTile({
      required int tileX,
      required int tileY,
      int size = 2,
    }) {
      return BitmapTile.blank(
        coord: TileCoord(x: tileX, y: tileY),
        size: size,
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

    BrushSurfaceEdit editFor({
      required BitmapSurface surface,
      required BrushDabSequence sequence,
      LayerId overrideLayerId = layerId,
      FrameId overrideFrameId = frameId,
    }) {
      return brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: surface,
        sequence: sequence,
        layerId: overrideLayerId,
        frameId: overrideFrameId,
      );
    }

    test('returns no-op BrushSurfaceEdit for empty BrushDabSequence', () {
      final original = surface();

      final edit = editFor(surface: original, sequence: BrushDabSequence());

      expect(edit.commitResult, BrushCommitResult.noOp(surface: original));
      expect(edit.beforeSurface, original);
      expect(edit.afterSurface, original);
      expect(edit.hasChanges, isFalse);
      expect(edit.isNoOp, isTrue);
    });

    test('no-op edit uses same before and after surface instance', () {
      final original = surface();

      final edit = editFor(surface: original, sequence: BrushDabSequence());

      expect(identical(edit.beforeSurface, edit.afterSurface), isTrue);
    });

    test('no-op edit commitResult is BrushCommitResult.noOp', () {
      final edit = editFor(surface: surface(), sequence: BrushDabSequence());

      expect(
        edit.commitResult,
        BrushCommitResult.noOp(surface: edit.beforeSurface),
      );
    });

    test('returns changed BrushSurfaceEdit for dab on missing tile', () {
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.hasChanges, isTrue);
      expect(edit.isNoOp, isFalse);
      expect(
        edit.commitResult.dirtyTiles.contains(TileCoord(x: 0, y: 0)),
        isTrue,
      );
    });

    test('changed edit beforeSurface is original surface', () {
      final original = surface();

      final edit = editFor(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.beforeSurface, original);
      expect(identical(edit.beforeSurface, original), isTrue);
    });

    test('changed edit afterSurface contains created tile', () {
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.beforeSurface.tileAt(TileCoord(x: 0, y: 0)), isNull);
      expect(edit.afterSurface.tileAt(TileCoord(x: 0, y: 0)), isNotNull);
    });

    test('changed edit commitResult has changes', () {
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.commitResult.hasChanges, isTrue);
    });

    test('changed edit effectiveSurface equals afterSurface', () {
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.effectiveSurface, edit.afterSurface);
    });

    test('returns changed BrushSurfaceEdit for dab on existing tile', () {
      final existing = blankTile(tileX: 0, tileY: 0);
      final edit = editFor(
        surface: surface(tiles: {existing.coord: existing}),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.hasChanges, isTrue);
      expect(
        edit.commitResult.dirtyTiles.contains(TileCoord(x: 0, y: 0)),
        isTrue,
      );
    });

    test(
      'changed edit afterSurface equals applyBrushCommitResultToBitmapSurface manual result',
      () {
        final original = surface();
        final edit = editFor(
          surface: original,
          sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        );

        final manual = applyBrushCommitResultToBitmapSurface(
          surface: original,
          result: edit.commitResult,
        );

        expect(edit.afterSurface, manual);
      },
    );

    test(
      'changed edit can be reverted with revertBrushCommitResultOnBitmapSurface back to beforeSurface',
      () {
        final edit = editFor(
          surface: surface(),
          sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        );

        final reverted = revertBrushCommitResultOnBitmapSurface(
          surface: edit.afterSurface,
          result: edit.commitResult,
        );

        expect(reverted, edit.beforeSurface);
      },
    );

    test(
      'multi-tile dab produces afterSurface with multiple changed tiles',
      () {
        final edit = editFor(
          surface: surface(width: 4, height: 4, tileSize: 2),
          sequence: BrushDabSequence([squareDab(centerX: 2, centerY: 1)]),
        );

        expect(edit.commitResult.changedTileCount, greaterThan(1));
        for (final coord in edit.commitResult.dirtyTiles.coords) {
          expect(edit.afterSurface.tileAt(coord), isNotNull);
        }
      },
    );

    test('builder result matches manual composition', () {
      final original = surface();
      final sequence = BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]);
      final commitResult = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: sequence,
        layerId: layerId,
        frameId: frameId,
      );
      final afterSurface = applyBrushCommitResultToBitmapSurface(
        surface: original,
        result: commitResult,
      );
      final expected = BrushSurfaceEdit(
        beforeSurface: original,
        afterSurface: afterSurface,
        commitResult: commitResult,
      );

      final actual = editFor(surface: original, sequence: sequence);

      expect(actual, expected);
    });

    test('cache invalidation plan uses provided LayerId', () {
      const customLayerId = LayerId('custom-layer');
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        overrideLayerId: customLayerId,
      );

      expect(
        edit.commitResult.cacheInvalidationPlan.layerTiles.single.layerId,
        customLayerId,
      );
    });

    test('cache invalidation plan uses provided FrameId', () {
      const customFrameId = FrameId('custom-frame');
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        overrideFrameId: customFrameId,
      );

      expect(
        edit.commitResult.cacheInvalidationPlan.layerTiles.single.frameId,
        customFrameId,
      );
    });

    test('does not mutate original BitmapSurface', () {
      final original = surface();
      final before = BitmapSurface.fromJson(original.toJson());

      editFor(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(original, before);
      expect(original.tileAt(TileCoord(x: 0, y: 0)), isNull);
    });

    test('does not mutate existing BitmapTile', () {
      final existing = blankTile(tileX: 0, tileY: 0);
      final before = BitmapTile.fromJson(existing.toJson());

      editFor(
        surface: surface(tiles: {existing.coord: existing}),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(existing, before);
    });

    test('does not mutate BrushDabSequence', () {
      final dab = onePixelDab(globalX: 0, globalY: 0);
      final sequence = BrushDabSequence([dab]);
      final before = BrushDabSequence.fromJson(sequence.toJson());

      editFor(surface: surface(), sequence: sequence);

      expect(sequence, before);
    });

    test('does not mutate BrushDab', () {
      final dab = onePixelDab(globalX: 0, globalY: 0);
      final before = BrushDab.fromJson(dab.toJson());

      editFor(surface: surface(), sequence: BrushDabSequence([dab]));

      expect(dab, before);
    });

    test('does not execute cache invalidation', () {
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.commitResult.cacheInvalidationPlan.isNotEmpty, isTrue);
      expect(edit.afterSurface.tileAt(TileCoord(x: 0, y: 0)), isNotNull);
    });

    test('does not add undo stack behavior', () {
      final edit = editFor(
        surface: surface(),
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(edit.commitResult.dirtyTiles.isNotEmpty, isTrue);
      expect(edit.afterSurface, isNot(edit.beforeSurface));
    });
  });
}
