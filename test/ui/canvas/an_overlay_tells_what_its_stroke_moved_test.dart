import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

/// 🚨THE OVERLAY TELLS WHAT MOVED ONLY WHILE THAT IS ALL ITS PICTURES CHANGED
/// BY (F-533). A step is written as far as [ActiveStrokeOverlayModel.movedSince]
/// says and no further, so an answer where the pictures changed some other
/// way leaves that in no frame's picture: a tile keeps the old ink where a
/// fill landed. Each way a picture changes that is not a dab is here; each
/// says nothing, and the canvas falls back on the tiles it sees change.
void main() {
  const canvasSize = CanvasSize(
    width: 8 * defaultCelTileSize,
    height: 8 * defaultCelTileSize,
  );
  const tileSize = defaultCelTileSize;
  final farTile = TileCoord(x: 7, y: 7);
  final tile = BitmapTile.blank(size: tileSize);

  ActiveStrokeOverlayModel overlayOn() {
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    addTearDown(model.dispose);
    return model;
  }

  final rasterizer = BrushLiveStrokeRasterizer(
    pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    tileSize: tileSize,
  );

  /// A dab at ([x], [y]), as the interactive view flushes one.
  DirtyRegion dabInto(ActiveStrokeOverlayModel model, double x, double y) {
    final from = model.dabs.length;
    model.dabs.add(
      BrushDab(
        center: CanvasPoint(x: x, y: y),
        color: 0xFF000000,
        size: 3,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: from,
      ),
    );
    final region = rasterizer.blendFrom(model.dabs, from: from)!;
    model.updateRegion(source: rasterizer, region: region);
    return region;
  }

  test('what moved since a mark: all of it, across the tiles', () {
    final model = overlayOn();
    final mark = model.moveMark;
    final first = dabInto(model, 4, 4);
    final second = dabInto(model, 21, 5);

    expect(model.movedSince(mark), first.union(second));
    expect(
      first.union(second).width,
      lessThan(4 * tileSize),
      reason: '⛔premise: it says less than the tiles it crossed',
    );
  });

  test('a mark sees only what came after it', () {
    final model = overlayOn();
    dabInto(model, 4, 4);
    final mark = model.moveMark;
    final after = dabInto(model, 21, 5);

    expect(model.movedSince(mark), after);
  });

  test('being asked moves nothing: the same mark, the same answer', () {
    final model = overlayOn();
    final mark = model.moveMark;
    final moved = dabInto(model, 4, 4);
    model.tileImages;

    expect(model.movedSince(mark), moved);
    expect(model.movedSince(mark), moved);
  });

  test('nothing moved since: nothing to tell', () {
    final model = overlayOn();
    dabInto(model, 4, 4);

    expect(model.movedSince(model.moveMark), isNull);
  });

  test('⛔another overlay\'s mark says nothing here', () {
    final model = overlayOn();
    final other = overlayOn();
    dabInto(model, 4, 4);

    expect(model.movedSince(other.moveMark), isNull);
  });

  group('⛔pictures that changed some other way:', () {
    /// [model], a dab in hand and a mark from before it, as a screen keeps
    /// one between two looks — its premise said.
    OverlayMoveMark markBeforeADab(ActiveStrokeOverlayModel model) {
      final mark = model.moveMark;
      dabInto(model, 4, 4);
      expect(model.movedSince(mark), isNotNull, reason: '⛔premise: it tells');
      return mark;
    }

    test('a stroke let go', () {
      final model = overlayOn();
      final mark = markBeforeADab(model);

      model.reset();

      expect(model.movedSince(mark), isNull);
    });

    test('a fill\'s tiles', () {
      final model = overlayOn();
      final mark = markBeforeADab(model);

      model.showResultTiles([PromotedStrokeTile(farTile, tile, 1)]);

      expect(model.movedSince(mark), isNull);
    });

    test('a shape put up', () {
      final model = overlayOn();
      final mark = markBeforeADab(model);

      model.showStaged(const []);

      expect(model.movedSince(mark), isNull);
    });

    test('a tile handed over at pen-up', () {
      final model = overlayOn()
        ..showResultTiles([PromotedStrokeTile(farTile, tile, 1)]);
      final mark = markBeforeADab(model);

      expect(model.takeTileImageAt(farTile, revision: 1), isNotNull);

      expect(model.movedSince(mark), isNull);
    });

  });
}
