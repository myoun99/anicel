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

/// 🚨(v) — a floating selection moves under the hand, and the picture a
/// canvas keeps must never be shown while one exists.
///
/// The float is drawn in the live row's slot and changes without touching
/// anything a picture's tokens can see: not the layer tree, not the
/// surface's tiles, not the overlay's. A picture that missed it would
/// freeze the canvas for the whole drag — the same failure the tiled
/// buffer shipped and had to be reverted for, one input away.
///
/// ★Found by walking the painter's own body asking "what else can change",
/// which is the discipline those reverts bought
/// ([[cache-what-can-say-where-it-changed]]). This test is that walk, kept.
/// ↩️It was the canvas's display buffer kept under the float, until the
/// canvas showed the frame's one picture (one-picture-per-frame ②-5a).
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);
  const viewSize = Size(4, 4);
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

  BitmapSurface solid(RgbaColor color) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: 4,
    tiles: {
      TileCoord(x: 0, y: 0): writeRgbaColorToBitmapTile(
        tile: BitmapTile.blank(size: 4),
        x: 0,
        y: 0,
        color: color,
      ),
    },
  );

  BitmapSurfacePainter painterOf(BitmapSurface surface) =>
      BitmapSurfacePainter(surface: surface, showTransparentBackground: false);

  bool isRed(Shot shot, int x, int y) =>
      shot.rgba[(y * shot.width + x) * 4] > 200 &&
      shot.rgba[(y * shot.width + x) * 4 + 2] < 60;

  /// The canvas standing on the frame [nodes] stack — the cel [key] keeps
  /// blue at the corner — once its picture is made, and how to pump it
  /// again with the rows [LiveRows] holds.
  Future<Future<void> Function(LiveRows live)> standOn(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
    LiveRows live,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {key: solid(blue)});
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
    Future<void> pump(LiveRows live) => tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: const Color(0xFF00FF00),
        view: standingOn(
          run,
          picture: picture,
          nodes: nodes,
          viewport: CanvasViewport(),
          live: live,
        ),
      ),
    );
    await pump(live);
    final shown = run.pictures.keyOfStack(nodes, picture);
    expect(
      await settleAsync(tester, () => store.bytesOf(shown) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    expect(
      isRed(await shotOf(tester, screen), 0, 0),
      isFalse,
      reason: '⛔premise: the picture is the blue cel',
    );
    return pump;
  }

  /// The drag: [float] moves and NOTHING else does. No build — a float
  /// step reaches the canvas through the repaint Listenable, which is
  /// exactly the moment a kept picture can swallow it.
  Future<void> expectTheDragShows(
    WidgetTester tester,
    SelectionFloatOverlay float,
  ) async {
    float.value = SelectionFloatPaint(
      surface: painterOf(solid(red)),
      surfaceOffset: CanvasPoint(x: 0, y: 0),
    );
    await tester.pump();
    expect(
      isRed(await shotOf(tester, screen), 0, 0),
      isTrue,
      reason: 'the float came up and the canvas did not show it — the kept '
          'picture is drawn under the selection',
    );

    float.value = SelectionFloatPaint(
      surface: painterOf(solid(red)),
      surfaceOffset: CanvasPoint(x: 2, y: 2),
    );
    await tester.pump();
    final after = await shotOf(tester, screen);
    expect(
      isRed(after, 2, 2) && !isRed(after, 0, 0),
      isTrue,
      reason: 'the float moved and the canvas did not — a kept picture is '
          'showing where the selection used to be',
    );
  }

  testWidgets('moving a float repaints — no picture is kept under it', (
    tester,
  ) async {
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    await standOn(tester, nodes, (
      activeSurfacePainter: painterOf(solid(blue)),
      floatOverlay: float,
      liftedRows: const {},
    ));

    await expectTheDragShows(tester, float);
  });

  // I-37: a folder's lift floats on each of its rows, the live one or not.
  testWidgets('moving a lifted row\'s float repaints — no picture is kept '
      'under it', (tester) async {
    final lifted = [
      const CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: key, opacity: 1),
      ),
    ];
    final pump = await standOn(tester, lifted, (
      activeSurfacePainter: null,
      floatOverlay: null,
      liftedRows: const {},
    ));
    // The lift is taken up — a build, as a box opening is.
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    await pump((
      activeSurfacePainter: null,
      floatOverlay: null,
      liftedRows: {key: (surface: solid(blue), float: float)},
    ));

    await expectTheDragShows(tester, float);
  });

  // The third thing no token sees: a live row drawn from state its painter
  // does not publish. ↩️`static_bake_render_parity_test`'s swappable
  // surface (2026-09-15), which a bake replayed for the rest of the stroke.
  testWidgets('a live row drawn from what it does not publish repaints — no '
      'picture is kept under it', (tester) async {
    final surface = _InkOutOfSight(canvasSize);
    addTearDown(surface.ink.dispose);
    await standOn(tester, nodes, (
      activeSurfacePainter: surface,
      floatOverlay: null,
      liftedRows: const {},
    ));

    // A step: the live row draws something else and publishes nothing.
    surface.ink.value = const Color(0xFFFF0000);
    await tester.pump();
    expect(
      isRed(await shotOf(tester, screen), 0, 0),
      isTrue,
      reason: 'the live row drew red and the canvas still shows the picture '
          'taken before — the stroke froze where the picture was taken',
    );
  });
}

/// A live row's painter drawing [ink], which it does not publish: blue, as
/// the cel it is drawn over is stored, until a step changes it.
class _InkOutOfSight extends BitmapSurfacePainter {
  _InkOutOfSight(CanvasSize canvasSize)
    : super(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 4,
          tiles: const {},
        ),
        showTransparentBackground: false,
      );

  final ink = ValueNotifier(const Color(0xFF0000FF));

  /// 🚨Nothing that inspects a surface painter can tell when, let alone
  /// where, this one changed — the honest answer, not a concession.
  @override
  bool get drawsOnlyFromPublishedState => false;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    ink.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    ink.removeListener(listener);
  }

  @override
  void paintContentInto(
    Canvas canvas, {
    Paint? layerPaint,
    double scale = 1,
    RowFloat? float,
  }) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = ink.value,
    );
  }
}
