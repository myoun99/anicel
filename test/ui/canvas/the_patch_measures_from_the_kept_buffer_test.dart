import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨F-68 ③ (유저 2026-09-11, Windows debug AND iPad release): 「축소시
/// 변형툴 밖의 이전그림 위치에 그림 생기는건 여전히 존재. 펜으로 바꿔서
/// 그부분 그리려하면 정상적으로 사라짐. 진짜 보이는거만 문제인듯.」
///
/// The display buffer patched a miss over the KEPT image, repainting only
/// where the live surface changed. It asked "changed since when?" of
/// tokens it re-recorded on EVERY paint — including the paints that kept
/// nothing (a floating selection made the buffer uncacheable for the whole
/// session). So after a lift (erase, float up: nothing kept) and a confirm
/// (float gone: cacheable again), the base was the buffer from BEFORE the
/// lift and the dirty rect was only what the confirm changed: the erased
/// ring came back from the old buffer, and stayed until something else
/// repainted it — the pen, another transform, a full raster.
///
/// The frame's one picture is that kept image now: what the live rows
/// moved is measured from what the PICTURE holds of them, and a paint that
/// draws the frame as it stands — the float up — moves nothing it holds.
void main() {
  // Two tiles across, one down — a ring needs a tile the landing does not
  // touch, or the dirty rect is the whole canvas and nothing can go stale.
  const canvasSize = CanvasSize(width: 8, height: 4);
  const viewSize = Size(8, 4);
  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);
  final screen = GlobalKey();

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  final picture = (
    cut: Cut(
      id: key.cutId,
      name: 'c',
      duration: 1,
      canvasSize: canvasSize,
      layers: const [],
    ),
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final nodes = [
    const CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: key),
    ),
  ];

  BitmapTile inked(int x, int y, RgbaColor color) => writeRgbaColorToBitmapTile(
    tile: BitmapTile.blank(size: 4),
    x: x,
    y: y,
    color: color,
  );

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: 4, tiles: tiles);

  BitmapSurfacePainter painterOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurfacePainter(
        surface: surfaceOf(tiles),
        showTransparentBackground: false,
      );

  testWidgets('a patch writes in everything the live row moved since the '
      'PICTURE took it in, not since the last paint', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);

    // The picture before the lift: red in the LEFT tile, blue in the
    // right — the cel as stored, and the live row as it draws it.
    final left = inked(1, 1, red);
    final right = inked(1, 1, blue);
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      key: surfaceOf({
        TileCoord(x: 0, y: 0): left,
        TileCoord(x: 1, y: 0): right,
      }),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
    );

    Future<void> pumpWith(BitmapSurfacePainter active) => tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: const Color(0xFF00FF00),
        view: standingOn(
          run,
          picture: picture,
          nodes: nodes,
          viewport: CanvasViewport(),
          live: (
            activeSurfacePainter: active,
            floatOverlay: float,
            liftedRows: const {},
          ),
        ),
      ),
    );
    bool isRed(Shot shot, int x, int y) =>
        shot.rgba[(y * shot.width + x) * 4] > 200 &&
        shot.rgba[(y * shot.width + x) * 4 + 1] < 60;

    await pumpWith(
      painterOf({TileCoord(x: 0, y: 0): left, TileCoord(x: 1, y: 0): right}),
    );
    final shown = run.pictures.keyOfStack(nodes, picture);
    expect(
      await settleAsync(tester, () => store.bytesOf(shown) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    expect(
      isRed(await shotOf(tester, screen), 1, 1),
      isTrue,
      reason: '⛔premise: the picture shows the red pixel',
    );

    // The LIFT: the left tile is erased (dropped) and its pixels float,
    // drawn one tile to the right. A floating selection is not told by
    // where it lands, so the frame is drawn as it stands.
    float.value = SelectionFloatPaint(
      surface: painterOf({TileCoord(x: 0, y: 0): left}),
      surfaceOffset: CanvasPoint(x: 4, y: 0),
    );
    await pumpWith(painterOf({TileCoord(x: 1, y: 0): right}));
    final lifted = await shotOf(tester, screen);
    expect(isRed(lifted, 1, 1), isFalse, reason: '⛔premise: the erase shows');
    expect(isRed(lifted, 5, 1), isTrue, reason: '⛔premise: the float shows');

    // The CONFIRM: the float lands in the RIGHT tile (a new tile object
    // there) and the float goes. The left tile stays erased — nothing on
    // this paint touches it, and that is the whole point.
    float.value = null;
    final landed = writeRgbaColorToBitmapTile(
      tile: right,
      x: 1,
      y: 1,
      color: red,
    );
    await pumpWith(painterOf({TileCoord(x: 1, y: 0): landed}));
    await lendBothClocks(tester, rounds: 2);
    final confirmed = await shotOf(tester, screen);
    expect(
      isRed(confirmed, 5, 1),
      isTrue,
      reason: 'LIVENESS: what landed shows',
    );
    expect(
      isRed(confirmed, 1, 1),
      isFalse,
      reason: 'the erased tile shows the picture from BEFORE the lift: '
          'what the live row moved was measured from the last paint instead '
          'of from what the picture holds',
    );
  });
}
