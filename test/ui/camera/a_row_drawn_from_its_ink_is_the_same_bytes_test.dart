import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/raster_picture.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

import '../../helpers/placement_reading.dart';

/// 🚨★★★A ROW A RENDER DRAWS FROM ITS INK PUTS THE SAME BYTES IN THE FRAME
/// AS THE WHOLE ROW DID (유저 2026-09-23: 「1/4해상도같은 결과바뀌는건 절대로
/// 허용안하고 … 보이는 결과 특히」).
///
/// The playback cache's law (`a_cropped_cel_draws_the_same_bytes_test`),
/// asked of the camera's render — the export's frames, a video run's held
/// rows. Every scene is rendered twice: once with every row composed whole,
/// as the render did before (`debugComposesRowsWhole`), once with the rows
/// that draw exactly from their ink composed as their ink alone wherever
/// the camera moves canvas pixels onto output pixels whole. The scenes are
/// the ways ink could lie — inside the canvas, on its left and top edge, by
/// the odd right and bottom edges, on the pasteboard, scattered — through
/// the blends that keep the ink alone exact and those that do not, posed,
/// blurred, in a folder; through a camera square over the canvas, over a
/// part of it, and turned.
///
/// ⚠️The draw counters say both arms of the lay-down ran — a pin whose
/// scenes never drew a crop, or never laid one back, would be green about
/// nothing.
void main() {
  const tile = 16;
  const canvasSize = CanvasSize(width: 150, height: 101);

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

  /// Where each cel's ink is, as the cache's pin lays it: [interior] is a
  /// block in the middle, [leftTop] shares the canvas's left and top edges,
  /// [rightBottom] reaches tiles past the canvas's odd edges, [pasteboard]
  /// has ink off the canvas on both sides, [sparse] spans it corner to
  /// corner.
  const cels = <String, (int, List<(double, double)>)>{
    'interior': (0xFF2040C0, [(60, 44), (72, 52), (66, 60)]),
    'leftTop': (0xFFE04020, [(1, 1), (4, 30), (18, 3)]),
    'rightBottom': (0xFF20A060, [(147, 98), (131, 100), (149, 84)]),
    'pasteboard': (0xFFA020C0, [(-9, 20), (-3, 26), (158, 60), (166, 66)]),
    'sparse': (0xFFF0C020, [(8, 9), (141, 93)]),
  };

  late Map<String, BitmapSurface> surfaces;

  setUpAll(() {
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
    surfaces = {
      for (final id in cels.keys)
        id: store.currentSurfaceWithoutReplay(key(id), canvasSize: canvasSize)!,
    };
  });

  tearDown(() => debugComposesRowsWhole = false);

  /// How many of [ids] hold less ink than content — the rows a crop
  /// changes.
  int croppedOf(Iterable<String> ids) => [
    for (final id in ids)
      if (surfaceInkWorldRect(surfaces[id]!) !=
          surfaceContentWorldRect(surfaces[id]!))
        id,
  ].length;

  CompositeNode<CutFrameCompositeLayer> row(
    String id, {
    double opacity = 1,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    TransformPose? pose,
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeLeaf(
    CutFrameCompositeLayer(
      surface: surfaces[id]!,
      opacity: opacity,
      blendMode: blendMode,
      placement: pose == null ? null : placedBy(pose, canvasSize),
      effects: effects,
    ),
  );

  ResolvedLayerEffect effect(EffectKind kind, List<double> values) =>
      ResolvedLayerEffect(kind: kind, values: values);

  final center = CanvasPoint(x: 75, y: 50.5);

  final scenes = <String, _Scene>{
    'ink rows through normal and add': () => [
      row('interior'),
      row('leftTop', opacity: 0.8),
      row('rightBottom', opacity: 0.7, blendMode: LayerBlendMode.add),
      row('pasteboard'),
      row('sparse', opacity: 0.5),
    ],
    'ink and whole rows over each other': () => [
      row('pasteboard'),
      row('interior', blendMode: LayerBlendMode.multiply),
      row('leftTop', opacity: 0.8),
      row('rightBottom', opacity: 0.7, blendMode: LayerBlendMode.screen),
      row('sparse', opacity: 0.5, blendMode: LayerBlendMode.add),
    ],
    'posed rows': () => [
      row('interior', pose: TransformPose(center: CanvasPoint(x: 78, y: 48.5))),
      row(
        'rightBottom',
        pose: TransformPose(center: center, rotationDegrees: 15),
      ),
      row('sparse'),
    ],
    'a blur and a colour effect': () => [
      row('interior', effects: [effect(EffectKind.blur, [3, 3])]),
      row('leftTop', effects: [effect(EffectKind.brightnessContrast, [20, 0])]),
      row('sparse'),
    ],
    'ink rows in a folder': () => [
      row('pasteboard'),
      CompositeGroup(
        children: [
          row('interior'),
          row('leftTop', opacity: 0.8),
          row('rightBottom', blendMode: LayerBlendMode.add),
        ],
        opacity: 0.9,
        blendMode: LayerBlendMode.normal,
      ),
    ],
  };

  const service = CameraFrameRenderService();

  /// The cameras a render looks through: square over the whole canvas (a
  /// video frame's composites), square over a part of it, and turned.
  final cameras = <String, CameraView>{
    'square over the canvas': cameraViewOver(canvasSize.canvasRect),
    'square over a part': cameraViewOver(const Rect.fromLTWH(10, 7, 100, 60)),
    'turned': (
      pose: CameraPose(center: center, rotationDegrees: 9),
      frameSize: const CanvasSize(width: 100, height: 60),
    ),
  };

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<Uint8List> render(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
    CameraView view, {
    RowPictures? rows,
  }) async => bytesOf(
    await service.renderThroughCamera(
      nodes: nodes,
      pose: view.pose,
      cameraFrameSize: view.frameSize,
      rows: rows,
    ),
  );

  for (final MapEntry(key: scene, value: nodes) in scenes.entries) {
    for (final MapEntry(key: camera, value: view) in cameras.entries) {
      testWidgets('🎯$scene, through a camera $camera', (tester) async {
        await tester.runAsync(() async {
          debugComposesRowsWhole = true;
          final whole = await render(nodes(), view);
          debugComposesRowsWhole = false;
          final ink = await render(nodes(), view);

          expect(ink, whole);
        });
      });
    }
  }

  testWidgets('LIVENESS: a camera square over the canvas draws the rows '
      'that keep the ink exact from their ink — composed at its size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final rastered = <int>[];
      debugOnWaitedSnapshot = (width, height) => rastered.add(width * height);
      addTearDown(() => debugOnWaitedSnapshot = null);
      final laidDown = debugCropsLaidDown;
      final cropped = croppedOf(cels.keys);
      expect(cropped, greaterThanOrEqualTo(3), reason: 'LIVENESS: crops');

      await render(
        scenes['ink rows through normal and add']!(),
        cameras['square over the canvas']!,
      );

      expect(
        rastered.take(5),
        [
          for (final id in cels.keys)
            surfaceInkWorldRect(surfaces[id]!).width *
                surfaceInkWorldRect(surfaces[id]!).height,
        ],
        reason: 'each row rastered over its ink, not over its content',
      );
      expect(
        debugCropsLaidDown - laidDown,
        cropped,
        reason: 'a crop is laid down as it is wherever it is one',
      );
    });
  });

  testWidgets('🎯a row its ink alone would draw otherwise — an advanced '
      'blend, a pose, a blur — is composed whole, and so is every row '
      'through a camera that resamples', (tester) async {
    await tester.runAsync(() async {
      final rastered = <int>[];
      debugOnWaitedSnapshot = (width, height) => rastered.add(width * height);
      addTearDown(() => debugOnWaitedSnapshot = null);
      double areaOf(Rect rect) => rect.width * rect.height;
      double ink(String id) => areaOf(surfaceInkWorldRect(surfaces[id]!));
      double whole(String id) => areaOf(surfaceContentWorldRect(surfaces[id]!));
      const square = 'square over the canvas';

      for (final (scene, camera, areas) in [
        (
          'ink and whole rows over each other',
          square,
          [
            ink('pasteboard'),
            whole('interior'),
            ink('leftTop'),
            whole('rightBottom'),
            ink('sparse'),
          ],
        ),
        ('posed rows', square, [whole('interior'), whole('rightBottom')]),
        (
          'a blur and a colour effect',
          square,
          [whole('interior'), ink('leftTop')],
        ),
        (
          'ink rows through normal and add',
          'turned',
          [for (final id in cels.keys) whole(id)],
        ),
      ]) {
        rastered.clear();
        await render(scenes[scene]!(), cameras[camera]!);

        expect(rastered.take(areas.length), areas, reason: '$scene, $camera');
      }
    });
  });

  testWidgets('🎯rows kept for renders that do not all lay them down texel '
      'for texel are composed whole — even for one that does', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final kept = _Kept(laidTexelForTexel: false);
      addTearDown(kept.dispose);
      final rastered = <int>[];
      debugOnWaitedSnapshot = (width, height) => rastered.add(width * height);
      addTearDown(() => debugOnWaitedSnapshot = null);
      final laidDown = debugCropsLaidDown;

      await render(
        scenes['ink rows through normal and add']!(),
        cameras['square over the canvas']!,
        rows: kept,
      );

      expect(kept.composed, 5, reason: 'LIVENESS: every row asked');
      expect(rastered.take(5), [
        for (final id in cels.keys)
          surfaceContentWorldRect(surfaces[id]!).width *
              surfaceContentWorldRect(surfaces[id]!).height,
      ]);
      expect(debugCropsLaidDown, laidDown);
    });
  });

  testWidgets('🚨a row kept from a render that drew its ink is laid back '
      'whole for a render through a turned camera — the same bytes as the '
      'whole row (a keeper that vouched wrongly costs time, never a pixel)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final kept = _Kept(laidTexelForTexel: true);
      addTearDown(kept.dispose);
      final nodes = scenes['ink rows through normal and add']!();
      final laidBack = debugWholesLaidBack;

      await render(nodes, cameras['square over the canvas']!, rows: kept);
      final turned = await render(nodes, cameras['turned']!, rows: kept);
      debugComposesRowsWhole = true;
      final whole = await render(nodes, cameras['turned']!);

      expect(kept.composed, 5, reason: 'LIVENESS: kept from the first');
      expect(
        debugWholesLaidBack - laidBack,
        croppedOf(cels.keys),
        reason: 'each crop laid back',
      );
      expect(turned, whole);
    });
  });

  // A canvas a few pixels wider than a folder's raster may be: the folder
  // over it is cut down to its cap, and its rows are drawn into it
  // resampled, never texel for texel.
  testWidgets('🎯a row composed as its ink is laid back whole in a folder '
      'cut down to its cap — the same bytes as the whole row', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const wide = CanvasSize(width: maxSubtreeRasterSide + 8, height: 16);
      final pixels = Uint8List(16 * 16 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = 200;
        pixels[i + 3] = 255;
      }
      final surface = BitmapSurface(
        canvasSize: wide,
        tileSize: 16,
        tiles: {TileCoord(x: 1, y: 0): BitmapTile(size: 16, pixels: pixels)},
      );
      final nodes = [
        CompositeGroup<CutFrameCompositeLayer>(
          children: [
            CompositeLeaf(CutFrameCompositeLayer(surface: surface, opacity: 1)),
          ],
          opacity: 0.9,
          blendMode: LayerBlendMode.normal,
        ),
      ];
      final view = cameraViewOver(wide.canvasRect);
      Future<Uint8List> render() async {
        final image = await const CameraFrameRenderService()
            .renderThroughCamera(
              nodes: nodes,
              pose: view.pose,
              cameraFrameSize: view.frameSize,
            );
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }

      final laidBack = debugWholesLaidBack;
      final ink = await render();
      expect(
        debugLastSubtreeRaster!.scale,
        lessThan(1),
        reason: 'LIVENESS: the cap cut the folder down',
      );
      expect(debugWholesLaidBack - laidBack, 1, reason: 'the crop laid back');
      debugComposesRowsWhole = true;
      addTearDown(() => debugComposesRowsWhole = false);
      final whole = await render();

      expect(ink, whole);
    });
  });
}

/// The rows' pictures kept from one render to the next, by surface.
final class _Kept implements RowPictures {
  _Kept({required this.laidTexelForTexel});

  @override
  final bool laidTexelForTexel;

  final _pictures = <BitmapSurface, PositionedSurfaceImage>{};
  int composed = 0;

  @override
  Future<PositionedSurfaceImage> of(
    BitmapSurface surface,
    Future<PositionedSurfaceImage> Function() compose,
  ) async {
    if (_pictures[surface] case final kept?) {
      return kept;
    }
    composed += 1;
    return _pictures[surface] = await compose();
  }

  void dispose() {
    for (final picture in _pictures.values) {
      picture.image.dispose();
    }
  }
}

/// The rows of a frame, made anew for each render.
typedef _Scene = List<CompositeNode<CutFrameCompositeLayer>> Function();
