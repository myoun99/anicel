import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/services/viewport_transform_matrix.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/tile_pyramid.dart';
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import '../../helpers/temp_dir.dart';

/// 🚨A RUN DRAWS THE PICTURE THE CANVAS DRAWS STANDING STILL
/// (playback-picture-is-not-the-canvas-picture, 유저 10-13: 「재생하면
/// 미묘하게 화면 움직이는데 … 배율따라서 끝에 흰 선 보이는데」 — a canvas
/// filled black, a light line along its right and bottom edges).
///
/// Standing still, the active row is drawn from its tiles' level blocks
/// ([TilePyramid]) on the stack's own paper; a run draws every row as its
/// cel's image at the display's level ([LayerFrameImageCache]) — a cut's
/// run on the canvas, the film's on the track stack, either of them through
/// the camera. Pressing Play must change nothing on the screen, and a cel
/// filled to the canvas's edge, on a canvas that is no whole number of
/// tiles and halves to an odd size, is where the roads part if they part
/// anywhere.
void main() {
  const tileSize = 16;
  // 60 × 38: no whole number of tiles, and odd on the way down — 30 × 19,
  // 15 × 10 grown past the odd edge, 8 × 5.
  const canvasSize = CanvasSize(width: 60, height: 38);
  // Room past the canvas on both sides it can end on, so its edge is seen —
  // and whole device pixels at every ratio below, so the box's own edge
  // cuts no pixel.
  const viewSize = Size(80, 48);
  const fill = [0x10, 0x20, 0x30, 0xFF];
  // Past the canvas every road shows this one colour — the editing
  // canvas's pasteboard, the camera's apron and letterbox, the film's
  // floor — so a pixel that differs is the picture's own.
  const past = PlaybackFramePainter.letterboxColor;

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('filled'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: key.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: key.layerId,
        name: 'Filled',
        frames: [Frame(id: key.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(key.frameId, length: 1)},
      ),
    ],
  );
  final layout = buildStoryboardTimelineLayout(
    Project(
      id: key.projectId,
      name: 'Project',
      cameraSize: canvasSize,
      tracks: [
        Track(id: key.trackId, name: 'Track', cuts: [cut]),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );
  // The camera at rest: its frame is the canvas, centred on it.
  final atRest = CameraPose(
    center: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
  );
  final rows = [
    const CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: key, opacity: 1),
    ),
  ];

  final screen = GlobalKey();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-a-run-draws');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// The tile at ([tx], [ty]) of a cel filled to the canvas's edge and not a
  /// pixel past it, as the fill leaves one.
  BitmapTile tileAt(int tx, int ty) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        if (tx * tileSize + x >= canvasSize.width ||
            ty * tileSize + y >= canvasSize.height) {
          continue;
        }
        pixels.setRange(
          (y * tileSize + x) * 4,
          (y * tileSize + x) * 4 + 4,
          fill,
        );
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  final tilesAcross = (canvasSize.width + tileSize - 1) ~/ tileSize;
  final tilesDown = (canvasSize.height + tileSize - 1) ~/ tileSize;

  /// A store holding [key]'s cel as a FILE-BACKED entry — the image cache
  /// refuses a cel without a drawing state at its first gate.
  BrushFrameStore storeWithTheCel() {
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(
        key,
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {
            for (var ty = 0; ty < tilesDown; ty += 1)
              for (var tx = 0; tx < tilesAcross; tx += 1)
                TileCoord(x: tx, y: ty): tileAt(tx, ty),
          },
        ),
      ),
    );
    final file = File('${tempDir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    return BrushFrameStore()
      ..restoreFromFile({
        key: AnicelCelFileRef(
          filePath: file.path,
          dataOffset: 0,
          length: blob.bytes.length,
          canvasSize: canvasSize,
          tileSize: tileSize,
        ),
      });
  }

  BitmapSurface surfaceOf(BrushFrameStore store) =>
      BrushFrameDisplayCacheService(
        frameStore: store,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface;

  Future<void> pump(WidgetTester tester, Widget picture) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: screen,
            child: ClipRect(
              child: Container(
                width: viewSize.width,
                height: viewSize.height,
                color: past,
                child: picture,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The editing canvas's stack, as the canvas area mounts it: inside the
  /// camera's shot, which cuts nothing without a [shot].
  Widget canvas(
    LayerFrameImageCache images, {
    required CanvasViewport view,
    required bool bake,
    BitmapSurfacePainter? live,
    CameraShotAt? shot,
  }) => CameraShot(
    view: view,
    shot: shot,
    canvasSize: canvasSize,
    pasteboardColor: past,
    pasteboardNone: false,
    child: CanvasLayerStackView(
      // Each road a stack of its own: nothing one drew is handed to the
      // other.
      key: ValueKey<(bool, bool)>((live != null, shot != null)),
      nodes: live != null
          ? [
              const CompositeLeaf<CanvasStackRow>(
                CanvasActiveLayerRow(opacity: 1, frameKey: key),
              ),
            ]
          : rows,
      imageCache: images,
      canvasSize: canvasSize,
      viewport: shot?.frameView ?? view,
      activeSurfacePainter: live,
      debugDisableBake: !bake,
      // White paper under the ink, as every cut has.
      paintPaper: true,
    ),
  );

  /// The film's track stack at the cut's one frame.
  Widget film(
    LayerFrameImageCache images, {
    required CanvasViewport view,
    required bool throughTheCamera,
  }) => CanvasTrackStackView(
    key: ValueKey<bool>(throughTheCamera),
    globalFrame: const AlwaysStoppedAnimation<int?>(0),
    positionsOf: (frame) => resolveTrackStackContributions(
      layout: layout,
      spansOf: (_) => const [],
      globalFrameIndex: frame,
    ),
    stackOf: (_, _) => rows,
    imageCache: images,
    cameraFrameSize: canvasSize,
    cameraViewEnabled: throughTheCamera,
    cameraPoseOf: (_, _) => atRest,
    viewport: view,
    backdropArgb: past.toARGB32(),
    pasteboardArgb: past.toARGB32(),
  );

  /// What the last pump put on the screen, in device pixels.
  Future<Shot> onScreen(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ratio = tester.view.devicePixelRatio;
    final shot = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      return (rgba: data!.buffer.asUint8List(), width: width, height: height);
    });
    return shot!;
  }

  Future<void> landEverything(WidgetTester tester) async {
    for (var i = 0; i < 8; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  /// The RGBA of device pixel ([x], [y]).
  List<int> pixelAt(Shot shot, int x, int y) => shot.rgba.sublist(
    (y * shot.width + x) * 4,
    (y * shot.width + x) * 4 + 4,
  );

  /// The device pixels where the two pictures differ, as `(x, y): a → b`.
  List<String> differences(Shot a, Shot b) => [
    for (var y = 0; y < a.height; y += 1)
      for (var x = 0; x < a.width; x += 1)
        if (!listEquals(pixelAt(a, x, y), pixelAt(b, x, y)))
          '($x, $y): ${pixelAt(a, x, y)} → ${pixelAt(b, x, y)}',
  ];

  /// The canvas standing still at [zoom], with the cel as the active row,
  /// and [road] after it — the cel's image made at the display's level as
  /// a run makes it — each on a stack of its own.
  Future<({Shot still, Shot running})> stillThen(
    WidgetTester tester, {
    required double zoom,
    required String lineage,
    required Widget Function(LayerFrameImageCache images, CanvasViewport view)
    road,
    bool bake = true,
  }) async {
    final store = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    addTearDown(() => TilePyramid.instance.drop(lineage));
    final view = CanvasViewport(zoom: zoom);

    await pump(
      tester,
      canvas(
        images,
        view: view,
        bake: bake,
        live: BitmapSurfacePainter(
          surface: surfaceOf(store),
          showTransparentBackground: false,
          lineage: lineage,
        ),
      ),
    );
    await landEverything(tester);
    final still = await onScreen(tester);

    await tester.runAsync(
      () => images.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: rowQualityThrough(view, tester.view.devicePixelRatio),
        sourceEffects: const [],
      ),
    );
    await pump(tester, road(images, view));
    await landEverything(tester);
    final running = await onScreen(tester);
    expect(
      pixelAt(still, 0, 0),
      fill,
      reason: 'LIVENESS: the cel is on the screen standing still',
    );
    expect(pixelAt(running, 0, 0), fill, reason: 'LIVENESS: and in the run');
    return (still: still, running: running);
  }

  /// The camera at rest seen through [view]: what a run through it draws.
  CameraShotAt shotAtRest(CanvasViewport view) => (
    pose: atRest,
    frameSize: canvasSize,
    frameView: viewportAfter(
      view,
      cameraProjectionMatrix(atRest, canvasSize),
    ),
  );

  const ratios = [1.0, 1.25, 1.5];
  const zooms = [1.0, 0.5, 0.3, 0.25, 0.2, 0.125];
  String at(double zoom, double ratio) =>
      '${(zoom * ratio * 100).round()}% (ratio $ratio)';

  group('a cut\'s run on the canvas', () {
    for (final ratio in ratios) {
      for (final bake in const [false, true]) {
        for (final zoom in zooms) {
          final where = '${at(zoom, ratio)}${bake ? ', baked' : ''}';
          testWidgets('🚨at $where draws, pixel for pixel, the picture the '
              'canvas draws standing still', (tester) async {
            tester.view.devicePixelRatio = ratio;
            addTearDown(tester.view.resetDevicePixelRatio);

            final (:still, :running) = await stillThen(
              tester,
              zoom: zoom,
              bake: bake,
              lineage: 'on-the-canvas-$where',
              road: (images, view) =>
                  canvas(images, view: view, bake: bake),
            );

            expect(
              differences(still, running),
              isEmpty,
              reason: 'pressing Play must change nothing on the screen',
            );
          });
        }
      }
    }
  });

  group('the film', () {
    for (final ratio in ratios) {
      for (final zoom in zooms) {
        final where = at(zoom, ratio);
        testWidgets('🚨at $where draws, pixel for pixel, the picture the '
            'canvas draws standing still', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);

          final (:still, :running) = await stillThen(
            tester,
            zoom: zoom,
            lineage: 'the-film-$where',
            road: (images, view) =>
                film(images, view: view, throughTheCamera: false),
          );

          expect(
            differences(still, running),
            isEmpty,
            reason: 'pressing Play must change nothing on the screen',
          );
        });
      }
    }
  });

  group('through the camera at rest', () {
    for (final ratio in ratios) {
      for (final zoom in zooms) {
        final where = at(zoom, ratio);
        testWidgets('🚨at $where a cut\'s run draws, pixel for pixel, the '
            'picture the canvas draws standing still', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);

          final (:still, :running) = await stillThen(
            tester,
            zoom: zoom,
            lineage: 'a-cut-through-the-camera-$where',
            road: (images, view) => canvas(
              images,
              view: view,
              bake: true,
              shot: shotAtRest(view),
            ),
          );

          expect(
            differences(still, running),
            isEmpty,
            reason: 'a camera framing the canvas cuts nothing of it',
          );
        });

        testWidgets('🚨at $where the film draws, pixel for pixel, the '
            'picture the canvas draws standing still', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);

          final (:still, :running) = await stillThen(
            tester,
            zoom: zoom,
            lineage: 'the-film-through-the-camera-$where',
            road: (images, view) =>
                film(images, view: view, throughTheCamera: true),
          );

          expect(
            differences(still, running),
            isEmpty,
            reason: 'a camera framing the canvas cuts nothing of it',
          );
        });
      }
    }
  });
}

/// A screen shot in device pixels.
typedef Shot = ({Uint8List rgba, int width, int height});
