import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨★★★THE FRAME YOU LEFT DOES NOT STAY ON THE PASTEBOARD (F-104,
/// 2026-09-12).
///
/// 유저: 「페이스트 보드에 이전 프레임의 그림이 남아있음 … 그 위치에 선을
/// 그리면 사라짐. 즉 디스플레이에만 남아있는듯」 · 「그렇게 사라져도
/// 이전프레임 갔다가 다시 돌아오면 똑같이 그림이 남아있음」.
///
/// 🔬Reproduced before the fix (2026-09-15): switching the active cel was a
/// change of the LIVE surface only, so the display buffer CARRIED the buffer
/// it made for the frame before and recomposed where the live surface moved
/// — painting over what it carried without clearing, so wherever the frame
/// you went to draws nothing, the frame you came from stayed. It showed on
/// the pasteboard because that is where two frames' extents differ: frame
/// B's own ink stretched the buffer over the spot where frame A had ink.
///
/// Each frame is its one picture now, and the frame you go to is its own —
/// ⛔never the picture you left moved under its key, as a stroke that lands
/// moves one.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 32);
  const tileSize = 16;
  const view = Size(96, 96);
  const backdrop = [128, 128, 128, 255];
  final screen = GlobalKey();

  BrushFrameKey keyOf(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );
  final a = keyOf('a');
  final b = keyOf('b');
  final cut = Cut(
    id: a.cutId,
    name: 'c',
    duration: 2,
    canvasSize: canvasSize,
    layers: const [],
  );

  Uint8List rgba(int r, int g, int b) {
    final bytes = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 255;
    }
    return bytes;
  }

  BitmapSurface surfaceWith(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: tileSize, tiles: tiles);

  for (final zoom in [1.0, 0.5]) {
    testWidgets('🚨at zoom $zoom, going A → B → A → B never shows A\'s ink '
        'where B has none', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      // Frame A: red at tile (-1, 1), canvas (-16..0, 16..32).
      final frameA = surfaceWith({
        TileCoord(x: -1, y: 1): BitmapTile(
          size: tileSize,
          pixels: rgba(255, 0, 0),
        ),
      });
      // Frame B: nothing there, and blue ink of its own at tile (-2, 0) —
      // which is what stretches its extent over A's red.
      final frameB = surfaceWith({
        TileCoord(x: -2, y: 0): BitmapTile(
          size: tileSize,
          pixels: rgba(0, 0, 255),
        ),
      });
      final cels = BrushFrameStore();
      keepInAFile(cels, {a: frameA, b: frameB});
      final images = LayerFrameImageCache(frameStore: cels);
      addTearDown(images.dispose);
      final store = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
      addTearDown(store.dispose);
      List<CompositeNode<CanvasStackRow>> stackOn(BrushFrameKey cel) => [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: cel),
        ),
      ];
      final run = runOver(
        images,
        store,
        canvasSize: canvasSize,
        stackOf: (picture) => stackOn(picture.frameIndex == 0 ? a : b),
      );
      final viewport = CanvasViewport(zoom: zoom, panX: 32, panY: 32);
      Offset onScreen(double x, double y) =>
          Offset(32 + x * zoom, 32 + y * zoom);
      // The middle of A's red tile, and of B's blue one.
      final whereAWas = onScreen(-8, 24);
      final whereBIs = onScreen(-24, 8);

      /// The canvas standing on [cel]'s frame, once its picture is there.
      Future<Shot> show(BrushFrameKey cel, BitmapSurface surface) async {
        final picture = (
          cut: cut,
          frameIndex: cel == a ? 0 : 1,
          paintPaper: true,
          ghosts: false,
        );
        final nodes = stackOn(cel);
        await tester.pumpWidget(
          onAScreen(
            screen,
            size: view,
            under: const Color(0xFF808080),
            view: standingOn(
              run,
              picture: picture,
              nodes: nodes,
              viewport: viewport,
              live: (
                activeSurfacePainter: BitmapSurfacePainter(
                  surface: surface,
                  showTransparentBackground: false,
                ),
                floatOverlay: null,
                liftedRows: const {},
              ),
            ),
          ),
        );
        final key = run.pictures.keyOfStack(nodes, picture);
        expect(
          await settleAsync(tester, () => store.bytesOf(key) != null),
          isTrue,
          reason: 'LIVENESS: the frame\'s picture is made',
        );
        await lendBothClocks(tester, rounds: 2);
        return shotOf(tester, screen);
      }

      List<int> colorAt(Shot shot, Offset at) {
        final i = (at.dy.round() * shot.width + at.dx.round()) * 4;
        return shot.rgba.sublist(i, i + 4);
      }

      for (final visit in [1, 2]) {
        expect(
          colorAt(await show(a, frameA), whereAWas),
          [255, 0, 0, 255],
          reason: 'control (visit $visit): frame A has its ink there',
        );
        final onB = await show(b, frameB);
        expect(
          colorAt(onB, whereBIs),
          [0, 0, 255, 255],
          reason: 'control (visit $visit): the canvas is showing frame B — '
              'its own ink is there',
        );
        expect(
          colorAt(onB, whereAWas),
          backdrop,
          reason: 'visit $visit: frame B has nothing where frame A had ink, '
              'so nothing may be drawn there — A\'s ink staying is F-104',
        );
      }
    });
  }
}
