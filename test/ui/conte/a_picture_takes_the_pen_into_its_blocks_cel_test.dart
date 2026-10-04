import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/conte_book.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart'
    show exportFrameGround;
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';

/// 🚨A CONTE PICTURE TAKES THE PEN INTO ITS BLOCK'S CEL (유저 2026-09-25,
/// conte-drawing-target: 「그림 칸 안의 부분은 그 블록의 콘티 레이어
/// 그림으로」 · 「진짜 하나의 용지처럼. 데이터는 나누더라도」 · 「보이는
/// 거 = 결과」).
///
/// A stroke started on a cell's picture lands in the cel the picture shows
/// — through the camera and the layer's placement, the maps the picture is
/// printed by — all of it, past the picture's edge into the canvas beyond
/// the camera; one started on the sheet's own ink stays there (유저
/// 2026-09-30, H49: 「선 시작한곳에따라 칸 나누자」). While the brush is on, the picture is the cut's
/// live composite (유저 답 conte-picture-display-Q1 「실시간 합성
/// (정확)」), so the stroke shows in it while it is drawn.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const cutId = CutId('39');
  const layerId = LayerId('sb');
  const frameId = FrameId('sb-0');

  Cut cut() => Cut(
    id: cutId,
    name: '39',
    duration: 10,
    canvasSize: canvas,
    layers: [
      Layer(
        id: layerId,
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [Frame(id: frameId, duration: 1, strokes: const [])],
        timeline: const {
          0: TimelineExposure.drawing(frameId, length: 10),
        },
      ),
    ],
  );

  Project project() => Project(
    id: const ProjectId('conte-project'),
    name: 'Conte',
    createdAt: DateTime.utc(2026, 9, 26),
    tracks: [
      Track(id: const TrackId('track'), name: 'Video', cuts: [cut()]),
    ],
  );

  BrushFrameKey celKeyOf(Cut cut, LayerId layer, FrameId frame) =>
      BrushFrameKey(
        projectId: const ProjectId('conte-project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layer,
        frameId: frame,
      );

  bool inkAt(BitmapSurface? surface, Offset pixel) =>
      surface != null &&
      (surfacePixelRgba(surface, pixel.dx.floor(), pixel.dy.floor()) ?? 0) !=
          0;

  Future<void> stroke(
    WidgetTester tester,
    Offset origin,
    List<Offset> path,
  ) async {
    final gesture = await tester.startGesture(origin + path.first, pointer: 7);
    await tester.pump();
    for (final point in path.skip(1)) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  group('the sheet\'s ink layer', () {
    late ContePageLayout page;
    late ConteInkController ink;
    late ContePictureInkController cels;
    late BrushFrameStore store;
    late HistoryManager history;
    late ContePicture picture;

    /// The name the band of a block not yet written on is written under.
    String bandOf(ContePlacedCell cell) => 'band-${cell.source.startFrame}';

    Future<Offset> pump(WidgetTester tester, CameraPose pose) async {
      final drawn = cut();
      page = layoutConteSheet(
        buildConteSheetSource(project()),
        metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
      ).first;
      final metrics = page.metrics;
      ink = ConteInkController()..syncGeometry(metrics);
      addTearDown(ink.dispose);
      store = BrushFrameStore();
      cels = ContePictureInkController(cels: store);
      addTearDown(cels.dispose);
      history = HistoryManager();
      final strokeActive = ValueNotifier<bool>(false);
      addTearDown(strokeActive.dispose);
      final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brush.dispose);
      // The picture's live stroke, let go after the views drawing into it
      // (tear-downs run last-added first).
      final stroke = ActiveStrokeOverlayModel();
      addTearDown(stroke.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      picture = contePictures(page, (
        cutOf: (id) => id == cutId ? drawn : null,
        celKeyOf: celKeyOf,
        cameraPoseOf: (cut, frame) => pose,
        cameraFrameSize: canvas,
        // The cut has its conte row.
        conteCelOf: (cut) => null,
        refusalOf: (_) => null,
      ), (id) => stroke).single;

      await tester.binding.setSurfaceSize(
        Size(metrics.pageWidth + 40, metrics.pageHeight + 40),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: metrics.pageWidth,
                height: metrics.pageHeight,
                child: ConteInkLayer(
                  controller: ink,
                  pages: [(page: page, at: Offset.zero)],
                  brushToolState: brush,
                  historyManager: history,
                  viewport: CanvasViewport(),
                  strokeActive: strokeActive,
                  pictures: cels,
                  pictureWindows: [picture.window],
                  unwrittenInkIdOf: bandOf,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.byType(ConteInkLayer));
    }

    testWidgets('the pen lands through the camera: the picture\'s middle is '
        'the pose\'s centre on the cel, and a step right on the paper is a '
        'step DOWN the canvas under a camera turned 90° — halved by its '
        'zoom 2', (tester) async {
      final pose = CameraPose(
        center: CanvasPoint(x: 320, y: 180),
        zoom: 2,
        rotationDegrees: 90,
      );
      final origin = await pump(tester, pose);
      final shown = picture.shown;
      const step = 24.0;
      await stroke(tester, origin, [
        shown.center,
        shown.center + const Offset(step / 2, 0),
        shown.center + const Offset(step, 0),
      ]);

      // Paper units per camera pixel, and the zoom on top of it.
      final along = step / (shown.width / canvas.width) / pose.zoom;
      final cel = store.bakedSurfaceOrNull(picture.window.key);
      expect(inkAt(cel, const Offset(320, 180)), isTrue);
      expect(
        inkAt(cel, Offset(320, 180 + along)),
        isTrue,
        reason:
            'a camera turned clockwise shows the world turned back: right '
            'on the paper is down the canvas',
      );
      expect(
        inkAt(cel, Offset(320 + along, 180)),
        isFalse,
        reason: 'unturned, the stroke would have gone right',
      );
      expect(
        inkAt(cel, Offset(320, 180 + 2 * along)),
        isFalse,
        reason: 'unzoomed, it would have gone twice as far',
      );
    });

    testWidgets('🗣️H49: a stroke from the picture out over its cell\'s band '
        'is the picture\'s — past the camera it goes on into the cut\'s '
        'canvas, and the cell\'s ink keeps none of it — ONE undo (유저 '
        '2026-09-30: 「밖으로 나가면 해당 캔버스의 카메라 밖 영역에 그리긴 '
        '하게」)', (tester) async {
      // Closed in on the canvas's middle, so the canvas runs on past the
      // camera's frame.
      final origin = await pump(
        tester,
        CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: 2),
      );
      final slot = picture.window.slot;
      final inside = slot.center;
      final outside = Offset(slot.right + 30, slot.center.dy);
      await stroke(tester, origin, [
        inside,
        Offset(slot.right - 10, inside.dy),
        Offset(slot.right + 10, inside.dy),
        outside,
      ]);

      final row = conteInkWindows(
        page,
        unwrittenInkIdOf: bandOf,
      ).singleWhere((window) => window.key == conteInkRowKey(cutId, 'band-0'));
      // The picture's middle is the pose's centre; past its edge, the
      // canvas the camera leaves out.
      const underInside = Offset(320, 180);
      final pastTheCamera = picture.window
          .surfaceShapeOf([
            outside,
            outside + const Offset(1, 0),
            outside + const Offset(0, 1),
          ])
          .points
          .first;
      expect(
        pastTheCamera.x,
        allOf(greaterThan(480), lessThan(canvas.width.toDouble())),
        reason: 'fixture: on the canvas, right of the camera\'s frame',
      );
      BitmapSurface? cel() => store.bakedSurfaceOrNull(picture.window.key);

      expect(inkAt(cel(), underInside), isTrue);
      expect(
        inkAt(cel(), Offset(pastTheCamera.x, pastTheCamera.y)),
        isTrue,
        reason: 'the canvas past the camera takes the rest of it',
      );
      expect(
        ink.hasInkFor(null, row.key),
        isFalse,
        reason: 'the band it crossed into takes none of it',
      );

      history.undo();
      expect(inkAt(cel(), underInside), isFalse);
      history.redo();
      expect(inkAt(cel(), underInside), isTrue);
    });

    // F-216: a band's stroke runs on under the picture's edge by
    // [sheetInkApron], so the line meets the picture wherever a screen's
    // pixels put that edge — and only by that much.
    testWidgets('a stroke from the cell\'s band into its picture keeps a ring '
        'of itself past the picture\'s edge, and nothing deeper', (
      tester,
    ) async {
      final origin = await pump(
        tester,
        CameraPose(center: CanvasPoint(x: 320, y: 180)),
      );
      final slot = picture.window.slot;
      final y = slot.center.dy;
      await stroke(tester, origin, [
        Offset(slot.right + 30, y),
        Offset(slot.right + 10, y),
        Offset(slot.right - 10, y),
        slot.center,
      ]);

      final row = conteInkWindows(
        page,
        unwrittenInkIdOf: bandOf,
      ).singleWhere((window) => window.key == conteInkRowKey(cutId, 'band-0'));
      final surface = ink.sessionStateFor(null, row.key).canvasState
          .currentSurface;
      bool keeps(double inside) => inkAt(
        surface,
        row.placement.pixelOf(Offset(slot.right - inside, y)),
      );
      expect(keeps(-2), isTrue, reason: 'fixture: the paper keeps its own');
      expect(keeps(sheetInkApron / 2), isTrue);
      expect(keeps(sheetInkApron + 1.5), isFalse);
    });

  });

  testWidgets('the panel composites the picture live: the stroke shows in it '
      'while it is drawn, from the pen\'s own overlay, and stays at the '
      'pen-up', (tester) async {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final cels = ContePictureInkController(
      cels: session.renderCaches.brushFrameStore,
    );
    addTearDown(cels.dispose);
    final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brush.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Rebuilt as the workspace rebuilds it: on the session and on the
          // pictures' cels (`workspace_tabs.dart`, F-80 ②).
          body: ListenableBuilder(
            listenable: Listenable.merge([session, ink, cels]),
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewport: seedFromRender(
                tester,
                onConteBody(session, CanvasViewport()),
              ),
              inkController: ink,
              pictures: cels,
              brushToolState: brush,
              brushAllowed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cell = layoutConteSheet(
      buildConteSheetSource(session.repository.requireProject()),
      metrics: ConteSheetMetrics(
        cameraAspect: session.camera.cameraFrameAspect,
      ),
    ).first.cells.single;
    final live = find.byKey(
      const ValueKey<String>('conte-picture-live-picture-39-0'),
    );
    expect(live, findsOneWidget);
    final pageTopLeft = conteBodyTopLeft(tester);
    final centre = pageTopLeft + cell.pictureRect.center;
    final at = centre - tester.getTopLeft(live);

    /// The live composite's own painter, rasterized: is there ink at [at]?
    Future<bool> showsInk() async {
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(of: live, matching: find.byType(CustomPaint)),
          )
          .map((paint) => paint.painter)
          .whereType<CustomPainter>()
          .first;
      final size = tester.getSize(live);
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(
          size.width.ceil(),
          size.height.ceil(),
        );
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      return _alphaAt(bytes, size.width.ceil(), at) > 0;
    }

    expect(await showsInk(), isFalse, reason: 'an empty cel');

    final gesture = await tester.startGesture(centre, pointer: 7);
    await tester.pump();
    await gesture.moveTo(centre + const Offset(6, 0));
    await tester.pump();
    await gesture.moveTo(centre + const Offset(12, 0));
    await tester.pump();

    expect(
      await showsInk(),
      isTrue,
      reason: 'the composite paints the pen\'s live stroke in the cel\'s place',
    );
    final stack = tester.widget<CanvasLayerStackView>(live);
    // This picture's window — the page's free row has the next cut's too.
    final pen = tester
        .widgetList<SheetInkLayer>(find.byType(SheetInkLayer))
        .single
        .windows
        .whereType<SheetPictureWindow>()
        .singleWhere((window) => window.id == 'picture-39-0');
    expect(
      identical(stack.activeSurfacePainter!.overlayModel, pen.overlay),
      isTrue,
      reason: 'one live stroke, drawn by the pen and painted by the picture',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(await showsInk(), isTrue, reason: 'the pen-up changes nothing');
    expect(
      session.cutById(cutId)!.layers,
      hasLength(1),
      reason: 'a picture of a cut with its conte row makes no other',
    );
    expect(
      ink.hasInkFor(
        null,
        conteInkRowKey(
          cutId,
          session.storyboardCursor.conteInkIdFor(cutId, 0),
        ),
      ),
      isFalse,
      reason: 'drawn on the picture only: the cell\'s ink got nothing',
    );
  });

  // 🚨The shown is the result: while the brush is on, the picture on screen
  // is what the page prints for it — the camera's frame on the print's
  // ground, the layers cropped at the canvas, the camera's work over it —
  // and nothing around it moves.
  group('on screen, while the brush is on', () {
    const boundary = ValueKey<String>('screen');
    const blue = Color(0xFF0000FF);
    late EditorSessionManager session;
    late ValueNotifier<bool> brushOn;

    /// Every height the panel asked the printed picture at, in order.
    final askedHeights = <double>[];

    /// The cut framed by its camera at [zoom] about the canvas's middle,
    /// held still over its one block — two keys at one place are no camera
    /// work — or panning on to [last]; its conte row posed by [rowPose], its
    /// block's handwriting named [inkId].
    Project framed({
      required double zoom,
      TransformPose? rowPose,
      CameraPose? last,
      String? inkId,
    }) {
      final pose = CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: zoom);
      final base = cut();
      final block = base.layers.single;
      final row = inkId == null
          ? block
          : block.copyWith(
              timeline: {
                0: TimelineExposure.drawing(
                  frameId,
                  length: 10,
                  memo: ExposureMemo(inkId: inkId),
                ),
              },
            );
      return Project(
        id: const ProjectId('conte-project'),
        name: 'Conte',
        createdAt: DateTime.utc(2026, 9, 26),
        cameraSize: canvas,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              base.copyWith(
                camera: CutCamera(keyframes: {0: pose, 9: last ?? pose}),
                layers: [
                  if (rowPose == null)
                    row
                  else
                    row.copyWith(
                      transformTrack: TransformTrack(keyframes: {0: rowPose}),
                    ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    /// The block's cel, inked blue on four of its 128px tiles: the two
    /// across its top-left (canvas x 0–256, y 0–128) and the two down its
    /// right at x 384–512 (y 128–360).
    BitmapSurface inked() {
      const size = defaultCelTileSize;
      final pixels = Uint8List(size * size * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      return BitmapSurface(
        canvasSize: canvas,
        tileSize: size,
        tiles: {
          for (final (x, y) in const [(0, 0), (1, 0), (3, 1), (3, 2)])
            TileCoord(x: x, y: y): BitmapTile(size: size, pixels: pixels),
        },
      );
    }

    /// Handwriting over the top of a band surface of [size]: a hairline in
    /// every seventh column and every fifth row, across its first three
    /// tile rows — a pattern a sub-pixel shift or a softer filter changes
    /// everywhere. A hairline is a POINT of the page wide: the surface is
    /// kept at the paper's pixels (F-294), [nib] of them to the point.
    BitmapSurface hatched(CanvasSize size) {
      const tile = defaultCelTileSize;
      final nib = const ConteSheetMetrics().paperScale.ceil();
      BitmapTile hatchedAt(int tileX, int tileY) {
        final pixels = Uint8List(tile * tile * 4);
        for (var y = 0; y < tile; y += 1) {
          for (var x = 0; x < tile; x += 1) {
            if (((tileX * tile + x) ~/ nib) % 7 == 0 ||
                ((tileY * tile + y) ~/ nib) % 5 == 0) {
              final i = (y * tile + x) * 4;
              pixels[i] = 0x10;
              pixels[i + 1] = 0x10;
              pixels[i + 2] = 0x10;
              pixels[i + 3] = 0xFF;
            }
          }
        }
        return BitmapTile(size: tile, pixels: pixels);
      }

      return BitmapSurface(
        canvasSize: size,
        tileSize: tile,
        tiles: {
          for (var y = 0; y < 3; y += 1)
            for (var x = 0; x * tile < size.width; x += 1)
              TileCoord(x: x, y: y): hatchedAt(x, y),
        },
      );
    }

    /// The block's cel black over the whole canvas — the cut filled black.
    BitmapSurface filledBlack() {
      const size = defaultCelTileSize;
      final pixels = Uint8List(size * size * 4);
      for (var i = 3; i < pixels.length; i += 4) {
        pixels[i] = 0xFF;
      }
      return BitmapSurface(
        canvasSize: canvas,
        tileSize: size,
        tiles: {
          for (var y = 0; y * size < canvas.height; y += 1)
            for (var x = 0; x * size < canvas.width; x += 1)
              TileCoord(x: x, y: y): BitmapTile(size: size, pixels: pixels),
        },
      );
    }

    /// The panel on [project], its brush off, with the block's cel [cel]
    /// (inked, unless told), the page's printed picture [printed] and the
    /// handwriting [band] makes for a band surface of its size, keyed
    /// `band`, seen through [view].
    Future<Rect> pumpPanel(
      WidgetTester tester,
      Project project, {
      ui.Image? printed,
      BitmapSurface? cel,
      CanvasViewport? view,
      BitmapSurface Function(CanvasSize size)? band,
    }) async {
      session = EditorSessionManager(initialProject: project);
      addTearDown(session.dispose);
      final rows = BrushFrameStore();
      final ink = ConteInkController(rowStore: rows);
      addTearDown(ink.dispose);
      if (band != null) {
        final metrics = ConteSheetMetrics(
          cameraAspect: session.camera.cameraFrameAspect,
        );
        rows.storeBakedSurface(
          conteInkRowKey(cutId, 'band'),
          band(
            CanvasSize(
              width: (metrics.bodyWidth * metrics.paperScale).ceil(),
              height: (metrics.bodyHeight * metrics.paperScale).ceil(),
            ),
          ),
        );
      }
      final cels = ContePictureInkController(
        cels: session.renderCaches.brushFrameStore,
      );
      addTearDown(cels.dispose);
      final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brush.dispose);
      brushOn = ValueNotifier<bool>(false);
      addTearDown(brushOn.dispose);
      final drawn = session.repository.requireProject().tracks.single.cuts
          .single;
      session.renderCaches.brushFrameStore.storeBakedSurface(
        session.brushFrameKeyForCut(drawn, layerId, frameId),
        cel ?? inked(),
      );
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ListenableBuilder(
                listenable: Listenable.merge([session, ink, cels, brushOn]),
                builder: (context, _) => ConteTabHost(
                  session: session,
                  thumbnails: printed == null
                      ? null
                      : (
                          resolve:
                              (
                                cut,
                                frame, {
                                required shownHeight,
                                region,
                              }) {
                                askedHeights.add(shownHeight);
                                return printed;
                              },
                          landed: const _NeverLands(),
                          pending: () => false,
                        ),
                  viewport: seedFromRender(
                    tester,
                    onConteBody(session, view ?? CanvasViewport()),
                  ),
                  inkController: ink,
                  pictures: cels,
                  brushToolState: brush,
                  brushAllowed: brushOn.value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = layoutConteSheet(
        buildConteSheetSource(project),
        metrics: ConteSheetMetrics(
          cameraAspect: session.camera.cameraFrameAspect,
        ),
      ).first;
      final pageTopLeft =
          conteBodyTopLeft(tester) -
          tester.getTopLeft(find.byKey(boundary));
      // On the screen: the view's zoom lays a paper unit that many logical
      // pixels wide.
      final zoom = (view ?? CanvasViewport()).zoom;
      final slot = contePictureSlot(page.cells.single, page.metrics);
      return Rect.fromLTWH(
        pageTopLeft.dx + zoom * slot.left,
        pageTopLeft.dy + zoom * slot.top,
        zoom * slot.width,
        zoom * slot.height,
      );
    }

    Future<_Screen> shoot(WidgetTester tester) async {
      await tester.pumpAndSettle();
      final ratio = tester.view.devicePixelRatio;
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary),
      );
      return (await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: ratio);
        final data = await image.toByteData();
        final screen = _Screen(data!.buffer.asUint8List(), image.width, ratio);
        image.dispose();
        return screen;
      }))!;
    }

    /// The point [fraction] of the way across [slot].
    Offset within(Rect slot, double x, double y) =>
        slot.topLeft + Offset(slot.width * x, slot.height * y);

    testWidgets('the live picture stands on the print\'s ground inside the '
        'slot, and the page around it does not change', (tester) async {
      final printed = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
        return recorder.endRecording().toImage(64, 36);
      }))!;
      addTearDown(printed.dispose);
      final slot = await pumpPanel(
        tester,
        framed(zoom: 2),
        printed: printed,
      );
      final off = await shoot(tester);
      brushOn.value = true;
      final on = await shoot(tester);

      // The camera at 2× about the middle frames canvas x 160–480 and
      // y 90–270 in the slot.
      final empty = within(slot, 0.55, 0.6);
      expect(off.colorAt(empty), const Color(0xFFFF0000));
      expect(
        on.colorAt(empty),
        const Color(0xFFFFFFFF),
        reason: 'the live picture covers the printed one with the ground '
            'the print stands on',
      );
      expect(on.colorAt(within(slot, 0.1, 0.12)), blue);

      final around = slot.inflate(30);
      final kept = slot.inflate(2);
      final moved = [
        for (var y = around.top.ceil(); y < around.bottom; y += 1)
          for (var x = around.left.ceil(); x < around.right; x += 1)
            if (!kept.contains(Offset(x + 0.5, y + 0.5)) &&
                on.colorAt(Offset(x + 0.5, y + 0.5)) !=
                    off.colorAt(Offset(x + 0.5, y + 0.5)))
              Offset(x + 0.5, y + 0.5),
      ];
      expect(
        moved,
        isEmpty,
        reason: 'the canvas the camera does not frame stays off the page',
      );

      final buffers = session.renderCaches.livePictureBufferBytes;
      expect(buffers.keys, ['picture-39-0'], reason: 'the census counts it');
      brushOn.value = false;
      await tester.pumpAndSettle();
      expect(buffers, isEmpty, reason: 'and stops when it goes');
    });

    testWidgets('🗣️F-215: the brush switch moves no pixel — the band\'s '
        'handwriting and the picture print where and as the live windows '
        'draw them (유저 2026-10-01: 「허용 on하면 칸 잉크는 선명해지고 '
        '살짝오른쪽이동, 픽쳐칸 그림은 왼쪽위 0.5픽셀?1픽셀? 이동. 대체 '
        '왜?」)', (tester) async {
      // A ratio that leaves edges inside device pixels, so the print's snap
      // and the live views' each have something to round.
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      // The camera at 4× frames canvas x 240–400, y 135–225: white, and
      // from x 384 the blue of tile (3, 1). What the print renders of it,
      // pixel for pixel.
      final printed = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder)
          ..drawColor(exportFrameGround, BlendMode.src)
          ..drawRect(
            const Rect.fromLTWH(144, 0, 16, 90),
            Paint()..color = blue,
          );
        return recorder.endRecording().toImage(160, 90);
      }))!;
      addTearDown(printed.dispose);
      bool hatch(Color color) =>
          color.r < 0.1 && color.g < 0.1 && color.b < 0.1 && color.a > 0.9;
      bool isBlue(Color color) => color == blue;
      // Swept, not sampled: a shift under a pixel moves a nearest sample
      // only where it carries one across a boundary, and one view can sit
      // where neither print does.
      final moved = <String>[];
      for (final zoom in const [1.13, 1.37, 1.71, 2.29]) {
        for (final (panX, panY) in const [(13.3, 7.7), (5.61, 21.47)]) {
          final slot = await pumpPanel(
            tester,
            framed(zoom: 4, inkId: 'band'),
            printed: printed,
            band: hatched,
            view: CanvasViewport(zoom: zoom, panX: panX, panY: panY),
          );
          final off = await shoot(tester);
          // The band beside the picture: no silhouette there to stand in
          // for the handwriting.
          final band = Rect.fromLTWH(
            slot.right + 20,
            slot.top + 10,
            60,
            slot.height - 20,
          );
          expect(
            off.countIn(band, hatch),
            greaterThan(200),
            reason: 'LIVENESS — the band\'s handwriting prints at $zoom',
          );
          expect(
            off.countIn(slot, isBlue),
            greaterThan(200),
            reason: 'LIVENESS — the picture prints at $zoom',
          );
          brushOn.value = true;
          final on = await shoot(tester);
          final unlike = on.unlike(off);
          if (unlike.isNotEmpty) {
            moved.add('at $zoom ($panX, $panY): $unlike');
          }
        }
      }
      expect(moved, isEmpty, reason: 'device pixels the brush switch moved');
    });

    testWidgets('the camera\'s work is printed over the live picture — its '
        'frames, the trails of their corners and its names, as the page '
        'prints them (유저 2026-09-30)', (tester) async {
      // At 2× the camera pans from canvas x 160–480 to 240–560: the cell
      // shows the canvas the two frames sweep, OUT's frame in red.
      final slot = await pumpPanel(
        tester,
        framed(
          zoom: 2,
          last: CameraPose(center: CanvasPoint(x: 400, y: 180), zoom: 2),
        ),
      );
      bool red(Color color) =>
          color.r > 0.5 && color.g < 0.35 && color.b < 0.35;
      final off = await shoot(tester);
      expect(
        off.countIn(slot, red),
        greaterThan(10),
        reason: 'fixture: the page prints OUT\'s red frame',
      );
      brushOn.value = true;
      final on = await shoot(tester);
      expect(
        find.byKey(const ValueKey<String>('conte-picture-live-picture-39-0')),
        findsOneWidget,
        reason: 'fixture: the live picture is up',
      );
      expect(
        on.countIn(slot, red),
        greaterThan(10),
        reason: 'the live picture covers the print, and the camera\'s work '
            'is printed again over it',
      );
    });

    testWidgets('a row posed off the canvas is cropped at the canvas, as the '
        'print crops it', (tester) async {
      // The camera at ½× frames canvas x −320–960 and y −180–540: the
      // canvas sits in the slot's middle half. The row moved 100 left puts
      // its top-left ink at canvas x −100–156.
      final slot = await pumpPanel(
        tester,
        framed(
          zoom: 0.5,
          rowPose: CameraPose(center: CanvasPoint(x: 220, y: 180)),
        ),
      );
      brushOn.value = true;
      final on = await shoot(tester);

      // Canvas (−51, 58): inked, but off the canvas.
      expect(on.colorAt(within(slot, 0.21, 0.33)), const Color(0xFFFFFFFF));
      // Canvas (64, 58): inked, on it.
      expect(on.colorAt(within(slot, 0.30, 0.33)), blue);
      // Canvas (200, 58): inked only where the row would be unposed.
      expect(
        on.colorAt(within(slot, 0.406, 0.33)),
        const Color(0xFFFFFFFF),
        reason: 'the row\'s pose is where the picture puts it',
      );
    });

    // 🗣️F-197 (유저 2026-09-27): 「해당컷 채우기로 전면 검정색됫는데
    // 콘티프리뷰패널에서 줌하거나 팬할때 그림이랑 실루엣 경계에 흰 여백? 선이
    // 생김」 · 「팬은 아니고 줌할때마다 생김」.
    testWidgets('🚨with the brush on, a cut filled black meets the silhouette '
        'with no light line across any side of its window, at any zoom', (
      tester,
    ) async {
      final printed = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF000000), BlendMode.src);
        return recorder.endRecording().toImage(64, 36);
      }))!;
      addTearDown(printed.dispose);
      final seams = <String>[];
      var scans = 0;
      for (final zoom in const [0.83, 1.37, 1.9]) {
        await pumpPanel(
          tester,
          framed(zoom: 1),
          printed: printed,
          cel: filledBlack(),
          view: CanvasViewport(zoom: zoom, panX: 11, panY: 7),
        );
        brushOn.value = true;
        final on = await shoot(tester);
        expect(
          find.byKey(const ValueKey<String>('conte-picture-live-picture-39-0')),
          findsOneWidget,
          reason: 'fixture: the live picture is up',
        );

        // Where the page is on the screen: the form's own printer's view.
        final form = conteBodyForm();
        final painter =
            tester.widget<CustomPaint>(form).painter! as ContePagePainter;
        final view = renderSnappedViewport(
          painter.viewport!,
          painter.effectiveRatio,
        );
        final origin =
            tester.getTopLeft(form) - tester.getTopLeft(find.byKey(boundary));
        Offset onScreen(Offset paper) =>
            origin +
            Offset(
              view.panX + view.zoom * paper.dx,
              view.panY + view.zoom * paper.dy,
            );
        final slot = contePictureSlot(
          painter.page.cells.single,
          painter.page.metrics,
        );
        final middle = onScreen(slot.center);
        // Across each side: three device pixels either way of the edge.
        for (final (side, edge, across) in [
          ('left', onScreen(slot.centerLeft).dx, true),
          ('right', onScreen(slot.centerRight).dx, true),
          ('top', onScreen(slot.topCenter).dy, false),
          ('bottom', onScreen(slot.bottomCenter).dy, false),
        ]) {
          final device = edge * on.ratio;
          for (var d = device.floor() - 3; d <= device.ceil() + 3; d += 1) {
            final point = across
                ? Offset((d + 0.5) / on.ratio, middle.dy)
                : Offset(middle.dx, (d + 0.5) / on.ratio);
            final red = (on.colorAt(point).r * 255).round();
            scans += 1;
            if (red > 64) {
              seams.add('zoom $zoom, $side side, device pixel $d: $red');
            }
          }
        }
      }
      expect(scans, greaterThan(50), reason: 'fixture: the edges are read');
      expect(seams, isEmpty);
    });

    testWidgets('🗣️the panel asks a cell\'s picture at the height it shows '
        'it, in device pixels — and twice as tall at twice the zoom '
        '(유저 2026-09-25 「화면이 필요한 만큼(최대 원본)」)', (tester) async {
      final printed = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
        return recorder.endRecording().toImage(64, 36);
      }))!;
      addTearDown(printed.dispose);
      final ratio = tester.view.devicePixelRatio;

      askedHeights.clear();
      final slot = await pumpPanel(tester, framed(zoom: 1), printed: printed);
      expect(askedHeights, isNotEmpty, reason: 'fixture: the cell asks');
      final atOne = askedHeights.last;
      expect(atOne, closeTo(slot.height * ratio, 2));

      await pumpPanel(
        tester,
        framed(zoom: 1),
        printed: printed,
        view: CanvasViewport(zoom: 2),
      );
      expect(askedHeights.last, closeTo(atOne * 2, 2));
    });
  });
}

