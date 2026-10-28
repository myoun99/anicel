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
import 'package:anicel/src/ui/playback/frame_picture_view.dart' show StackRun;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/settle_async.dart';

/// H27 — 「이전 변형하기 전 그림이 남아있었음」 (iPhone, 2026-08-27): a second
/// transform's confirm left the drawing as it was BEFORE it on screen until
/// the view moved — an idle phone draws no next frame of its own. And since
/// 2026-09-17 the edit's frame is the edit, not a blank (유저 절대규칙
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// A canvas standing on a frame shows a cel edited off the pen — a
/// transform's confirm, an undo — at the next frame: the edit moves the
/// frame's key, and a frame whose picture is not there yet is drawn as it
/// stands. A build that edits nothing keeps the picture it shows.
///
/// ↩️Pinned on the editing stack's held row images — the picture before the
/// edit kept on a cold miss — until a frame's one picture was all a screen
/// drew (one-picture-per-frame ②-5b-1).
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 16);
  const viewSize = Size(32, 16);
  const under = Color(0xFF000000);
  const red = [0xFF, 0x00, 0x00, 0xFF];
  const blue = [0x00, 0x00, 0xFF, 0xFF];

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: key.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: const [],
  );
  // No paper: the screen shows the cel alone.
  final frame = (cut: cut, frameIndex: 0, paintPaper: false);
  final screen = GlobalKey();

  BitmapSurface filled(List<int> colour) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var tx = 0; tx < 2; tx += 1)
        TileCoord(x: tx, y: 0): BitmapTile(
          size: tileSize,
          pixels: Uint8List.fromList([
            for (var i = 0; i < tileSize * tileSize; i += 1) ...colour,
          ]),
        ),
    },
  );

  /// A fresh tree each build, as the editor hands one on every rebuild.
  List<CompositeNode<CanvasStackRow>> nodes() => [
    const CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: key, opacity: 1),
    ),
  ];

  Future<void> standOn(WidgetTester tester, StackRun run) => tester.pumpWidget(
    onAScreen(
      screen,
      size: viewSize,
      under: under,
      view: standingOn(
        run,
        picture: frame,
        nodes: nodes(),
        viewport: CanvasViewport(),
        live: (activeSurfacePainter: null, floatOverlay: null, liftedRows: {}),
      ),
    ),
  );

  List<int> pixelAt(Shot shot, int x, int y) =>
      shot.rgba.sublist((y * shot.width + x) * 4, (y * shot.width + x) * 4 + 4);

  ({BrushFrameStore cels, StackRun run, FramePictureStore<FramePictureKey> store})
  standing() {
    final cels = BrushFrameStore()..storeBakedSurface(key, filled(red));
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes(),
    );
    return (cels: cels, run: run, store: store);
  }

  testWidgets('🚨a cel edited off the pen shows its edit at the next frame — '
      'not the picture before it', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final (:cels, :run, :store) = standing();
    await standOn(tester, run);
    final before = run.pictures.keyOfStack(nodes(), frame);
    expect(
      await settleAsync(tester, () => store.peek(before) != null),
      isTrue,
      reason: '⛔premise: the frame\'s picture is made',
    );
    await standOn(tester, run);
    expect(pixelAt(await shotOf(tester, screen), 20, 8), red);

    // A transform's confirm: the cel's pixels replaced, off the pen.
    cels.storeBakedSurface(key, filled(blue));
    cels.markCelEdited(key);
    expect(
      run.pictures.keyOfStack(nodes(), frame),
      isNot(before),
      reason: '⛔premise: the edit moved the frame\'s key',
    );
    await standOn(tester, run);

    expect(pixelAt(await shotOf(tester, screen), 20, 8), blue);
  });

  testWidgets('a build that edits nothing keeps the picture it shows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final (cels: _, :run, :store) = standing();
    await standOn(tester, run);
    final shown = run.pictures.keyOfStack(nodes(), frame);
    expect(
      await settleAsync(tester, () => store.peek(shown) != null),
      isTrue,
      reason: '⛔premise: the frame\'s picture is made',
    );
    await standOn(tester, run);
    expect(store.pinnedBytes, store.bytesOf(shown), reason: 'it shows it');

    await standOn(tester, run);

    expect(
      store.pinnedBytes,
      store.bytesOf(shown),
      reason: 'the same picture, held through the build',
    );
    expect(pixelAt(await shotOf(tester, screen), 20, 8), red);
  });
}
