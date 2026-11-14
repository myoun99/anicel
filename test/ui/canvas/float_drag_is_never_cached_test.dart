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
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart'
    show FramePictureKey;
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨(v) — a floating selection moves under the hand, and the picture a
/// canvas keeps must never be shown without it.
///
/// The float is drawn in the live row's slot and changes without touching
/// the layer tree, the surface's tiles or the overlay's. A picture that
/// missed it would freeze the canvas for the whole drag — the same failure
/// the tiled buffer shipped and had to be reverted for, one input away.
///
/// ★Found by walking the painter's own body asking "what else can change",
/// which is the discipline those reverts bought
/// ([[cache-what-can-say-where-it-changed]]). This test is that walk, kept.
/// ↩️It was the canvas's display buffer kept under the float, until the
/// canvas showed the frame's one picture (one-picture-per-frame ②-5a).
///
/// The float is told by its value, beside where it draws
/// (`a_float_in_hand_is_told_where_it_moved_test`), so each step is
/// patched into the picture — and the picture patched is the frame drawn
/// as it stands. ↩️Until it was told, the frame was drawn as it stands,
/// whole, at every step (a-float-in-hand-draws-the-frame-as-it-stands,
/// 2026-11-12).
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  const viewSize = Size(defaultCelTileSize * 1.0, defaultCelTileSize * 1.0);
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
    tileSize: defaultCelTileSize,
    tiles: {
      TileCoord(x: 0, y: 0): writeRgbaColorToBitmapTile(
        tile: BitmapTile.blank(size: defaultCelTileSize),
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
  /// blue at the corner — once its picture is made, how to pump it again
  /// with the rows [LiveRows] holds, and what its picture is written by.
  Future<
    ({
      Future<void> Function(LiveRows live) pump,
      StoreTellingItsWrites store,
      FramePictureKey shown,
    })
  >
  standOn(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
    LiveRows live, {
    Key? view,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {key: solid(blue)});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = StoreTellingItsWrites();
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
          key: view,
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
    return (pump: pump, store: store, shown: shown);
  }

  bool drawnAsItStands(WidgetTester tester) =>
      // ignore: avoid_dynamic_calls
      (tester.state(theFramesPicture()) as dynamic).drawnAsItStands as bool;

  /// The step just taken went into the picture shown — not the frame drawn
  /// as it stands.
  void expectItWentIn(
    WidgetTester tester,
    StoreTellingItsWrites store,
    FramePictureKey shown, {
    required String what,
  }) {
    expect(
      store.landedAt(keptByTheCanvas(tester, shown)),
      isTrue,
      reason: 'LIVENESS: $what is patched into the picture',
    );
    expect(drawnAsItStands(tester), isFalse, reason: '$what is no whole frame');
    store.patched.clear();
  }

  /// The drag: [float] moves and NOTHING else does. No build — a float
  /// step reaches the canvas through the repaint Listenable, which is
  /// exactly the moment a kept picture can swallow it — and the frame a
  /// view of its own draws as it stands, the float where the drag left it,
  /// is what the canvas shows.
  Future<void> expectTheDragShows(
    WidgetTester tester,
    ({
      Future<void> Function(LiveRows live) pump,
      StoreTellingItsWrites store,
      FramePictureKey shown,
    })
    standing,
    SelectionFloatOverlay float, {
    required List<CompositeNode<CanvasStackRow>> nodes,
    required LiveRows live,
  }) async {
    final (pump: _, :store, :shown) = standing;
    float.value = SelectionFloatPaint(
      surface: painterOf(solid(red)),
      surfaceOffset: CanvasPoint(x: 0, y: 0),
    );
    await tester.pump();
    expectItWentIn(tester, store, shown, what: 'the float as it comes up');
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
    expectItWentIn(tester, store, shown, what: 'the float as it moves');
    final after = await shotOf(tester, screen);
    expect(
      isRed(after, 2, 2) && !isRed(after, 0, 0),
      isTrue,
      reason: 'the float moved and the canvas did not — a kept picture is '
          'showing where the selection used to be',
    );

    // A view of its own, the float in hand where the drag left it: the
    // frame as it stands.
    await standOn(tester, nodes, live, view: const ValueKey('as it stands'));
    expect(drawnAsItStands(tester), isTrue, reason: '⛔premise');
    expect(
      differences(await shotOf(tester, screen), after),
      isEmpty,
      reason: 'the patched picture is the frame as it stands',
    );
  }

  testWidgets('moving a float repaints — patched in, never kept under it', (
    tester,
  ) async {
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    final LiveRows live = (
      activeSurfacePainter: painterOf(solid(blue)),
      floatOverlay: float,
      liftedRows: const {},
    );
    final standing = await standOn(tester, nodes, live);

    await expectTheDragShows(tester, standing, float, nodes: nodes, live: live);
  });

  // I-37: a folder's lift floats on each of its rows, the live one or not.
  testWidgets('moving a lifted row\'s float repaints — patched in, never '
      'kept under it', (tester) async {
    final lifted = [
      const CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: key, opacity: 1),
      ),
    ];
    final standing = await standOn(tester, lifted, (
      activeSurfacePainter: null,
      floatOverlay: null,
      liftedRows: const {},
    ));
    // The lift is taken up — a build, as a box opening is.
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    final LiveRows live = (
      activeSurfacePainter: null,
      floatOverlay: null,
      liftedRows: {key: (surface: solid(blue), float: float)},
    );
    await standing.pump(live);
    expectItWentIn(tester, standing.store, standing.shown, what: 'the lift');

    await expectTheDragShows(
      tester,
      standing,
      float,
      nodes: lifted,
      live: live,
    );
  });
}
