import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';


/// 🚨A SCREEN MOVED UNDER ANOTHER PARENT SHOWS ITS FRAME AGAIN
/// (frame-timing-overlay-hides-the-canvas, 검증 2026-11-15: 「캔버스 자리가
/// 통째로 어둡다 … 새 프로젝트를 열면 다시 그려진다」). Turning the frame
/// timing overlay on rebuilt the app round the canvas, which moved its
/// screens under another parent — the same boxes, detached and attached
/// again, laid out with the constraints they had — and the canvas stayed
/// dark till its boxes were made anew.
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSize, height: 2 * tileSize);
  const viewSize = Size(3.0 * tileSize, 2.5 * tileSize);
  const fill = [0x30, 0x60, 0x90, 0xFF];
  const under = Color(0xFF203040);
  final view = CanvasViewport(panX: tileSize / 2, panY: tileSize / 4);

  const inked = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: inked.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: inked.layerId,
        name: 'Layer',
        frames: [Frame(id: inked.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(inked.frameId, length: 1)},
      ),
    ],
  );
  // No paper: what lies under the ink is the screen's own.
  final frame = (
    cut: cut,
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final screen = GlobalKey();

  List<CompositeNode<CanvasStackRow>> treeOf() => [
    const CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: inked, opacity: 1),
    ),
  ];

  testWidgets('🚨the same box, moved under another parent, shows its frame '
      'again', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      inked: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          for (var ty = 0; ty < 2; ty += 1)
            for (var tx = 0; tx < 2; tx += 1)
              TileCoord(x: tx, y: ty): BitmapTile(
                size: tileSize,
                pixels: Uint8List.fromList([
                  for (var at = 0; at < tileSize * tileSize; at += 1) ...fill,
                ]),
              ),
        },
      ),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => treeOf(),
    );
    final LiveRows live = (
      activeSurfacePainter: BitmapSurfacePainter(
        surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
        showTransparentBackground: false,
        lineage: 'a-screen-moved',
      ),
      floatOverlay: null,
      liftedRows: const {},
    );
    final kept = GlobalKey();
    Widget shown({required bool moved}) {
      final picture = standingOn(
        run,
        key: kept,
        picture: frame,
        nodes: treeOf(),
        viewport: view,
        live: live,
      );
      return onAScreen(
        screen,
        size: viewSize,
        under: under,
        view: moved
            ? Padding(padding: EdgeInsets.zero, child: picture)
            : picture,
      );
    }

    RenderObject theBox() =>
        tester.renderObject(theFrameScreenIn(find.byType(FramePictureView)));
    List<int> onThePage(Shot shot) {
      const x = tileSize * 5 ~/ 4;
      const y = tileSize * 3 ~/ 4;
      final at = (y * shot.width + x) * 4;
      return shot.rgba.sublist(at, at + 4);
    }

    await tester.pumpWidget(shown(moved: false));
    expect(
      await settleAsync(tester, () => run.pictures.allInHand(treeOf(), frame)),
      isTrue,
      reason: 'LIVENESS: the cel is read',
    );
    // A file just opened stands bare till its frame's picture comes, in
    // real time: waited for, not given rounds — two were what the Surface
    // needed and too few on lavapipe (the-bundle-pr-ci-is-red-on-two-frame-
    // screen-tests-on-linux).
    await theFrameIsShown(tester);
    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: '⛔premise: the frame is shown',
    );
    final box = theBox();

    await tester.pumpWidget(shown(moved: true));
    expect(theBox(), same(box), reason: '⛔premise: moved, not made anew');
    // A boundary of its own, it is not painted again by being moved: the
    // layer it put up before stands in the tree. Asked to paint — as the
    // app's canvas is at anything that changes — it shows what it holds.
    box.markNeedsPaint();
    await lendBothClocks(tester, rounds: 2);

    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: 'moved under another parent, the box shows its frame again',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
