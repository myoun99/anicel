import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show DemandedPicture, FrameGhosts;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/picture_up_view.dart';
import 'package:anicel/src/ui/engine_screen_texture.dart' show PicturesLeftUp;
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨★★★A CUT THE FILM CROSSES INTO STANDS ON THE PICTURE LEFT UP TILL ITS
/// OWN IS UP (F-599, 유저 2026-11-16: 「콘티패널에서 재생시 컷 넘어갈때
/// 캔버스에 검은프레임 생김」; F-365-Q2 「컷을 넘을 때도 직전 그림을
/// 남기고」). The film's unit of a cut is keyed by the cut, so the cut coming
/// in is a screen made anew — 🔬on the Surface Pro 11 it had no texture at
/// its first paint and none of its frames finished for two or three after,
/// and the stage's floor showed through. Its first paint is the picture
/// the cut going out left up, never the floor.
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSize, height: 2 * tileSize);
  const viewSize = Size(2.5 * tileSize, 2.5 * tileSize);
  const going = [0x30, 0x60, 0x90, 0xFF];
  const coming = [0x90, 0x30, 0x60, 0xFF];
  // The floor: the backdrop the film lies on, and what shows where no
  // picture is up.
  const floor = Color(0xFF203040);
  const floorRgba = [0x20, 0x30, 0x40, 0xFF];

  BrushFrameKey celOf(String cut) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: CutId(cut),
    layerId: LayerId('$cut-ink'),
    frameId: FrameId('$cut-f'),
  );
  Cut cutOf(String id) {
    final cel = celOf(id);
    return Cut(
      id: cel.cutId,
      name: id,
      duration: 1,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: cel.layerId,
          name: 'Ink',
          frames: [Frame(id: cel.frameId, duration: 1, strokes: const [])],
          timeline: {0: TimelineExposure.drawing(cel.frameId, length: 1)},
        ),
      ],
    );
  }

  final first = cutOf('c1');
  final second = cutOf('c2');
  final layout = buildStoryboardTimelineLayout(
    Project(
      id: const ProjectId('p'),
      name: 'Project',
      cameraSize: canvasSize,
      tracks: [
        Track(id: const TrackId('t'), name: 'Track', cuts: [first, second]),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );
  List<CompositeNode<CanvasStackRow>> rowsOf(Cut cut) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: celOf(cut.id.value), opacity: 1),
    ),
  ];
  DemandedPicture frameOf(Cut cut) => (
    cut: cut,
    frameIndex: 0,
    paintPaper: true,
    ghosts: FrameGhosts.none,
  );

  BitmapSurface inked(List<int> colour) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < 2; ty += 1)
        for (var tx = 0; tx < 2; tx += 1)
          TileCoord(x: tx, y: ty): BitmapTile(
            size: tileSize,
            pixels: Uint8List.fromList([
              for (var at = 0; at < tileSize * tileSize; at += 1) ...colour,
            ]),
          ),
    },
  );

  final screen = GlobalKey();

  List<int> mid(Shot shot) {
    const x = tileSize;
    const y = tileSize;
    final at = (y * shot.width + x) * 4;
    return shot.rgba.sublist(at, at + 4);
  }

  testWidgets('🚨the film crossing into a cut shows, at the new cut\'s first '
      'paint, the picture the cut going out left up — not its floor — and '
      'the new cut\'s own once it is up', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {celOf('c1'): inked(going), celOf('c2'): inked(coming)});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    final StackRun road = (
      landings: landings,
      pictures: FramePictures(
        store: store,
        layerImages: images,
        stackOf: (picture) => rowsOf(picture.cut),
        pageOf: (picture) => (
          canvasSize: canvasSize,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: picture.paintPaper,
          paperBackground: ProjectBackground.defaultBackground,
        ),
      ),
    );
    final playhead = ValueNotifier<int?>(0);
    addTearDown(playhead.dispose);
    final pictureUp = PictureUpView();
    addTearDown(pictureUp.dispose);
    final atRest = CameraPose(
      center: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: screen,
            child: SizedBox.fromSize(
              size: viewSize,
              child: PictureUpViewScope(
                view: pictureUp,
                together: PicturesUpTogether(),
                picturesLeftUp: PicturesLeftUp(),
                child: CanvasTrackStackView(
                  globalFrame: playhead,
                  positionsOf: (frame) => resolveTrackStackContributions(
                    layout: layout,
                    spansOf: (_) => const [],
                    globalFrameIndex: frame,
                  ),
                  stackOf: (cut, _) => rowsOf(cut),
                  pictures: road,
                  cameraFrameSize: canvasSize,
                  cameraViewEnabled: false,
                  cameraPoseOf: (_, _) => atRest,
                  viewport: CanvasViewport(),
                  backdropArgb: floor.toARGB32(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> upOf(Cut cut) async {
      expect(
        await settleAsync(
          tester,
          () =>
              road.pictures.store.bytesOf(
                road.pictures.keyOfStack(rowsOf(cut), frameOf(cut)),
              ) !=
              null,
        ),
        isTrue,
        reason: 'LIVENESS: ${cut.name}\'s picture is made',
      );
      await lendBothClocks(tester, rounds: 2);
    }

    await upOf(first);
    expect(
      mid(await shotOf(tester, screen)),
      going,
      reason: '⛔premise: the cut going out shows its picture',
    );

    playhead.value = 1;
    await tester.pump();
    final crossed = mid(await shotOf(tester, screen));
    expect(
      crossed,
      isNot(floorRgba),
      reason: 'the film\'s floor showed at the cut coming in (F-599)',
    );
    expect(
      crossed,
      going,
      reason: 'the cut coming in has put none up: the picture left up stands',
    );

    await upOf(second);
    expect(
      mid(await shotOf(tester, screen)),
      coming,
      reason: 'up, the cut coming in shows its own',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
