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
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';

/// 🚨★★★A CEL THE CANVAS DREW LIVE IS ITS GHOST ON THE FRAME AFTER — WHOLE
/// (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// The cel you are drawing on is drawn live; the onion ghosts are one
/// picture over the frame's, drawn as they stand from the cels in hand
/// until it is made. Step to the next frame and the cel you were just
/// drawing is the ghost behind it — and if it is not in hand (an edit
/// leaves its stored pixels to be laid out again) the ghost used to show
/// NOTHING for the frames an asynchronous read takes: what you had just
/// drawn vanished and came back.
///
/// 🔬Measured on these fixtures before the fix (2026-09-17, when the ghosts
/// were stacked from their rows' images): at 50% on the display buffer
/// **0 of 32** columns on the first frame, and at 100% on the direct walk,
/// again **0 of 32**. ↩️The two routes were one when the ghosts were one
/// picture (one-picture-per-frame ②-5b-1), which read nothing on this
/// thread until it was told what the canvas drew live.
///
/// The ghosts' view reads which cels the canvas under it drew live the build
/// it replaces ([FramePictureView.drawnLive]) and reads those on the spot.
///
/// ⛔AND ONLY THOSE. A cel that was NOT on screen — a frame scrubbed to, a
/// project just opened — is not read inside the build: a whole cold stack
/// read in one build is a stall nobody asked for.
void main() {
  const tileSize = 16;
  const tileCount = 8;
  const canvasSize = CanvasSize(width: tileSize * tileCount, height: tileSize);
  // The VIEW is two tiles wide; the cel is eight.
  const viewSize = Size(tileSize * 2.0, tileSize * 1.0);
  const zoom = 0.5;

  BrushFrameKey keyOf(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 2,
    canvasSize: canvasSize,
    layers: const [],
  );
  final screen = GlobalKey();

  /// One blue cel of eight tiles.
  BitmapSurface blue() {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(size: tileSize, pixels: pixels);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  /// The cels of [frames], each one [blue] cel kept in a file — none in
  /// hand until it is read.
  LayerFrameImageCache blueCels(List<String> frames) {
    final store = BrushFrameStore();
    keepInAFile(store, {for (final frame in frames) keyOf(frame): blue()});
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    return images;
  }

  StackRun runOf(LayerFrameImageCache images) {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    return runOver(images, store, canvasSize: canvasSize, stackOf: (_) => []);
  }

  /// The ghosts' view at [frame]: [ghosts], over a canvas that draws
  /// [drawnLive] live.
  Future<void> pumpGhosts(
    WidgetTester tester,
    StackRun run,
    List<BrushFrameKey> ghosts, {
    required int frame,
    required Set<BrushFrameKey> drawnLive,
  }) => tester.pumpWidget(
    onAScreen(
      screen,
      size: viewSize,
      under: const Color(0xFF000000),
      view: FramePictureView(
        run: run,
        picture: (cut: cut, frameIndex: frame, paintPaper: false),
        nodes: [
          for (final ghost in ghosts)
            CompositeLeaf<CanvasStackRow>(
              CanvasLayerImageRequest(frameKey: ghost, opacity: 1),
            ),
        ],
        viewport: CanvasViewport(zoom: zoom),
        laysWhatItMisses: true,
        wholeFrames: false,
        drawnLive: drawnLive,
      ),
    ),
  );

  /// Blue columns on the row through the middle of the cel.
  int blueColumns(Shot shot) {
    var n = 0;
    final row = (tileSize * zoom / 2).floor();
    for (var x = 0; x < shot.width; x += 1) {
      final o = (row * shot.width + x) * 4;
      if (shot.rgba[o + 2] > 0xC8 && shot.rgba[o + 3] == 0xFF) n += 1;
    }
    return n;
  }

  bool inHand(LayerFrameImageCache images, BrushFrameKey cel) =>
      images.storedSurfaceIsInHand(cel, canvasSize: canvasSize);

  testWidgets('🚨zoomed out: the cel drawn live is whole as its ghost on the '
      'first frame after the step', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = blueCels(['drawn']);
    final run = runOf(images);
    final drawn = keyOf('drawn');

    await pumpGhosts(tester, run, const [], frame: 0, drawnLive: {drawn});
    expect(inHand(images, drawn), isFalse, reason: '⛔premise: not in hand');

    // THE STEP: the cel is a ghost now. ONE frame — ⛔not pumpAndSettle,
    // which would let the asynchronous read land.
    await pumpGhosts(tester, run, [drawn], frame: 1, drawnLive: const {});

    expect(
      blueColumns(await shotOf(tester, screen)),
      viewSize.width.toInt(),
      reason: 'the ghosts\' view was told the canvas drew it live, so it '
          'reads it on this thread — else what you had just been drawing '
          'vanishes until an asynchronous read lands',
    );
  });

  testWidgets('⛔a cel the canvas did NOT draw live is not read inside the '
      'build — it arrives with the asynchronous read', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = blueCels(['drawn', 'cold']);
    final run = runOf(images);
    final cold = keyOf('cold');

    await pumpGhosts(
      tester,
      run,
      const [],
      frame: 0,
      drawnLive: {keyOf('drawn')},
    );
    // A ghost nobody was looking at comes in (a frame scrubbed to).
    await pumpGhosts(tester, run, [cold], frame: 1, drawnLive: const {});

    // ⚠️Not asked by whether the cel is in hand after the pump: in this
    // runner the asynchronous read lands in the microtasks that follow the
    // frame, so only the frame itself tells it from a read in the build.
    expect(
      blueColumns(await shotOf(tester, screen)),
      0,
      reason: 'a build must not read a cold cel: with a stack of cold rows — '
          'every frame scrubbed to — that is the whole stack read inside '
          'one build. Its first frame is the asynchronous read\'s to fill — '
          'if this ever reads whole, the cold half of the law has been '
          'widened and the stall came with it',
    );
  });
}
