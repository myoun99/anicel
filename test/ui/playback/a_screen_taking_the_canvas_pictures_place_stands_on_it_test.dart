import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show DemandedPicture, FrameGhosts;
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
import 'package:anicel/src/native/screen_texture.dart' show ScreenTexture;
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/picture_up_view.dart';
import 'package:anicel/src/ui/engine_screen_texture.dart' show PicturesLeftUp;
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨★★★THE CANVAS'S PICTURE STANDS TILL THE SCREEN THAT TAKES ITS PLACE
/// PUTS ONE UP (F-599, 유저 2026-11-16: the conte's run showed a black
/// frame on the canvas at every cut it crossed; F-365-Q2 「컷을 넘을 때도
/// 직전 그림을 남기고」). A screen made anew has no texture at its first
/// paint, and none of its frames finished for a few after: the floor under
/// it showed. The picture handed on is the canvas's own, on its paper —
/// never one off it (the ghosts over the frame, a track over the stage).
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSize, height: 2 * tileSize);
  const viewSize = Size(3.0 * tileSize, 2.5 * tileSize);
  const fill = [0x30, 0x60, 0x90, 0xFF];
  const other = [0x90, 0x30, 0x60, 0xFF];
  const under = Color(0xFF203040);
  const underRgba = [0x20, 0x30, 0x40, 0xFF];
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
  DemandedPicture frameOf({required bool paper}) => (
    cut: cut,
    frameIndex: 0,
    paintPaper: paper,
    ghosts: FrameGhosts.none,
  );
  final screen = GlobalKey();

  List<CompositeNode<CanvasStackRow>> treeOf() => [
    const CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: inked, opacity: 1),
    ),
  ];

  /// The frame's picture, its cel all [colour].
  StackRun aRunOf(List<int> colour) {
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
                  for (var at = 0; at < tileSize * tileSize; at += 1)
                    ...colour,
                ]),
              ),
        },
      ),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    return runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => treeOf(),
    );
  }

  final LiveRows live = (
    activeSurfacePainter: BitmapSurfacePainter(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
      showTransparentBackground: false,
      lineage: 'a-screen-taking-the-place',
    ),
    floatOverlay: null,
    liftedRows: const {},
  );

  /// The canvas, one screen on it: [run]'s, by [key] — on its paper where
  /// [paper] says, as the canvas's own picture is.
  Widget theCanvas(
    StackRun run,
    Key key, {
    required PictureUpView pictureUp,
    required PicturesLeftUp leftUp,
    bool paper = true,
  }) => onAScreen(
    screen,
    size: viewSize,
    under: under,
    view: PictureUpViewScope(
      view: pictureUp,
      together: PicturesUpTogether(),
      picturesLeftUp: leftUp,
      child: standingOn(
        run,
        key: key,
        picture: frameOf(paper: paper),
        nodes: treeOf(),
        viewport: view,
        live: live,
      ),
    ),
  );

  List<int> onThePage(Shot shot) {
    const x = tileSize * 5 ~/ 4;
    const y = tileSize * 3 ~/ 4;
    final at = (y * shot.width + x) * 4;
    return shot.rgba.sublist(at, at + 4);
  }

  Future<void> upIn(WidgetTester tester, StackRun run, {bool paper = true}) =>
      settleAsync(
        tester,
        () => run.pictures.allInHand(treeOf(), frameOf(paper: paper)),
      ).then((inHand) async {
        expect(inHand, isTrue, reason: 'LIVENESS: the cel is read');
        // A screen of a file just opened stands bare till its frame's
        // picture comes, in real time: waited for, not given rounds — two
        // were what the Surface needed and too few on lavapipe (the-bundle-
        // pr-ci-is-red-on-two-frame-screen-tests-on-linux).
        await theFrameIsShown(tester);
      });

  testWidgets('🚨a screen that takes the place of the canvas\'s picture '
      'stands on the picture left up till it has put one up', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final pictureUp = PictureUpView();
    addTearDown(pictureUp.dispose);
    final leftUp = PicturesLeftUp();
    final first = aRunOf(fill);
    final next = aRunOf(other);
    await tester.pumpWidget(
      theCanvas(
        first,
        const ValueKey('first'),
        pictureUp: pictureUp,
        leftUp: leftUp,
      ),
    );
    await upIn(tester, first);
    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: '⛔premise: the first screen shows its picture',
    );
    final oneScreen = ScreenTexture.liveBytes;

    await tester.pumpWidget(
      theCanvas(
        next,
        const ValueKey('next'),
        pictureUp: pictureUp,
        leftUp: leftUp,
      ),
    );
    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: 'the screen made anew has put none up: the picture left up '
          'stands — not the floor under it',
    );

    await upIn(tester, next);
    expect(
      onThePage(await shotOf(tester, screen)),
      other,
      reason: 'up, the screen shows its own, and the picture left up goes',
    );
    expect(
      ScreenTexture.liveBytes,
      oneScreen,
      reason: 'up, the picture left up is freed — not kept till the screen '
          'goes',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a picture off its paper — the ghosts over the frame, a track '
      'over the stage — takes none', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final pictureUp = PictureUpView();
    addTearDown(pictureUp.dispose);
    final leftUp = PicturesLeftUp();
    final first = aRunOf(fill);
    final next = aRunOf(other);
    await tester.pumpWidget(
      theCanvas(
        first,
        const ValueKey('first'),
        pictureUp: pictureUp,
        leftUp: leftUp,
      ),
    );
    await upIn(tester, first);
    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: '⛔premise: the first screen shows its picture',
    );

    await tester.pumpWidget(
      theCanvas(
        next,
        const ValueKey('next'),
        pictureUp: pictureUp,
        leftUp: leftUp,
        paper: false,
      ),
    );
    expect(
      onThePage(await shotOf(tester, screen)),
      underRgba,
      reason: 'off its paper, the screen stands on no picture left up',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
