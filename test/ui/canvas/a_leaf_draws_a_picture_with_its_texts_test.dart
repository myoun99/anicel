import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// 🚨★★★A LEAF CANNOT DRAW A PICTURE WITHOUT ITS TEXTS (R9-rest, the text
/// tool — 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」).
///
/// Two families draw a cel's tiles: the painter (`BitmapSurfacePainter`)
/// and the compose (`tiled_surface_compose.dart`). Every route that shows a
/// cel ends at one of them, and each lays the texts over the drawing for
/// itself — so a new panel that mounts a painter, or a new render that
/// composes a surface, cannot be the route that forgot. These hand each
/// leaf a surface that STILL CARRIES its texts, as such a route would.
void main() {
  final drawn = TileCoord(x: 0, y: 0);
  // On the pasteboard, past the canvas's right edge (32 px = four tiles).
  final pastTheEdge = TileCoord(x: 5, y: 1);
  final ink = tileOf({
    (1, 1): [10, 20, 30, 255],
    (2, 1): [10, 20, 30, 120],
  });
  final letters = tileOf({
    (1, 1): [200, 0, 0, 160],
    (5, 5): [200, 0, 0, 255],
  });

  BitmapSurface picture() => drawingOf({drawn: ink}).withTexts([
    textOf(1, plate: {drawn: letters, pastTheEdge: letters}),
  ]);

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  group('the painter', () {
    test('draws the laid tiles of a surface handed to it with its texts', () {
      final withTexts = picture();

      final painter = BitmapSurfacePainter(surface: withTexts);

      expect(painter.surface, same(celSurfaceWithTextsLaid(withTexts)));
      expect(painter.surface.texts, isEmpty);
      expect(
        painter.surface.tileAt(pastTheEdge),
        isNotNull,
        reason: 'the letters past the drawing are tiles it draws',
      );
    });

    test('a text past the drawing is inside what it says it draws', () {
      final painter = BitmapSurfacePainter(
        surface: picture(),
        showTransparentBackground: false,
      );

      expect(painter.drawnWorldRect.right, (pastTheEdge.x + 1) * 8.0);
      expect(painter.drawnWorldRect.bottom, (pastTheEdge.y + 1) * 8.0);
    });

    test('a surface with no text is drawn as the object it is', () {
      final bare = drawingOf({drawn: ink});

      expect(BitmapSurfacePainter(surface: bare).surface, same(bare));
    });
  });

  group('the compose', () {
    test('a text past the drawing grows the rect a compose rasters', () {
      final withTexts = picture();

      expect(surfaceContentWorldRect(withTexts).right, 48);
      expect(surfaceContentWorldRect(drawingOf({drawn: ink})).right, 32);
      expect(surfaceInkWorldRect(withTexts).right, 48);
      expect(surfaceInkWorldRect(withTexts).bottom, 16);
    });

    testWidgets('🚨every compose draws the letters: the image of a surface '
        'handed over with its texts is the image of its laid tiles', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final withTexts = picture();
        final laid = celSurfaceWithTextsLaid(withTexts);
        final cache = BitmapTileImageCache();
        final reference = await bytesOf(
          composeTiledSurfaceImageNow(laid, reuse: cache),
        );
        final drawingAlone = await bytesOf(
          composeTiledSurfaceImageNow(drawingOf({drawn: ink}), reuse: cache),
        );
        expect(reference, isNot(drawingAlone), reason: '⛔fixture: letters');

        expect(
          await bytesOf(composeTiledSurfaceImageNow(withTexts, reuse: cache)),
          reference,
          reason: 'the synchronous canvas-sized compose',
        );
        expect(
          await bytesOf((await composeTiledSurfaceImage(withTexts))!),
          reference,
          reason: 'the asynchronous canvas-sized compose',
        );

        // The positioned twins raster the content — and the letters past
        // the canvas edge are content.
        final positionedReference = await composePositionedSurfaceImage(laid);
        final positioned = await composePositionedSurfaceImage(withTexts);
        expect(positioned!.worldRect, positionedReference!.worldRect);
        expect(positioned.worldRect.right, 48);
        expect(
          await bytesOf(positioned.image),
          await bytesOf(positionedReference.image),
          reason: 'the asynchronous positioned compose',
        );
        final sync = composePositionedSurfaceImageSync(
          withTexts,
          reuse: cache,
          makePictures: true,
          snapshot: false,
        )!;
        final syncReference = composePositionedSurfaceImageSync(
          laid,
          reuse: cache,
          makePictures: true,
          snapshot: false,
        )!;
        expect(sync.deferred.worldRect, syncReference.deferred.worldRect);
        expect(
          await bytesOf(sync.deferred.image),
          await bytesOf(syncReference.deferred.image),
          reason: 'the synchronous positioned compose',
        );
      });
    });
  });
}
