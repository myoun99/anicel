import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';

/// 🚨A CONTE PICTURE TAKES THE PEN INTO ITS BLOCK'S CEL (유저 2026-09-25,
/// conte-drawing-target: 「그림 칸 안의 부분은 그 블록의 콘티 레이어
/// 그림으로」 · 「진짜 하나의 용지처럼. 데이터는 나누더라도」 · 「보이는
/// 거 = 결과」).
///
/// The part of a stroke drawn on a cell's picture lands in the cel the
/// picture shows — through the camera and the layer's placement, the maps
/// the picture is printed by — and the rest on the sheet's own ink, as one
/// stroke and one undo. While the brush is on, the picture is the cut's
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
        conteRowOf: (cut) => null,
        rowRefusal: null,
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
                  page: page,
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

    testWidgets('one paper: a stroke from the picture out over its cell\'s '
        'band keeps the picture\'s part in the block\'s cel and the rest in '
        'the cell\'s ink — ONE undo', (tester) async {
      final origin = await pump(
        tester,
        CameraPose(center: CanvasPoint(x: 320, y: 180)),
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
      BitmapSurface rowSurface() => ink
          .sessionStateFor(ConteInkPlane.row, row.key)
          .canvasState
          .currentSurface;
      // The picture's middle is the pose's centre: the camera at rest.
      const underInside = Offset(320, 180);

      expect(inkAt(store.bakedSurfaceOrNull(picture.window.key), underInside),
          isTrue);
      expect(inkAt(rowSurface(), row.placement.pixelOf(outside)), isTrue);
      expect(
        inkAt(rowSurface(), row.placement.pixelOf(inside)),
        isFalse,
        reason: 'the picture shows that spot, so the cel keeps it',
      );

      history.undo();
      expect(
        inkAt(store.bakedSurfaceOrNull(picture.window.key), underInside),
        isFalse,
      );
      expect(ink.hasInkFor(ConteInkPlane.row, row.key), isFalse);

      history.redo();
      expect(
        inkAt(store.bakedSurfaceOrNull(picture.window.key), underInside),
        isTrue,
      );
      expect(ink.hasInkFor(ConteInkPlane.row, row.key), isTrue);
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
              viewport: seedFromRender(tester, CanvasViewport()),
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
    final pageTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('conte-form-paint')),
    );
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
    final pen = tester
        .widgetList<SheetInkLayer>(find.byType(SheetInkLayer))
        .single
        .windows
        .whereType<SheetPictureWindow>()
        .single;
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
        ConteInkPlane.row,
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
  // ground, the layers cropped at the canvas, inside the slot's rounded
  // corners, the camera's labels over it — and nothing around it moves.
  group('on screen, while the brush is on', () {
    const boundary = ValueKey<String>('screen');
    const blue = Color(0xFF0000FF);
    late EditorSessionManager session;
    late ValueNotifier<bool> brushOn;

    /// The cut framed by its camera at [zoom] about the canvas's middle,
    /// held over its one block — two keys, so the page prints IN and OUT
    /// on the picture — its conte row posed by [rowPose].
    Project framed({required double zoom, TransformPose? rowPose}) {
      final pose = CameraPose(center: CanvasPoint(x: 320, y: 180), zoom: zoom);
      final base = cut();
      final row = base.layers.single;
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
                camera: CutCamera(keyframes: {0: pose, 9: pose}),
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

    /// The panel on [project], its brush off, with the block's cel inked
    /// and the page's printed picture [printed].
    Future<Rect> pumpPanel(
      WidgetTester tester,
      Project project, {
      ui.Image? printed,
    }) async {
      session = EditorSessionManager(initialProject: project);
      addTearDown(session.dispose);
      final ink = ConteInkController();
      addTearDown(ink.dispose);
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
        inked(),
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
                                tier = StoryboardThumbnailTier.sheet,
                              }) => printed,
                          landed: const _NeverLands(),
                        ),
                  viewport: seedFromRender(tester, CanvasViewport()),
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
          tester.getTopLeft(
            find.byKey(const ValueKey<String>('conte-form-paint')),
          ) -
          tester.getTopLeft(find.byKey(boundary));
      return contePictureSlot(
        page.cells.single,
        page.metrics,
      ).shift(pageTopLeft);
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
        'slot\'s rounded corners with the camera\'s labels over it, and the '
        'page around it does not change', (tester) async {
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

      // The slot's corner lies outside its rounded shape: what the page
      // shows there, not the cel.
      final corner = slot.topLeft + const Offset(0.5, 0.5);
      expect(
        on.colorAt(corner),
        off.colorAt(corner),
        reason: 'the picture is cut at the slot\'s rounded corner',
      );

      // OUT sits on the cel's inked right side, printed over the picture.
      final out = Rect.fromLTRB(
        slot.right - 40,
        slot.bottom - 16,
        slot.right - 2,
        slot.bottom - 2,
      );
      expect(
        on.countIn(out, (color) => color != blue),
        greaterThan(10),
        reason: 'the camera\'s labels are printed over the live picture',
      );

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
