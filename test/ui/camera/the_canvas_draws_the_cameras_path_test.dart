import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/camera_path.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/camera/camera_path_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/session/camera.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart' show CameraSizeDraft;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

/// I-89 ④ — the camera's path on the canvas: drawn as the canvas's camera
/// path settings say, whether or not the canvas draws the camera's frame
/// (유저 2026-10-13: 「on하든 off하든 설정한대로 보이도록」 — ↩️ 10-12
/// 「비지블버튼처럼 어느 상태에 있던 카메라 사각형을 보여주는 규칙 그대로
/// 경로도」 drew it where the frame was) — in time only standing on the
/// camera's row, where its frame is worked (「nf마다의 작은 십자가, 핸들
/// 이런게 서있으면 보여주도록」), and elsewhere as the export writes it.
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

  /// The spec's grey behind the playhead and blue ahead of it (2026-10-10,
  /// the mock's 5판), and a key between's ink.
  const grey = 0xFF8E9093;
  const blue = 0xFF3A78C8;
  const ink = 0xFF101010;

  /// A cut whose camera pans 200 canvas pixels right from frame 0 to frame
  /// 5, stood on at frame 0 on its camera row.
  (EditorSessionManager, LayerId) panning() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final camera = cameraOf(s);
    s.selectFrameIndex(0);
    final start = camera.cameraPoseAtCurrentFrame;
    camera.setCameraKeyframeAtCurrentFrame(start);
    s.selectFrameIndex(5);
    camera.setCameraKeyframeAtCurrentFrame(
      start.copyWith(
        center: CanvasPoint(x: start.center.x + 200, y: start.center.y),
      ),
    );
    s.selectFrameIndex(0);
    final row = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.camera)
        .id;
    s.standOnRow(LayerRowAddress(row));
    return (s, row);
  }

  /// The canvas over [s], the camera view (the eye) on — handed back, to be
  /// turned.
  Future<ValueNotifier<bool>> pumpArea(
    WidgetTester tester,
    EditorSessionManager s,
  ) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(true);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();
    return cameraView;
  }

  /// The warmer's debounced timers cannot be cancelled by a dispose.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Finder path() => find.byType(CameraPathOverlay);

  List<SheetMark> marks(WidgetTester tester) =>
      tester.widget<CameraPathOverlay>(path()).marks;

  List<Offset> centreTrail(WidgetTester tester) =>
      tester.widget<CameraPathOverlay>(path()).centreTrail;

  /// The screen pixels a pixel of the export spans on the picture — what
  /// the marks it writes are drawn by (F-421).
  double pixel(WidgetTester tester) {
    final overlay = tester.widget<CameraPathOverlay>(path());
    return overlay.viewport.zoom / overlay.printedAt!.zoom;
  }

  /// What the keys are written as — at the size a key's label takes.
  List<String> labels(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetWords &&
          (mark.size - CameraPathOverlay.sizes.labelSize * pixel(tester))
                  .abs() <
              1e-9)
        mark.text,
  ];

  /// The frames the crosses in time wear beside them.
  List<String> tickLabels(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetWords && mark.size == CameraPathOverlay.tickLabelSize)
        mark.text,
  ];

  /// The two-point strokes — the arms of the keys' and the ticks' crosses —
  /// each as long as it is drawn on the screen.
  List<double> arms(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetStroke && !mark.closed && mark.points.length == 2)
        (mark.points.last - mark.points.first).distance,
  ];

  int armsOf(WidgetTester tester) => arms(tester).length;

  /// The frames the path draws, a key each, first to last — on the screen.
  List<List<Offset>> keyFrames(WidgetTester tester) => [
    for (final mark in marks(tester))
      if (mark is SheetStroke && mark.closed) mark.points,
  ];

  /// The camera's frame as the canvas draws it now — on the screen.
  List<Offset> frameDrawn(WidgetTester tester) {
    final frame = tester.widget<CameraFrameOverlay>(
      find.byType(CameraFrameOverlay),
    );
    return [
      for (final corner in cameraFrameCornersInCanvas(
        pose: frame.pose,
        cameraFrameSize: frame.cameraFrameSize,
      ))
        frame.viewport.canvasToViewportOffset(
          CanvasPoint(x: corner.dx, y: corner.dy),
        ),
    ];
  }

  void expectPoints(List<Offset> actual, List<Offset> expected) {
    expect(actual, hasLength(expected.length));
    for (final (index, point) in expected.indexed) {
      expect(actual[index].dx, closeTo(point.dx, 1e-6), reason: 'x $index');
      expect(actual[index].dy, closeTo(point.dy, 1e-6), reason: 'y $index');
    }
  }

  testWidgets('its path is drawn whether or not the camera\'s frame is — in '
      'time only standing on the camera\'s row, where its box is; '
      'elsewhere as the export writes it', (tester) async {
    final (s, row) = panning();
    addTearDown(s.dispose);
    final eye = await pumpArea(tester, s);
    Finder box() => find.byType(CameraFrameBox);

    // The keys' two crosses, and a frame's from 1 to 4 between them.
    void inTime() {
      expect(box(), findsOneWidget, reason: '⛔전제: the frame is worked');
      expect(armsOf(tester), 4 + 8);
    }

    expect(cameraOf(s).isCameraLayerActive, isTrue, reason: '⛔전제');
    inTime();
    for (final lane in ['position', 'scale']) {
      s.standOnRow(LaneRowAddress(row, lane));
      await tester.pump();
      inTime();
    }

    final drawing = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind != LayerKind.camera)
        .id;
    s.standOnRow(LayerRowAddress(drawing));
    await tester.pump();
    expect(cameraOf(s).isCameraLayerActive, isFalse, reason: '⛔전제');
    expect(find.byType(CameraFrameOverlay), findsOneWidget, reason: 'eye');
    expect(box(), findsNothing, reason: '⛔전제: the frame is not worked');
    // As the export writes it: the keys alone — their frames, crosses and
    // labels.
    void asExported() {
      expect(keyFrames(tester), hasLength(2));
      expect(labels(tester), ['1f', '6f']);
      expect(armsOf(tester), 4);
    }

    asExported();

    // ↩️ The frame's eye no longer takes the path with it (2026-10-13).
    eye.value = false;
    await tester.pump();
    expect(find.byType(CameraFrameOverlay), findsNothing, reason: '⛔전제');
    expect(path(), findsOneWidget, reason: 'the frame gone, the path stays');
    asExported();

    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.off,
    );
    await tester.pump();
    expect(path(), findsNothing, reason: 'its own setting still does');

    await drain(tester);
  });

  testWidgets('it writes every key by its frame, and shown in time a cross '
      'at every frame between them with that frame beside it; in space '
      'alone, the keys\' crosses only — and off, nothing', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(labels(tester), ['1f', '6f']);
    expect(armsOf(tester), 4 + 8, reason: 'two keys, and frames 1 to 4');
    expect(
      tickLabels(tester),
      ['2f', '3f', '4f', '5f', '1f', '6f'],
      reason: '유저 2026-10-12: 「그 상황에서 십자가쪽에도 프레임번호」 — and '
          'the keys\' own crosses (I-89-Q16 B 「키의 십자에도」)',
    );
    // The mock's sizes (5판): a key's cross reaches 5 of the export's pixels
    // either way, a frame's 3 of the screen's — no export writes it.
    expect(arms(tester), [
      for (var arm = 0; arm < 4; arm++) closeTo(10 * pixel(tester), 1e-9),
      for (var arm = 0; arm < 8; arm++) closeTo(6, 1e-9),
    ]);

    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.space,
    );
    await tester.pump();
    expect(armsOf(tester), 4);
    expect(tickLabels(tester), isEmpty);
    expect(labels(tester), ['1f', '6f']);

    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.off,
    );
    await tester.pump();
    expect(path(), findsNothing);

    await drain(tester);
  });

  // 🗣️F-368 (유저 2026-10-16): 「공간+시간일때 카메라에 서면 핸들
  // 보여주듯이, 애초에 공간인 상태면 서면 중앙 십자가도 궤적 보여주도록.
  // 공간이든 공간+시간이든 공간이라는 정보로서」 — F-368-Q1 A: 「중앙 궤적
  // 선 + 핸들(두 모드 공통, 서 있을 때)」.
  testWidgets('standing on the camera\'s row it draws the line the camera\'s '
      'middle walks, in space as in space and time — from key\'s cross to '
      'key\'s cross, in the handles\' dashes — and elsewhere none', (
    tester,
  ) async {
    addTearDown(
      () => AppColors.accentSettings.value = const AppAccentSettings(),
    );
    final (s, row) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    CameraPathOverlay overlay() => tester.widget<CameraPathOverlay>(path());
    final picture = find.byKey(const ValueKey<String>('camera-path-overlay'));
    CustomPainter painter() => tester.widget<CustomPaint>(picture).painter!;

    void fromKeyToKey(String when) {
      final line = overlay().centreTrail;
      final crosses = [
        for (final frame in keyFrames(tester)) (frame[0] + frame[2]) / 2,
      ];
      expect(line, hasLength(2 * 5 + 1), reason: '$when: every half frame');
      expectPoints([line.first, line.last], crosses);
    }

    /// The widths of the strokes painted in [color], painted now. A paint
    /// keeps its colour and its width in floats: the colour is read back as
    /// 8-bit, a width to a float's precision.
    List<double> strokesIn(Color color) {
      final canvas = TestRecordingCanvas();
      painter().paint(canvas, tester.getSize(picture));
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath)
            if (call.invocation.positionalArguments[1] case final Paint ink
                when ink.color.toARGB32() == color.toARGB32())
              ink.strokeWidth,
      ];
    }

    fromKeyToKey('in space and time');
    CameraPathSettings.settings.value = const CameraPathSettings(
      show: CameraPathShow.space,
    );
    await tester.pump();
    fromKeyToKey('in space');
    final dashes = strokesIn(AppColors.accent);
    expect(dashes.length, greaterThan(1), reason: 'in dashes');
    expect(
      dashes,
      everyElement(closeTo(CameraPathOverlay.centreTrailWidth, 1e-6)),
    );

    final standing = (painter: painter(), marks: overlay().marks);
    final drawing = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind != LayerKind.camera)
        .id;
    s.standOnRow(LayerRowAddress(drawing));
    await tester.pump();
    expect(path(), findsOneWidget, reason: '⛔전제: the path is drawn');
    expect(overlay().centreTrail, isEmpty, reason: 'as the export writes it');
    expect(
      overlay().marks,
      standing.marks,
      reason: '⛔전제: in space, standing moves nothing else',
    );
    expect(
      painter().shouldRepaint(standing.painter),
      isTrue,
      reason: 'the line alone going repaints the picture',
    );

    s.standOnRow(LayerRowAddress(row));
    await tester.pump();
    final before = painter();
    const recolored = Color(0xFF2244CC);
    AppColors.accentSettings.value = const AppAccentSettings(
      accent: recolored,
    );
    await pumpArea(tester, s);
    expect(strokesIn(recolored), dashes, reason: 'the accent as it is now');
    expect(painter().shouldRepaint(before), isTrue);

    await drain(tester);
  });

  testWidgets('a key\'s frame lands on the camera\'s frame as the canvas '
      'draws it there — through the view, and at the size the frame is being '
      'adjusted to', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final view = tester.widget<CameraPathOverlay>(path()).viewport;
    expect(
      view.canvasToViewportOffset(CanvasPoint(x: 100, y: 50)),
      isNot(const Offset(100, 50)),
      reason: '⛔전제: the screen is not the canvas',
    );
    expectPoints(keyFrames(tester).first, frameDrawn(tester));

    s.selectFrameIndex(5);
    await tester.pump();
    expectPoints(keyFrames(tester).last, frameDrawn(tester));

    final size = cameraOf(s).cameraFrameSize;
    final adjusted = CanvasSize(
      width: size.width ~/ 2,
      height: size.height ~/ 2,
    );
    s.canvasAdjust.begin(CameraSizeDraft(size: adjusted));
    await tester.pump();
    expect(
      tester
          .widget<CameraFrameOverlay>(find.byType(CameraFrameOverlay))
          .cameraFrameSize,
      adjusted,
      reason: '⛔전제: the canvas draws the frame at the size it is given',
    );
    expectPoints(keyFrames(tester).last, frameDrawn(tester));

    s.canvasAdjust.end();
    await drain(tester);
  });

  testWidgets('it follows a camera edit while it is in flight — and writes '
      'nothing', (tester) async {
    final (s, row) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final before = keyFrames(tester).last;
    final end = cameraOf(s).activeCutCameraTrack!.position.keyAt(5)!.value;

    s.laneVerbs.previewLaneValueAt(
      row,
      'position',
      5,
      '${end.x}, ${end.y + 100}',
      frameIsGlobal: false,
      scaleLinked: false,
    );
    await tester.pump();
    final view = tester.widget<CameraPathOverlay>(path()).viewport;
    final down =
        view.canvasToViewportOffset(CanvasPoint(x: 0, y: 100)) -
        view.canvasToViewportOffset(CanvasPoint(x: 0, y: 0));
    expectPoints(keyFrames(tester).last, [
      for (final corner in before) corner + down,
    ]);
    expect(
      s.requireActiveCut.camera.track.position.keyAt(5)!.value,
      end,
      reason: 'nothing is written while it is in flight',
    );

    s.laneVerbs.endLaneEditPreview();
    await drain(tester);
  });

  testWidgets('around the playhead it keeps to so many frames either side, '
      'and goes with the playhead', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    // The line the camera's middle walks, every half frame from 0 to 5.
    final whole = centreTrail(tester);
    expect(whole, hasLength(2 * 5 + 1), reason: '⛔전제');
    CameraPathSettings.settings.value = const CameraPathSettings(
      range: CameraPathRange.aroundPlayhead,
      around: 2,
    );
    await tester.pump();
    expect(labels(tester), ['1f']);
    expect(armsOf(tester), 2 + 4, reason: 'the key at 0, frames 1 and 2');
    expectPoints(centreTrail(tester), whole.sublist(0, 2 * 2 + 1));

    s.selectFrameIndex(5);
    await tester.pump();
    expect(labels(tester), ['6f']);
    expect(armsOf(tester), 2 + 4, reason: 'frames 3 and 4, the key at 5');
    expectPoints(centreTrail(tester), whole.sublist(2 * 3));

    await drain(tester);
  });

  testWidgets('each of its settings reaches the canvas on its own', (
    tester,
  ) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    Future<void> change(
      CameraPathSettings Function(CameraPathSettings now) to,
    ) async {
      CameraPathSettings.settings.value = to(CameraPathSettings.settings.value);
      await tester.pump();
    }

    expect(armsOf(tester), 4 + 8, reason: '⛔전제: a cross at every frame');
    await change((now) => now.copyWith(tickEvery: 2));
    expect(armsOf(tester), 4 + 4, reason: 'frames 2 and 4');

    await change((now) => now.copyWith(around: 2));
    expect(labels(tester), ['1f', '6f'], reason: 'every key, however near');
    await change((now) => now.copyWith(range: CameraPathRange.aroundPlayhead));
    expect(labels(tester), ['1f']);
    expect(armsOf(tester), 2 + 2, reason: 'the key at 0, frame 2');

    await change((now) => now.copyWith(around: 4));
    expect(armsOf(tester), 2 + 4, reason: 'the key at 0, frames 2 and 4');

    await drain(tester);
  });

  // 🗣️F-421 (유저 2026-10-20): 「캔버스 확대해도 축소해도 크기 안바뀌는
  // 벡터?느낌인데 크기는 100%인 상태에서 고정되도록」 · 「사각형 라인도
  // 글자도 픽셀에 올리고싶단느낌」 · 「글자 3배는 너무큰거같으니 2배로」 —
  // F-421-Q1: 「출력시 남는 것만 캔버스 픽셀에 올리고싶은게 목적임. 이유는
  // 출력할때 선의 굵기같은게 참고가 되기때문」.
  group('F-421: what the export writes lies on the picture as large as it '
      'prints', () {
    /// The camera's path of [panning], drawn [zoom] screen pixels to a
    /// canvas pixel — printed at [printedAt], and stood on where [standing].
    Future<CameraPathOverlay> pumpPath(
      WidgetTester tester, {
      required double zoom,
      required CameraPose? printedAt,
      bool standing = false,
    }) async {
      final (s, _) = panning();
      addTearDown(s.dispose);
      final overlay = CameraPathOverlay(
        path: CameraPath.of(
          s.requireActiveCut,
          cameraOf(s).cameraFrameSize,
        )!,
        playhead: 0,
        settings: const CameraPathSettings(),
        viewport: CanvasViewport(zoom: zoom),
        standing: standing,
        printedAt: printedAt,
      );
      await tester.pumpWidget(MaterialApp(home: overlay));
      return overlay;
    }

    /// Every size [overlay]'s marks are drawn at: a word's, a stroke's
    /// width, and a cross's arm.
    List<double> sizesOf(CameraPathOverlay overlay) => [
      for (final mark in overlay.marks)
        ...switch (mark) {
          SheetWords(:final size) => [size],
          SheetStroke(:final width, :final points, :final closed) => [
            width,
            if (!closed && points.length == 2)
              (points.last - points.first).distance,
          ],
          _ => const <double>[],
        },
    ];

    Set<double> wordsOf(CameraPathOverlay overlay) => {
      for (final mark in overlay.marks)
        if (mark is SheetWords) mark.size,
    };

    final camera = CameraPose(center: CanvasPoint(x: 960, y: 540));

    testWidgets('at 100% under a camera at 1, the mock\'s sizes with its '
        'words twice; at 200%, twice that; under a camera at 2, half', (
      tester,
    ) async {
      final hundred = await pumpPath(tester, zoom: 1, printedAt: camera);
      expect(
        wordsOf(hundred),
        {24.0},
        reason: 'a key\'s name: the mock\'s 12 twice over',
      );
      final mock = sizesOf(hundred);
      expect(mock, contains(CameraPathOverlay.sizes.frameWidth));

      final twoHundred = await pumpPath(tester, zoom: 2, printedAt: camera);
      expect(sizesOf(twoHundred), [
        for (final size in mock) closeTo(2 * size, 1e-9),
      ]);

      final closer = await pumpPath(
        tester,
        zoom: 1,
        printedAt: camera.copyWith(zoom: 2),
      );
      expect(
        sizesOf(closer),
        [for (final size in mock) closeTo(size / 2, 1e-9)],
        reason: 'the file is the frame: a pixel of it is half the canvas\'s',
      );
    });

    testWidgets('what it does not write keeps the screen\'s size: a path '
        'no export writes, and standing, its crosses in time and the line '
        'its middle walks', (tester) async {
      Future<List<double>> unprinted(double zoom) async =>
          sizesOf(await pumpPath(tester, zoom: zoom, printedAt: null));
      final atHundred = await unprinted(1);
      expect(atHundred, contains(CameraPathOverlay.sizes.labelSize));
      expect(await unprinted(2), [
        for (final size in atHundred) closeTo(size, 1e-9),
      ]);

      /// The crosses in time and the frames beside them, and the dashes of
      /// the line the camera's middle walks — each one's size, as painted.
      Future<({List<double> ticks, List<double> dashes})> stoodOn(
        double zoom,
      ) async {
        final overlay = await pumpPath(
          tester,
          zoom: zoom,
          printedAt: camera,
          standing: true,
        );
        final picture = find.byKey(
          const ValueKey<String>('camera-path-overlay'),
        );
        final canvas = TestRecordingCanvas();
        tester
            .widget<CustomPaint>(picture)
            .painter!
            .paint(canvas, tester.getSize(picture));
        return (
          ticks: [
            for (final mark in overlay.marks)
              if (mark is SheetWords && mark.size != 24 * zoom)
                mark.size
              else if (mark is SheetStroke &&
                  mark.width == CameraPathOverlay.tickWidth)
                mark.width,
          ],
          dashes: [
            for (final call in canvas.invocations)
              if (call.invocation.memberName == #drawPath)
                if (call.invocation.positionalArguments[1] case final Paint ink
                    when ink.color.toARGB32() == AppColors.accent.toARGB32())
                  ink.strokeWidth,
          ],
        );
      }

      final hundred = await stoodOn(1);
      expect(hundred.ticks, isNotEmpty, reason: '⛔전제: crosses in time');
      expect(hundred.dashes, isNotEmpty, reason: '⛔전제: the middle\'s line');
      expect(hundred.ticks, everyElement(isIn([
        CameraPathOverlay.tickLabelSize,
        CameraPathOverlay.tickWidth,
      ])));
      expect(
        hundred.dashes,
        everyElement(closeTo(CameraPathOverlay.centreTrailWidth, 1e-6)),
      );
      final twoHundred = await stoodOn(2);
      expect(twoHundred.ticks, hundred.ticks);
      expect(
        twoHundred.dashes,
        everyElement(closeTo(CameraPathOverlay.centreTrailWidth, 1e-6)),
      );
    });
  });

  testWidgets('its crosses in time wear where the playhead stands — grey '
      'behind it, blue ahead, ink on it — and are painted again as it '
      'moves', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    s.selectFrameIndex(2);
    await pumpArea(tester, s);
    List<int> ticks() => [
      for (final mark in marks(tester))
        if (mark is SheetStroke && mark.width == CameraPathOverlay.tickWidth)
          mark.argb,
    ];
    CustomPainter painter() => tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey<String>('camera-path-overlay')),
        )
        .painter!;

    expect(ticks(), [grey, grey, ink, ink, blue, blue, blue, blue]);
    final before = painter();
    s.selectFrameIndex(3);
    await tester.pump();
    expect(ticks(), [grey, grey, grey, grey, ink, ink, blue, blue]);
    expect(painter().shouldRepaint(before), isTrue);

    await drain(tester);
  });

  testWidgets('a run shows the film: no path while it plays', (tester) async {
    final (s, _) = panning();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(path(), findsOneWidget, reason: '⛔전제');

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(path(), findsNothing);

    s.playbackRig.playback.stop();
    await drain(tester);
  });

  testWidgets('a gap has no cut and no camera: no path in it, as no frame', (
    tester,
  ) async {
    final (s, row) = panning();
    addTearDown(s.dispose);
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.first;
    s.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    s.selectCut(track.cuts[0].id);
    s.standOnRow(LayerRowAddress(row));
    await pumpArea(tester, s);
    expect(path(), findsOneWidget, reason: '⛔전제');

    final gap = track.cuts[0].duration + 1;
    s.frameScrub.scrubGlobalFrame(gap);
    s.frameScrub.scrubGlobalFrame(gap + 1);
    await tester.pump();
    expect(s.editingSession.playheadInGap, isTrue, reason: '⛔전제');
    expect(find.byType(CameraFrameOverlay), findsNothing, reason: '⛔전제');
    expect(path(), findsNothing);

    await drain(tester);
  });

  group('the path is built again', () {
    test('for another track, and kept while the track is the same', () {
      final (s, _) = panning();
      addTearDown(s.dispose);
      final camera = cameraOf(s);
      final size = camera.cameraFrameSize;
      final first = camera.activeCutCameraPath(size);
      expect(first, isNotNull, reason: '⛔전제: the camera moves');
      expect(camera.activeCutCameraPath(size), same(first));

      s.selectFrameIndex(3);
      camera.setCameraKeyframeAtCurrentFrame(camera.cameraPoseAtCurrentFrame);
      final again = camera.activeCutCameraPath(size);
      expect(again, isNot(same(first)));
      expect(again!.keys.map((key) => key.frameIndex), [0, 3, 5]);
    });

    test('for another size of frame, its frames that size', () {
      final (s, _) = panning();
      addTearDown(s.dispose);
      final camera = cameraOf(s);
      final size = camera.cameraFrameSize;
      final whole = camera.activeCutCameraPath(size);
      final half = CanvasSize(width: size.width ~/ 2, height: size.height ~/ 2);
      final halved = camera.activeCutCameraPath(half)!;
      expect(halved, isNot(same(whole)));
      final top = halved.keys.first.corners[1] - halved.keys.first.corners[0];
      expect(
        top.distance,
        closeTo(half.width.toDouble(), 1e-9),
        reason: 'at zoom 1, a frame as wide as it is asked to be',
      );
    });

    test('for its cut\'s canvas resized under the same track', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final row = s.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;
      for (final (frame, percent) in const [(0, '100'), (5, '200')]) {
        s.laneVerbs.setLaneValueAt(
          row,
          'scale',
          frame,
          percent,
          frameIsGlobal: false,
          description: 'Set Scale',
          scaleLinked: true,
        );
      }
      final camera = cameraOf(s);
      final size = camera.cameraFrameSize;
      expect(
        camera.activeCutCameraPath(size),
        isNotNull,
        reason: '⛔전제: a push-in moves the frame',
      );
      final track = camera.activeCutCameraTrack;
      final canvas = s.requireActiveCut.canvasSize;
      // About its middle, by even steps: the picture moves as far as the
      // middle does, so an unkeyed camera stays on it with no key put down
      // (F-362 — from any other anchor, one is).
      s.cutVerbs.resizeActiveCutCanvas(
        CanvasSize(width: canvas.width + 200, height: canvas.height + 100),
        anchor: CanvasResizeAnchor.center,
      );
      expect(
        camera.activeCutCameraTrack,
        same(track),
        reason: '⛔전제: a canvas grown about its middle moves no key',
      );
      expect(
        camera.activeCutCameraPath(size)!.keys.first.corners,
        cameraFrameShownAt(s.requireActiveCut, size, 0),
        reason: 'a camera keyed on no place stands at the middle of the '
            'canvas it has now',
      );
    });
  });
}

/// The collaborator that holds the path's memo, under its own name.
Camera cameraOf(EditorSessionManager session) => session.camera;
