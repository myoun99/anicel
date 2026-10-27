import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/placement_reading.dart';
import '../../helpers/stack_as_the_plan_hands_it.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// A folder's buffer reaches what its rows draw, on screen — past the view by
/// a blur's spread, past a row's tiles where its placement lays it, and to
/// nothing where a row is scaled to nothing — on the display buffer and the
/// direct walk alike.
///
/// ↩️These stood in the pin that a cel stored as its ink put the same bytes
/// on screen as its whole image (유저 2026-09-23 · 09-24), until no screen
/// drew a row's image (one-picture-per-frame ②-5b-1): a frame as it stands
/// is drawn from its cels' tiles. That law is the camera's now
/// (`a_row_drawn_from_its_ink_is_the_same_bytes_test`), the one route that
/// still composes a row as its ink.
///
/// ⚠️CAPTURED THROUGH `toImageSync`, and that is not a convenience. The walk
/// lays a whole image back as a deferred image, which the test runner (Skia)
/// makes RGBA while a snapshot is its native N32 (`picture.cc`
/// `CreateDeferredImage` · `snapshot_controller_skia.cc`), and onto an N32
/// target Skia blends an N32 image at 1:1 through a legacy blitter that
/// rounds `srcOver` one way and everything else through its pipeline another
/// — ±1 that exists only in this runner. On Impeller both are the same
/// texture. An RGBA capture sends every image through the one pipeline.
void main() {
  const tile = 16;
  const canvasSize = CanvasSize(width: 150, height: 101);
  const view = Size(176, 128);
  final screenKey = GlobalKey();

  setUpAll(ColourKeyShader.load);
  setUpAll(LayerBlendShader.load);

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  BrushDab dab(double x, double y, int color, int sequence) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: 9,
    opacity: 1,
    flow: 1,
    hardness: 0.4,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  /// Where each cel's ink is. Tiles are 16: [interior] is a block in the
  /// middle, [leftTop] shares the canvas's left and top edges, [rightBottom]
  /// reaches tiles past the canvas's odd edges, [pasteboard] has ink off the
  /// canvas on both sides, [sparse] spans the canvas corner to corner,
  /// [inner] keeps to the canvas's middle.
  const cels = <String, (int, List<(double, double)>)>{
    'interior': (0xFF2040C0, [(60, 44), (72, 52), (66, 60)]),
    'leftTop': (0xFFE04020, [(1, 1), (4, 30), (18, 3)]),
    'rightBottom': (0xFF20A060, [(147, 98), (131, 100), (149, 84)]),
    'pasteboard': (0xFFA020C0, [(-9, 20), (-3, 26), (158, 60), (166, 66)]),
    'sparse': (0xFFF0C020, [(8, 9), (141, 93)]),
    'inner': (0xFF308090, [(90, 30), (100, 70)]),
  };

  BrushFrameStore storeWithCels() {
    final store = BrushFrameStore();
    for (final MapEntry(key: id, value: (color, points)) in cels.entries) {
      BrushFrameEditingCoordinator(
        initialFrameKey: key(id),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: tile,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          for (var i = 0; i < points.length; i += 1)
            dab(points[i].$1, points[i].$2, color, i),
        ],
      );
    }
    return store;
  }

  CompositeNode<CanvasStackRow> row(
    String id, {
    double opacity = 1,
    TransformPose? pose,
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(
      frameKey: key(id),
      opacity: opacity,
      placement: pose == null ? null : placedBy(pose, canvasSize),
    ),
  );

  final center = CanvasPoint(x: 75, y: 50.5);

  // The blurred folder reaches both ends of the canvas ([sparse]), so at
  // every view but the whole one its buffer runs past the composite by the
  // blur's spread — the scene that stopped the paint pass's own assertion
  // (board `a-blurred-folder-outgrows-the-composite`).
  final foldersWithABlendAndABlur = <CompositeNode<CanvasStackRow>>[
    CompositeGroup<CanvasStackRow>(
      children: [
        row('sparse'),
        row('interior'),
        row('inner', opacity: 0.6),
      ],
      opacity: 0.7,
      blendMode: LayerBlendMode.multiply,
      effects: [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [2, 0]),
      ],
    ),
    CompositeGroup<CanvasStackRow>(
      children: [row('rightBottom'), row('leftTop')],
      opacity: 1,
      blendMode: LayerBlendMode.screen,
    ),
    row('pasteboard'),
  ];

  /// The screen for [nodes] as the plan hands them over, drawn as the frame
  /// stands.
  Future<Uint8List> screen(
    WidgetTester tester, {
    required List<CompositeNode<CanvasStackRow>> nodes,
    required CanvasViewport viewport,
    required bool walk,
  }) async {
    final images = LayerFrameImageCache(frameStore: storeWithCels());
    addTearDown(images.dispose);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: screenKey,
              child: ClipRect(
                child: SizedBox(
                  width: view.width,
                  height: view.height,
                  child: TheFrameAsItStands(
                    nodes: stackAsThePlanHandsIt(nodes),
                    imageCache: images,
                    canvasSize: canvasSize,
                    viewport: viewport,
                    paintPaper: true,
                    paperBackground: const ProjectBackground.color(0xFFF4EEE0),
                    debugDisableSingleBuffer: walk,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final render =
        screenKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = render.toImageSync();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  // board `a-blurred-folder-outgrows-the-composite`: the folder's buffer
  // runs past the view by the blur's spread ON PURPOSE — so the ink just
  // off screen still reaches the blur at the edge. Seen with the view's
  // right edge through the ink at (141, 93), every pixel of the canvas on
  // screen is the pixel the whole view shows there.
  //
  // ↩️RED ON IMPELLER VULKAN (`--enable-impeller`, Android's default), and
  // not for the blur. The folder blends in multiply, and Vulkan mixes an
  // advanced blend twice along the diagonal of the quad it draws
  // (flutter#179547 — every advanced-blend draw does it, from an image, a
  // saveLayer or a shader alike). This folder's raster follows the view, so
  // the diagonal moves with the pan: two pixels, up to 3/255 at this one.
  // Skia and the Windows app (Impeller GLES) keep every byte — measured
  // 2026-09-30, board `a-blurred-folder-cut-by-the-view-moves-on-vulkan`.
  // 🔬Green on all three since that card sent every advanced blend to our
  // shader over its backdrop (10-22): no engine blend draws the diagonal.
  for (final walk in [false, true]) {
    final route = walk ? 'the direct walk' : 'the display buffer';
    testWidgets('a blurred folder cut by the view\'s edge blurs as it does '
        'seen whole — $route', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      // At 100% a canvas pixel is a screen pixel, offset by the pan.
      const whole = (x: 18, y: 12);
      const cut = (x: 33, y: -30);
      final seenWhole = await screen(
        tester,
        nodes: foldersWithABlendAndABlur,
        viewport: CanvasViewport(zoom: 1, panX: 18, panY: 12),
        walk: walk,
      );
      final seenCut = await screen(
        tester,
        nodes: foldersWithABlendAndABlur,
        viewport: CanvasViewport(zoom: 1, panX: 33, panY: -30),
        walk: walk,
      );
      final width = view.width.toInt();
      var compared = 0;
      final moved = <String>[];
      for (var y = 0; y < canvasSize.height; y += 1) {
        for (var x = 0; x < canvasSize.width; x += 1) {
          final sx = x + cut.x;
          final sy = y + cut.y;
          if (sx < 0 || sx >= width || sy < 0 || sy >= view.height) {
            continue;
          }
          final a = (sy * width + sx) * 4;
          final b = ((y + whole.y) * width + x + whole.x) * 4;
          compared += 1;
          for (var c = 0; c < 4; c += 1) {
            if (seenCut[a + c] != seenWhole[b + c] && moved.length < 6) {
              moved.add('($x, $y) c$c ${seenCut[a + c]} '
                  'vs ${seenWhole[b + c]}');
            }
          }
        }
      }
      expect(compared, greaterThan(5000), reason: 'the cut view shows canvas');
      expect(moved, isEmpty, reason: 'the edge blurs what lies past it');
    });
  }

  // A folder's buffer is bounded by what its rows draw, and a placed row
  // draws where its placement lays it — which can be past every tile the row
  // holds. [rightBottom]'s tiles end at x 160; moved 14 right, its last dab
  // shows about (163, 84).
  for (final walk in [false, true]) {
    final route = walk ? 'the direct walk' : 'the display buffer';
    testWidgets('a folder shows a row placed PAST the row\'s own tiles — '
        '$route', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      // Unpanned at 100%: a canvas pixel is the screen pixel of its number.
      Future<Uint8List> seen(List<CompositeNode<CanvasStackRow>> nodes) =>
          screen(tester, nodes: nodes, viewport: CanvasViewport(), walk: walk);

      final bare = await seen(const []);
      final folder = await seen([
        CompositeGroup<CanvasStackRow>(
          children: [
            row(
              'rightBottom',
              pose: TransformPose(
                center: CanvasPoint(x: center.x + 14, y: center.y),
              ),
            ),
          ],
          opacity: 0.7,
          blendMode: LayerBlendMode.normal,
        ),
      ]);
      bool inked(int x, int y) {
        final at = (y * view.width.toInt() + x) * 4;
        for (var channel = 0; channel < 4; channel += 1) {
          if (folder[at + channel] != bare[at + channel]) {
            return true;
          }
        }
        return false;
      }

      expect(inked(145, 100), isTrue, reason: 'fixture: the row is drawn');
      expect(
        inked(164, 84),
        isTrue,
        reason: 'cut at x 160, where the row\'s tiles end before the move',
      );
    });
  }

  // A scale of zero on an axis — the frame a flip passes through (F-256-Q1)
  // — is the row shown as nothing: alone, and as all a folder holds, where
  // the folder's buffer has no extent to be made over.
  for (final walk in [false, true]) {
    final route = walk ? 'the direct walk' : 'the display buffer';
    testWidgets('a row scaled to NOTHING on an axis draws nothing, alone or '
        'in a folder — $route', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<Uint8List> seen(List<CompositeNode<CanvasStackRow>> nodes) =>
          screen(tester, nodes: nodes, viewport: CanvasViewport(), walk: walk);

      final collapsed = row(
        'interior',
        pose: TransformPose(center: center, scaleX: 0),
      );
      final bare = await seen(const []);
      expect(await seen([row('interior')]), isNot(bare), reason: 'fixture');
      expect(await seen([collapsed]), bare);
      expect(
        await seen([
          CompositeGroup<CanvasStackRow>(
            children: [collapsed],
            opacity: 0.7,
            blendMode: LayerBlendMode.multiply,
          ),
        ]),
        bare,
      );
    });
  }
}
