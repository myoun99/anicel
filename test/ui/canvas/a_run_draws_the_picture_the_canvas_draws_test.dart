import 'dart:async';
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
import 'package:anicel/src/models/pasteboard_bounds.dart';
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
import 'package:anicel/src/ui/playback/camera_shot.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨A RUN DRAWS THE PICTURE THE CANVAS DRAWS STANDING STILL
/// (playback-picture-is-not-the-canvas-picture, 유저 10-13: 「재생하면
/// 미묘하게 화면 움직이는데 … 배율따라서 끝에 흰 선 보이는데」 — a canvas
/// filled black, a light line along its right and bottom edges).
///
/// Standing still, the canvas shows the frame's one picture with the row a
/// pen is on live in it; a run shows that frame's picture as the warmer
/// made it — a cut's run on the canvas, the film's on the track stack,
/// either of them through the camera ([FramePictureView],
/// one-picture-per-frame ②-3). Each road here keeps pictures of its own, so
/// what is compared is two makings and two showings, not one image twice.
/// Pressing Play must change nothing on the screen, and a cel filled to
/// the canvas's edge, on a canvas that is no whole number of tiles and
/// halves to an odd size, is where the roads part if they part anywhere.
///
/// ↩️Standing still the active row was drawn from its tiles' level blocks
/// (`TilePyramid`) and a run drew every row as its cel's image at the
/// display's level (`LayerFrameImageCache`), each on a `CanvasLayerStackView`
/// — two roads this pinned to meet; and a road per baked static composite.
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
  // Off every halving's grid, odd on each side: a reduced pixel mixes ink
  // and hole, where two roads that reduce apart would part.
  // ↩️It lay on every level's grid down to an eighth, so no level pixel
  // mixed ink and hole: a mixed one rounded apart between a cel's whole
  // image and its tiles' pyramid at an eighth (1/255 — the halving's two
  // draws, level-halving-rounds-apart) while the canvas standing still drew
  // its live row from level tiles — until every road drew the frame's one
  // picture by its own chain and no halving was left
  // (one-picture-per-frame ②-5b-3).
  const hole = Rect.fromLTRB(17, 9, 31, 23);
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

  /// The frame's picture as the canvas and the film ask for it — the paper
  /// under the ink, as every cut has, white unless it is absent.
  final frame = (cut: cut, frameIndex: 0, paintPaper: true);

  /// The editing canvas, as the canvas area mounts it: the frame's one
  /// picture — the cel [live] in it standing still, made by the view itself;
  /// a run's, the warmer's ([warm]) — inside the camera's shot, which cuts
  /// nothing without a [shot], on the stage's [planes], where the canvas
  /// panel lays them under all of it.
  Widget canvas(
    Road road, {
    required CanvasViewport view,
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
      pasteboardReach: PasteboardReach.whole,
      child: FramePictureView(
        key: ValueKey<(bool, bool)>((live != null, shot != null)),
        run: road,
        picture: frame,
        nodes: live != null
            ? [
                const CompositeLeaf<CanvasStackRow>(
                  CanvasActiveLayerRow(opacity: 1, frameKey: key),
                ),
              ]
            : rows,
        viewport: shot?.frameView ?? view,
        live: live == null
            ? null
            : (
                activeSurfacePainter: live,
                floatOverlay: null,
                liftedRows: const {},
              ),
        laysWhatItMisses: live != null,
        wholeFrames: live == null,
      ),
    ),
  );

  /// The film's track stack at the cut's one frame, on a [past] floor.
  Widget film(
    Road road, {
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
    pictures: road,
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

  /// The pictures of the frame a road keeps — of its own, on [paper]:
  /// nothing one road made is handed to another.
  Road roadOf(
    LayerFrameImageCache images, {
    ProjectBackground paper = ProjectBackground.defaultBackground,
  }) {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    return (
      landings: landings,
      pictures: FramePictures(
        store: store,
        layerImages: images,
        stackOf: (_) => rows,
        pageOf: (picture) => (
          canvasSize: canvasSize,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: picture.paintPaper,
          paperBackground: paper,
        ),
      ),
    );
  }

  /// The warmer making the frame's picture ahead of a run on [road], and
  /// telling the run it landed.
  void warm(Road road) => unawaited(
    road.pictures
        .make(frame, shouldAbort: () => false)
        .then((_) => road.landings.value += 1),
  );

  /// What [picture] puts on the screen once [road] holds the frame's
  /// picture and the screen took it.
  Future<Shot> shown(WidgetTester tester, Widget picture, Road road) async {
    await pump(tester, picture);
    final made = road.pictures.keyOfStack(rows, frame);
    expect(
      await settleAsync(tester, () => road.pictures.store.bytesOf(made) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return onScreen(tester);
  }

  /// The canvas standing still at [zoom], with the cel — filled [reach]
  /// pixels past the canvas — as the active row, on the stage's [planes],
  /// and [road] after it, each with pictures of its own ([roadOf]).
  Future<({Shot still, Shot running})> stillThen(
    WidgetTester tester, {
    required double zoom,
    required String lineage,
    required Widget Function(Road road, CanvasViewport view) road,
    int reach = 0,
    StagePlanesPainter Function(CanvasViewport view)? planes,
    ProjectBackground paper = ProjectBackground.defaultBackground,
  }) async {
    final store = storeWithTheCel(reach: reach);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final view = CanvasViewport(zoom: zoom);

    final standing = roadOf(images, paper: paper);
    final still = await shown(
      tester,
      canvas(
        standing,
        view: view,
        live: BitmapSurfacePainter(
          surface: surfaceOf(store),
          showTransparentBackground: false,
          lineage: lineage,
        ),
        planes: planes?.call(view),
        paper: paper,
      ),
      standing,
    );

    final playing = roadOf(images, paper: paper);
    final running = await shown(tester, road(playing, view), playing);
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
      for (final zoom in zooms) {
        final where = at(zoom, ratio);
        testWidgets('🚨at $where draws, pixel for pixel, the picture the '
            'canvas draws standing still', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);

          final (:still, :running) = await stillThen(
            tester,
            zoom: zoom,
            lineage: 'on-the-canvas-$where',
            road: (road, view) {
              warm(road);
              return canvas(road, view: view);
            },
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
            road: (road, view) =>
                film(road, view: view, throughTheCamera: false),
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
                pasteboardReach: PasteboardReach.whole,
                paperNone: paperNone,
                canvasSize: canvasSize,
                viewport: view,
                devicePixelRatio: ratio,
              ),
              paper: paper,
              road: (road, view) => film(
                road,
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

  /// The device pixels a run seen through the camera at rest on [view]
  /// shows the canvas in — inside the cut both roads make
  /// ([pictureOutlineOnScreen], [shotClipOnScreen]).
  Rect cutOnScreen(CanvasViewport view, double ratio) {
    final corners = shotClipOnScreen(
      pictureOutlineOnScreen(view, shotAtRest(view), canvasSize, ratio)!,
      ratio,
    ).corners;
    final cut = Rect.fromPoints(corners[0], corners[2]);
    return Rect.fromLTRB(
      cut.left * ratio,
      cut.top * ratio,
      cut.right * ratio,
      cut.bottom * ratio,
    );
  }

  /// A camera at rest cuts nothing OF THE CANVAS, and past the canvas shows
  /// its apron (「페이스트보드는 포함 안 시킴」) — where the canvas standing
  /// still shows its pasteboard. The two are one colour here, so ⛔what is
  /// compared stops at the cut: zoomed out, the canvas's one picture is read
  /// through its own mip chain (D7-2-Q2 — 「축소해서 볼때는 정확도는
  /// 기대안해서 심각하게 맞출필요는없어」, within 2 of the levels it replaced),
  /// and the page's edge reaches a level's texel past the page onto the
  /// pasteboard — a trace the camera covers as it covers any ink there.
  /// ↩️Compared whole until the canvas standing still drew its picture
  /// (2026-10-25): at 31% (ratio 1.25) that trace lay one row under the
  /// page, 1 in 255.
  group('through the camera at rest', () {
    for (final ratio in ratios) {
      for (final zoom in zooms) {
        final where = at(zoom, ratio);

        void expectCutsNothing(Shot still, Shot running) {
          final cut = cutOnScreen(CanvasViewport(zoom: zoom), ratio);
          final inside = <String>[];
          final apron = <String>[];
          for (var y = 0; y < still.height; y += 1) {
            for (var x = 0; x < still.width; x += 1) {
              if (cut.contains(Offset(x + 0.5, y + 0.5))) {
                if (!listEquals(pixelAt(still, x, y), pixelAt(running, x, y))) {
                  inside.add(
                    '($x, $y): ${pixelAt(still, x, y)} → '
                    '${pixelAt(running, x, y)}',
                  );
                }
              } else if (!listEquals(pixelAt(running, x, y), rgbaOf(past))) {
                apron.add('($x, $y): ${pixelAt(running, x, y)}');
              }
            }
          }
          expect(
            inside,
            isEmpty,
            reason: 'a camera framing the canvas cuts nothing of it',
          );
          expect(apron, isEmpty, reason: 'and past it shows its apron');
        }

        testWidgets('🚨at $where a cut\'s run draws, pixel for pixel, the '
            'picture the canvas draws standing still', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);

          final (:still, :running) = await stillThen(
            tester,
            zoom: zoom,
            lineage: 'a-cut-through-the-camera-$where',
            road: (road, view) {
              warm(road);
              return canvas(road, view: view, shot: shotAtRest(view));
            },
          );

          expectCutsNothing(still, running);
        });

        testWidgets('🚨at $where the film draws, pixel for pixel, the '
            'picture the canvas draws standing still', (tester) async {
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.resetDevicePixelRatio);

          final (:still, :running) = await stillThen(
            tester,
            zoom: zoom,
            lineage: 'the-film-through-the-camera-$where',
            road: (road, view) =>
                film(road, view: view, throughTheCamera: true),
          );

          expectCutsNothing(still, running);
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

          final filmed = roadOf(images, paper: paper);
          final theFilm = await shown(
            tester,
            film(
              filmed,
              view: view,
              throughTheCamera: true,
              pasteboard: apron,
              paper: paper,
            ),
            filmed,
          );
          final played = roadOf(images, paper: paper);
          warm(played);
          final aCutsRun = await shown(
            tester,
            canvas(
              played,
              view: view,
              shot: shotAtRest(view),
              pasteboard: apron,
              paper: paper,
            ),
            played,
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

/// The pictures of the frame a road keeps, and the signal that one landed
/// ([StackRun]).
typedef Road = ({ValueNotifier<int> landings, FramePictures pictures});
