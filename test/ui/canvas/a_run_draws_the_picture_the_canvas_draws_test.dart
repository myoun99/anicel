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
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/services/viewport_transform_matrix.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart';
import 'package:anicel/src/ui/canvas/tile_pyramid.dart';
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import '../../helpers/cels_kept_in_a_file.dart';

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
///
/// 🚨Seen through no camera, that holds PAST the canvas too
/// (conte-playback-hides-the-pasteboard, 유저 10-13 「둘 다 보인다(편집
/// 캔버스처럼)」): the film shows the pasteboard and what is drawn on it as
/// the canvas shows them standing still.
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
  // Where the cel holds no ink: the paper — or its absence — shows there.
  // On every level's grid down to an eighth, so no level pixel mixes ink
  // and hole: a mixed one rounds apart between a cel's whole image and its
  // tiles' pyramid at an eighth (1/255 — the halving's two draws,
  // level-halving-rounds-apart), which is not a road's difference.
  const hole = Rect.fromLTRB(16, 8, 32, 24);
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

  /// The tile at ([tx], [ty]) of a cel filled [reach] pixels past the
  /// canvas's right and bottom edges and not a pixel further — to the edge
  /// itself at 0, as the fill leaves one — but for the [hole].
  BitmapTile tileAt(int tx, int ty, {required int reach}) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final at = Offset(tx * tileSize + x + 0.5, ty * tileSize + y + 0.5);
        if (at.dx >= canvasSize.width + reach ||
            at.dy >= canvasSize.height + reach ||
            hole.contains(at)) {
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

  /// A store holding [key]'s cel, filled [reach] pixels past the canvas, as
  /// a FILE-BACKED entry — the image cache refuses a cel without a drawing
  /// state at its first gate.
  BrushFrameStore storeWithTheCel({int reach = 0}) {
    final tilesAcross = (canvasSize.width + reach + tileSize - 1) ~/ tileSize;
    final tilesDown = (canvasSize.height + reach + tileSize - 1) ~/ tileSize;
    final store = BrushFrameStore();
    keepInAFile(store, {
      key: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          for (var ty = 0; ty < tilesDown; ty += 1)
            for (var tx = 0; tx < tilesAcross; tx += 1)
              TileCoord(x: tx, y: ty): tileAt(tx, ty, reach: reach),
        },
      ),
    });
    return store;
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
  /// camera's shot, which cuts nothing without a [shot] — on the stage's
  /// [planes], where the canvas panel lays them under all of it.
  Widget canvas(
    LayerFrameImageCache images, {
    required CanvasViewport view,
    required bool bake,
    BitmapSurfacePainter? live,
    CameraShotAt? shot,
    StagePlanesPainter? planes,
    Color pasteboard = past,
    ProjectBackground paper = ProjectBackground.defaultBackground,
  }) => CustomPaint(
    painter: planes,
    child: CameraShot(
      view: view,
      shot: shot,
      canvasSize: canvasSize,
      background: paper,
      pasteboardColor: pasteboard,
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
        // The paper under the ink, as every cut has — white unless it is
        // absent.
        paintPaper: true,
        paperBackground: paper,
      ),
    ),
  );

  /// The film's track stack at the cut's one frame, on a [past] floor.
  Widget film(
    LayerFrameImageCache images, {
    required CanvasViewport view,
    required bool throughTheCamera,
    Color pasteboard = past,
    bool pasteboardNone = false,
    ProjectBackground paper = ProjectBackground.defaultBackground,
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
    background: paper,
    backdropArgb: past.toARGB32(),
    pasteboardArgb: pasteboard.toARGB32(),
    pasteboardNone: pasteboardNone,
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

  /// [color] as [pixelAt] reads it.
  List<int> rgbaOf(Color color) => [
    for (final channel in [color.r, color.g, color.b, color.a])
      (channel * 255).round(),
  ];

  /// The device pixels where the two pictures differ, as `(x, y): a → b`.
  List<String> differences(Shot a, Shot b) => [
    for (var y = 0; y < a.height; y += 1)
      for (var x = 0; x < a.width; x += 1)
        if (!listEquals(pixelAt(a, x, y), pixelAt(b, x, y)))
          '($x, $y): ${pixelAt(a, x, y)} → ${pixelAt(b, x, y)}',
  ];

  /// What [picture] puts on the screen once everything it asked for landed.
  Future<Shot> shown(WidgetTester tester, Widget picture) async {
    await pump(tester, picture);
    await landEverything(tester);
    return onScreen(tester);
  }

  /// The cel's image made at the display's level through [view], as a run
  /// makes it.
  Future<void> madeForTheRun(
    WidgetTester tester,
    LayerFrameImageCache images,
    CanvasViewport view,
  ) => tester.runAsync(
    () => images.prepare(
      key: key,
      canvasSize: canvasSize,
      quality: rowQualityThrough(view, tester.view.devicePixelRatio),
      sourceEffects: const [],
    ),
  );

  /// The canvas standing still at [zoom], with the cel — filled [reach]
  /// pixels past the canvas — as the active row, on the stage's [planes],
  /// and [road] after it — the cel's image made at the display's level as a
  /// run makes it — each on a stack of its own.
  Future<({Shot still, Shot running})> stillThen(
    WidgetTester tester, {
    required double zoom,
    required String lineage,
    required Widget Function(LayerFrameImageCache images, CanvasViewport view)
    road,
    bool bake = true,
    int reach = 0,
    StagePlanesPainter Function(CanvasViewport view)? planes,
    ProjectBackground paper = ProjectBackground.defaultBackground,
  }) async {
    final store = storeWithTheCel(reach: reach);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    addTearDown(() => TilePyramid.instance.drop(lineage));
    final view = CanvasViewport(zoom: zoom);

    final still = await shown(
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
        planes: planes?.call(view),
        paper: paper,
      ),
    );

    await madeForTheRun(tester, images, view);
    final running = await shown(tester, road(images, view));
    expect(
      pixelAt(still, 0, 0),
      fill,
      reason: 'LIVENESS: the cel is on the screen standing still',
    );
    expect(pixelAt(running, 0, 0), fill, reason: 'LIVENESS: and in the run');
    return (still: still, running: running);
  }

  /// The camera at rest seen through [view]: what a cut's run through it
  /// draws.
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

  group('past the canvas, seen through no camera', () {
    // The ink runs onto the pasteboard past the canvas's right and bottom
    // edges, the pasteboard is a colour of its own, and the backdrop lies
    // past it.
    const reach = 12;
    const pasteboard = Color(0xFF5A4630);
    const stages = {
      'the stage\'s planes': (pasteboardNone: false, paperNone: false),
      'an absent pasteboard': (pasteboardNone: true, paperNone: false),
      'an absent paper': (pasteboardNone: false, paperNone: true),
    };

    for (final MapEntry(key: stage, value: (:pasteboardNone, :paperNone))
        in stages.entries) {
      final paper = ProjectBackground.color(
        ProjectBackground.defaultPaperArgb,
        none: paperNone,
      );
      for (final ratio in ratios) {
        for (final zoom in zooms) {
          final where = at(zoom, ratio);
          testWidgets('🚨with $stage, at $where the film shows, pixel for '
              'pixel, what the canvas shows past its edge standing still', (
            tester,
          ) async {
            tester.view.devicePixelRatio = ratio;
            addTearDown(tester.view.resetDevicePixelRatio);

            final (:still, :running) = await stillThen(
              tester,
              zoom: zoom,
              reach: reach,
              lineage: 'past-the-canvas-$stage-$where',
              // The stage's planes as the canvas panel lays them.
              planes: (view) => StagePlanesPainter(
                backdrop: (color: past, none: false),
                pasteboard: (color: pasteboard, none: pasteboardNone),
                paperNone: paperNone,
                canvasSize: canvasSize,
                viewport: view,
              ),
              paper: paper,
              road: (images, view) => film(
                images,
                view: view,
                throughTheCamera: false,
                pasteboard: pasteboard,
                pasteboardNone: pasteboardNone,
                paper: paper,
              ),
            );
            if (zoom == 1) {
              // At 1:1 the ink past the canvas is on the screen, and the
              // pasteboard past the ink.
              final y = (5 * ratio).floor();
              expect(
                pixelAt(still, (66 * ratio).floor(), y),
                fill,
                reason: 'LIVENESS: the ink past the canvas shows standing '
                    'still',
              );
              expect(
                pixelAt(still, (76 * ratio).floor(), y),
                isNot(rgbaOf(past)),
                reason: 'LIVENESS: and the pasteboard past the ink',
              );
              if (paperNone) {
                // Both roads lay the paper's absence with one painter:
                // only this tells that it is laid at all.
                expect(
                  pixelAt(still, (20 * ratio).floor(), (12 * ratio).floor()),
                  isNot(rgbaOf(pasteboard)),
                  reason: 'LIVENESS: in the hole the checkerboard lies in '
                      'the absent paper\'s place, not the pasteboard',
                );
              }
            }

            expect(
              differences(still, running),
              isEmpty,
              reason: 'a cut played whole shows what the canvas shows, past '
                  'its edge too',
            );
          });
        }
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

  /// Through the camera an absent paper is the checkerboard in its place on
  /// a cut's run as on the film (conte-playback-hides-the-pasteboard).
  /// ↩️A cut's run laid nothing there, and the camera's apron showed in the
  /// paper's place.
  group('an absent paper through the camera at rest', () {
    // The apron a colour of its own, so the paper's place shows which of
    // the two lies in it.
    const apron = Color(0xFF5A4630);
    const paper = ProjectBackground.color(
      ProjectBackground.defaultPaperArgb,
      none: true,
    );
    for (final ratio in ratios) {
      for (final zoom in zooms) {
        final where = at(zoom, ratio);
        testWidgets('🚨at $where a cut\'s run lays, pixel for pixel, what the '
            'film lays in the paper\'s place', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);
          final images = LayerFrameImageCache(frameStore: storeWithTheCel());
          addTearDown(images.dispose);
          final view = CanvasViewport(zoom: zoom);
          await madeForTheRun(tester, images, view);

          final theFilm = await shown(
            tester,
            film(
              images,
              view: view,
              throughTheCamera: true,
              pasteboard: apron,
              paper: paper,
            ),
          );
          final aCutsRun = await shown(
            tester,
            canvas(
              images,
              view: view,
              bake: true,
              shot: shotAtRest(view),
              pasteboard: apron,
              paper: paper,
            ),
          );
          if (zoom == 1) {
            expect(
              pixelAt(theFilm, (20 * ratio).floor(), (12 * ratio).floor()),
              isNot(rgbaOf(apron)),
              reason: 'LIVENESS: in the hole the film lays the '
                  'checkerboard, not the apron',
            );
          }

          expect(
            differences(theFilm, aCutsRun),
            isEmpty,
            reason: 'one paper, absent, through one camera',
          );
        });
      }
    }
  });
}

/// A screen shot in device pixels.
typedef Shot = ({Uint8List rgba, int width, int height});
