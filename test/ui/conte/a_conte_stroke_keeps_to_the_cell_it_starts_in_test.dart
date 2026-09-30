import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/conte_book.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️H49 (유저 2026-09-30): 「그냥 선 시작한곳에따라 칸 나누자. 픽쳐칸에서
/// 그리기시작하면 해당 레이어? 칸에서만 작동하도록. 밖으로 나가면 해당
/// 캔버스의 카메라 밖 영역에 그리긴 하게 … 일반칸은 일반칸내에서만 지정된
/// 범위 안에서만 그려지도록」.
///
/// A stroke on the conte is the cell's it starts in: a picture's goes on
/// into its cut's canvas wherever the pen goes, and a band's stays in the
/// band — right up to a picture's edge, at every zoom, with no device pixel
/// between the two (F-216, 유저 2026-09-28: 「칸 사이에 흰 빈공간이 존재.
/// 줌 배율에 따라 사라지거나 생기거나 함」).
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const boundary = ValueKey<String>('screen');
  const blue = 0xFF0000FF;

  // One camera key: no IN and OUT printed over the pictures. Below a zoom
  // of 1 the camera sees past the canvas, and its frame shows that much of
  // the pasteboard round it.
  Project project({required double cameraZoom}) {
    final pose = CameraPose(
      center: CanvasPoint(x: 320, y: 180),
      zoom: cameraZoom,
    );
    return Project(
      id: const ProjectId('seam-project'),
      name: 'Seam',
      createdAt: DateTime.utc(2026, 9, 29),
      cameraSize: canvas,
      tracks: [
        Track(
          id: const TrackId('seam-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('39'),
              name: '39',
              duration: 10,
              canvasSize: canvas,
              camera: CutCamera(keyframes: {0: pose}),
              layers: [
                Layer(
                  id: const LayerId('39-sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [
                    for (final start in const [0, 5])
                      Frame(
                        id: FrameId('39-$start'),
                        duration: 1,
                        strokes: const [],
                      ),
                  ],
                  timeline: {
                    for (final start in const [0, 5])
                      start: TimelineExposure.drawing(
                        FrameId('39-$start'),
                        length: 5,
                        memo: ExposureMemo(inkId: 'ink-$start'),
                      ),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Whether the panel's brush is on.
  late ValueNotifier<bool> brushOn;

  /// The page's own ink: the cells' bands.
  late ConteInkController ink;

  /// The panel's zoom, moved while the panel stays mounted.
  late ValueNotifier<double> panelZoom;

  /// The panel with its brush on, a blue brush [size] wide, seen at
  /// [zoom] from a view off the whole-pixel grid — its pictures printed
  /// white, so what shows in them is what the page lays over the print.
  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester, {
    required double zoom,
    required double size,
    double cameraZoom = 1,
  }) async {
    brushOn = ValueNotifier<bool>(true);
    addTearDown(brushOn.dispose);
    panelZoom = ValueNotifier<double>(zoom);
    addTearDown(panelZoom.dispose);
    final session = EditorSessionManager(
      initialProject: project(cameraZoom: cameraZoom),
    );
    addTearDown(session.dispose);
    ink = ConteInkController();
    addTearDown(ink.dispose);
    final cels = ContePictureInkController(
      cels: session.renderCaches.brushFrameStore,
    );
    addTearDown(cels.dispose);
    final brush = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.copyWith(
        color: blue,
        size: size,
        opacity: 1,
        flow: 1,
        hardness: 1,
      ),
    );
    addTearDown(brush.dispose);
    final printed = (await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
      return recorder.endRecording().toImage(64, 36);
    }))!;
    addTearDown(printed.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                session,
                ink,
                cels,
                brushOn,
                panelZoom,
              ]),
              builder: (context, _) => ConteTabHost(
                session: session,
                thumbnails: (
                  resolve: (cut, frame, {required shownHeight, region}) => printed,
                  landed: const _NeverLands(),
                  pending: () => false,
                ),
                viewport: seedFromRender(
                  tester,
                  onConteBody(
                    session,
                    CanvasViewport(
                      zoom: panelZoom.value,
                      panX: 7.3,
                      panY: 5.6,
                    ),
                  ),
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
    await _settle(tester);
    return session;
  }

  /// [paper] on the first body page, where the screen shows it — through
  /// the view the page's form is printed through.
  Offset onScreen(WidgetTester tester, Offset paper) {
    final form = conteBodyForm();
    final painter = tester.widget<CustomPaint>(form).painter!
        as ContePagePainter;
    final view = renderSnappedViewport(
      painter.viewport!,
      painter.effectiveRatio,
    );
    final origin =
        tester.getTopLeft(form) - tester.getTopLeft(find.byKey(boundary));
    return origin +
        Offset(
          view.panX + view.zoom * paper.dx,
          view.panY + view.zoom * paper.dy,
        );
  }

  Future<_Shot> shoot(WidgetTester tester) async {
    final ratio = tester.view.devicePixelRatio;
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    return (await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: ratio);
      final data = await image.toByteData();
      final shot = _Shot(data!.buffer.asUint8List(), image.width, ratio);
      image.dispose();
      return shot;
    }))!;
  }

  /// A pen drawn from [from] to [to] on screen, two points a step.
  Future<void> draw(WidgetTester tester, Offset from, Offset to) async {
    final origin = tester.getTopLeft(find.byKey(boundary));
    final pen = await tester.startGesture(
      origin + from,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    final steps = ((to - from).distance / 2).ceil();
    for (var i = 1; i <= steps; i += 1) {
      await pen.moveTo(origin + Offset.lerp(from, to, i / steps)!);
      await tester.pump();
    }
    await pen.up();
    await _settle(tester);
  }

  for (final zoom in const [0.83, 1.37]) {
    testWidgets('at ${(zoom * 100).round()}%, a stroke started in a picture '
        'is the picture\'s: down through the silhouette into the next cell, '
        'nothing of it shows outside the picture', (tester) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPanel(tester, zoom: zoom, size: 24);
      final page = (tester.widget<CustomPaint>(conteBodyForm()).painter!
              as ContePagePainter)
          .page;
      final upper = contePictureSlot(page.cells[0], page.metrics);
      final lower = contePictureSlot(page.cells[1], page.metrics);
      expect(lower.top, greaterThan(upper.bottom), reason: 'fixture');

      await draw(
        tester,
        onScreen(tester, upper.center),
        onScreen(tester, lower.center + const Offset(0, 30)),
      );

      final shot = await shoot(tester);
      final between = Offset(upper.center.dx, (upper.bottom + lower.top) / 2);
      expect(
        _isInk(shot.pixelAt(onScreen(tester, upper.center))),
        isTrue,
        reason: 'fixture: the picture shows it',
      );
      expect(
        _isInk(shot.pixelAt(onScreen(tester, between))),
        isFalse,
        reason: 'the black between the pictures is the band\'s, which took '
            'none of it',
      );
      expect(
        _isInk(shot.pixelAt(onScreen(tester, lower.center))),
        isFalse,
        reason: 'nor the next picture',
      );
    });

    testWidgets('at ${(zoom * 100).round()}%, a stroke started in a cell\'s '
        'band stays in that band: the next cell\'s keeps none of it', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPanel(tester, zoom: zoom, size: 24);
      final page = (tester.widget<CustomPaint>(conteBodyForm()).painter!
              as ContePagePainter)
          .page;
      final upper = contePictureSlot(page.cells[0], page.metrics);
      final lower = contePictureSlot(page.cells[1], page.metrics);
      final x = upper.right + 40;

      await draw(
        tester,
        onScreen(tester, Offset(x, upper.center.dy)),
        onScreen(tester, Offset(x, lower.center.dy)),
      );

      final shot = await shoot(tester);
      expect(
        _isInk(shot.pixelAt(onScreen(tester, Offset(x, upper.center.dy)))),
        isTrue,
        reason: 'fixture: the band shows it',
      );
      expect(
        _isInk(shot.pixelAt(onScreen(tester, Offset(x, lower.center.dy)))),
        isFalse,
        reason: 'the next cell\'s band took none of it',
      );
    });
  }

  // With the brush off the picture is its print, and the band's ink —
  // which keeps a ring of the stroke past the picture's edge — shows up to
  // that edge and not a device pixel into it.
  for (final zoom in const [0.83, 1.37]) {
    testWidgets('at ${(zoom * 100).round()}%, the brush off: a band\'s ink '
        'runs to the printed picture\'s edge and not into it', (tester) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPanel(tester, zoom: zoom, size: 24);
      final form = conteBodyForm();
      final painter = tester.widget<CustomPaint>(form).painter!
          as ContePagePainter;
      final page = painter.page;
      final slot = contePictureSlot(page.cells[0], page.metrics);
      final from = onScreen(tester, slot.center + const Offset(0, 20));
      final to = onScreen(
        tester,
        Offset(slot.right + 40, slot.center.dy + 20),
      );
      // From the words into the picture: the band's stroke.
      await draw(
        tester,
        onScreen(tester, Offset(slot.right + 80, slot.center.dy + 20)),
        onScreen(tester, slot.center + const Offset(-30, 20)),
      );
      brushOn.value = false;
      await _settle(tester);

      // Along the line: the print's white, then the ink — nothing blue in
      // the print, nothing but ink after it.
      final walk = (await shoot(tester)).walk(from, to);
      final firstInk = walk.indexWhere(_isInk);
      expect(firstInk, greaterThan(0), reason: 'fixture: the ink is there');
      expect(
        walk.take(firstInk).where((pixel) => !_isPrint(pixel)),
        isEmpty,
        reason: 'the print shows up to where the ink starts',
      );
      final lastInk = walk.lastIndexWhere(_isInk);
      expect(
        walk.sublist(firstInk, lastInk + 1).where((pixel) => !_isInk(pixel)),
        isEmpty,
        reason: 'and the ink runs unbroken from there',
      );
    });
  }

  // A camera that sees past the canvas: its frame shows the pasteboard, and
  // the picture is cropped at the canvas (「페이스트보드는 포함 안 시킴」). A
  // stroke started on the canvas is the picture's all the way — past the
  // canvas's edge it goes on into the cel, cropped from view like the rest
  // of the pasteboard, and the band under the frame takes none of it.
  for (final zoom in const [0.83, 1.37]) {
    testWidgets('at ${(zoom * 100).round()}%, a stroke out of the canvas into '
        'the pasteboard its picture shows stays the picture\'s', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await pumpPanel(
        tester,
        zoom: zoom,
        size: 24,
        cameraZoom: 0.5,
      );
      final form = conteBodyForm();
      final painter = tester.widget<CustomPaint>(form).painter!
          as ContePagePainter;
      final page = painter.page;
      final slot = contePictureSlot(page.cells[0], page.metrics);
      final canvasRight = contePicturesOverInkIn(
        session,
        page,
      ).first.canvas.map((point) => point.dx).reduce(math.max);
      expect(
        canvasRight,
        lessThan(slot.right - 10),
        reason: 'fixture: the frame shows pasteboard right of the canvas',
      );
      await draw(
        tester,
        onScreen(tester, slot.center - const Offset(30, 0)),
        onScreen(tester, Offset(slot.right + 80, slot.center.dy)),
      );

      final shot = await shoot(tester);
      expect(
        _isInk(shot.pixelAt(onScreen(tester, slot.center))),
        isTrue,
        reason: 'fixture: the canvas shows it',
      );
      final pasteboard = Offset((canvasRight + slot.right) / 2, slot.center.dy);
      expect(
        _isInk(shot.pixelAt(onScreen(tester, pasteboard))),
        isFalse,
        reason: 'the pasteboard the frame shows is cropped, and the band '
            'under it took none of the stroke',
      );
      expect(
        _isInk(
          shot.pixelAt(
            onScreen(tester, Offset(slot.right + 40, slot.center.dy)),
          ),
        ),
        isFalse,
        reason: 'nor the words beside the picture',
      );
    });
  }

  // What a cell's band keeps under its picture — a stroke's ring past the
  // picture's edge, or handwriting from before the cell had a picture —
  // shows nowhere the picture shows its canvas: not over the composite with
  // the brush on, nor over the print with it off, whatever the zoom moves
  // to.
  for (final on in const [true, false]) {
    testWidgets('the brush ${on ? 'on' : 'off'}: the band\'s ink under a '
        'picture shows nowhere in it, at any zoom', (tester) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await pumpPanel(tester, zoom: 1.37, size: 24);
      final form = conteBodyForm();
      final painter = tester.widget<CustomPaint>(form).painter!
          as ContePagePainter;
      final page = painter.page;
      final slot = contePictureSlot(page.cells[0], page.metrics);
      final under = slot.center;
      final beside = Offset(slot.right + 30, slot.center.dy);
      ink.commitStroke(
        plane: null,
        key: conteInkRowKey(const CutId('39'), 'ink-0'),
        strokeData: conteBandDabs(
          page.cells[0],
          page.metrics,
          [under, beside],
          color: blue,
        ),
        historyManager: session.historyManager,
      );
      brushOn.value = on;
      for (final zoom in const [1.37, 0.83]) {
        panelZoom.value = zoom;
        await _settle(tester);
        final shot = await shoot(tester);
        expect(
          _isInk(shot.pixelAt(onScreen(tester, beside))),
          isTrue,
          reason: 'fixture: the band shows its ink beside the picture at '
              '$zoom',
        );
        expect(
          _isPrint(shot.pixelAt(onScreen(tester, under))),
          isTrue,
          reason: 'and none of it in the picture at $zoom',
        );
      }
    });
  }

  // The canvas a picture shows moves with its camera, and the band's ink
  // round it follows: the pasteboard the frame showed is the canvas's once
  // the camera closes in.
  for (final on in const [true, false]) {
    testWidgets('the brush ${on ? 'on' : 'off'}: the band\'s ink in a '
        'picture\'s pasteboard hides once its camera shows the canvas '
        'there', (tester) async {
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await pumpPanel(
        tester,
        zoom: 1.37,
        size: 24,
        cameraZoom: 0.5,
      );
      final form = conteBodyForm();
      final painter = tester.widget<CustomPaint>(form).painter!
          as ContePagePainter;
      final page = painter.page;
      final over = contePicturesOverInkIn(session, page).first;
      final frame = over.picture.frame;
      final canvasRight = over.canvas.map((point) => point.dx).reduce(math.max);
      expect(
        frame.right - canvasRight,
        greaterThan(12),
        reason: 'fixture: the frame shows pasteboard right of the canvas',
      );
      final pasteboard = Offset(
        (canvasRight + frame.right) / 2,
        frame.center.dy,
      );
      ink.commitStroke(
        plane: null,
        key: conteInkRowKey(const CutId('39'), 'ink-0'),
        strokeData: conteBandDabs(
          page.cells[0],
          page.metrics,
          [pasteboard],
          color: blue,
          size: 6,
        ),
        historyManager: session.historyManager,
      );
      brushOn.value = on;
      await _settle(tester);
      expect(
        _isInk((await shoot(tester)).pixelAt(onScreen(tester, pasteboard))),
        isTrue,
        reason: 'the pasteboard is the band\'s: its ink shows there',
      );

      // The camera key moved as the app moves it: the session tells the
      // panel.
      session.camera.setCameraKeyframeAtCurrentFrame(
        CameraPose(center: CanvasPoint(x: 320, y: 180)),
      );
      await _settle(tester);
      expect(
        _isPrint((await shoot(tester)).pixelAt(onScreen(tester, pasteboard))),
        isTrue,
        reason: 'the canvas is there now, over the band\'s ink',
      );
    });
  }

  // 🗣️H50 (유저 2026-09-30): 「원본 1:1그대로 공용로직 그대로 적용해서
  // 원복하자. 지금 브러시 너무작은데 중요한건 너무작아서 브러시가 끊겨서」.
  // ↩️F-217 drew the paper's brush at the pictures' scale — 640 pixels of
  // camera over a window 243 points wide — so a 24-pixel brush was 9 on
  // the paper.
  testWidgets('🗣️H50: the paper reads the brush at its own size, a pixel of '
      'it a pixel of the paper — as the timesheet and the envelope do', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPanel(tester, zoom: 1.37, size: 24);
    final page = (tester.widget<CustomPaint>(conteBodyForm()).painter!
            as ContePagePainter)
        .page;
    final slot = contePictureSlot(page.cells[0], page.metrics);
    final y = slot.center.dy;
    await draw(
      tester,
      onScreen(tester, Offset(slot.right + 20, y)),
      onScreen(tester, Offset(slot.right + 90, y)),
    );

    final band = conteInkWindows(page).singleWhere(
      (window) => window.key == conteInkRowKey(const CutId('39'), 'ink-0'),
    );
    final surface = ink
        .sessionStateFor(null, band.key)
        .canvasState
        .currentSurface;
    final across = band.placement.pixelOf(Offset(slot.right + 55, y));
    var inked = 0;
    for (var dy = -40; dy <= 40; dy += 1) {
      final rgba = surfacePixelRgba(
        surface,
        across.dx.floor(),
        across.dy.floor() + dy,
      );
      if ((rgba ?? 0) != 0) {
        inked += 1;
      }
    }
    expect(
      inked,
      inInclusiveRange(22, 26),
      reason: 'a brush 24 pixels wide, 24 pixels of the paper',
    );
  });
}

/// The stroke's blue — over the paper or the silhouette alike: blue well
/// above the other two.
bool _isInk(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return b - (r > g ? r : g) > 90;
}

/// The white the pictures print.
bool _isPrint(Color color) =>
    color.r > 0.8 && color.g > 0.8 && color.b > 0.8;

/// Every asynchronous build the last change set off, landed and drawn.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 10; round += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// A capture of the screen at its device pixels.
class _Shot {
  _Shot(this.rgba, this.width, this.ratio);

  final Uint8List rgba;
  final int width;
  final double ratio;

  /// The device pixels along the segment [from]–[to] (logical points),
  /// one a step.
  List<Color> walk(Offset from, Offset to) {
    final a = from * ratio;
    final b = to * ratio;
    final steps = (b - a).distance.ceil();
    return [
      for (var i = 0; i <= steps; i += 1) _at(Offset.lerp(a, b, i / steps)!),
    ];
  }

  /// The device pixel at [point] (logical points).
  Color pixelAt(Offset point) => _at(point * ratio);

  Color _at(Offset device) {
    final o = (device.dy.floor() * width + device.dx.floor()) * 4;
    return Color.fromARGB(rgba[o + 3], rgba[o], rgba[o + 1], rgba[o + 2]);
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