int _alphaAt(Uint8List rgba, int width, Offset at) =>
    rgba[(at.dy.floor() * width + at.dx.floor()) * 4 + 3];

/// A capture of the screen, read at LOGICAL points.
class _Screen {
  _Screen(this.rgba, this.width, this.ratio);

  final Uint8List rgba;
  final int width;
  final double ratio;

  Color colorAt(Offset logical) {
    final i =
        ((logical.dy * ratio).floor() * width + (logical.dx * ratio).floor()) *
        4;
    return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  /// The first [most] device pixels where [other] differs from this, as
  /// `(x, y) this≠other` — and how many there are in all.
  List<String> unlike(_Screen other, {int most = 8}) {
    final found = <String>[];
    var count = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] != other.rgba[i] ||
          rgba[i + 1] != other.rgba[i + 1] ||
          rgba[i + 2] != other.rgba[i + 2] ||
          rgba[i + 3] != other.rgba[i + 3]) {
        count += 1;
        if (found.length < most) {
          final pixel = i ~/ 4;
          found.add(
            '(${pixel % width}, ${pixel ~/ width}) '
            '${rgba.sublist(i, i + 4)}≠${other.rgba.sublist(i, i + 4)}',
          );
        }
      }
    }
    return [if (count > 0) '$count in all', ...found];
  }

  /// How many device pixels inside [rect] read as [test] says.
  int countIn(Rect rect, bool Function(Color color) test) {
    var count = 0;
    for (var y = (rect.top * ratio).ceil(); y < rect.bottom * ratio; y += 1) {
      for (var x = (rect.left * ratio).ceil(); x < rect.right * ratio; x += 1) {
        if (test(colorAt(Offset(x + 0.5, y + 0.5) / ratio))) {
          count += 1;
        }
      }
    }
    return count;
  }
}

/// A picture store whose one picture never changes.
class _NeverLands implements Listenable {
  const _NeverLands();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
