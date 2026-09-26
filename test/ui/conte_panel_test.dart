import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/device_viewport.dart';
import '../helpers/frame_census.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/conte/conte_words_in.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;

/// The conte panel IS the sheet: it draws the renderer the export draws, a
/// cell press picks that cut and frame, and the ACTION text lands on the
/// exposure that opens the cell.
Layer _storyboardLayer(String cutId, Map<int, int> divisions) => Layer(
  id: LayerId('$cutId-sb'),
  name: 'SB',
  kind: LayerKind.storyboard,
  frames: [
    for (final start in divisions.keys)
      Frame(id: FrameId('$cutId-$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final entry in divisions.entries)
      entry.key: TimelineExposure.drawing(
        FrameId('$cutId-${entry.key}'),
        length: entry.value,
      ),
  },
);

Cut _cut(String id, int duration, Map<int, int> divisions) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [_storyboardLayer(id, divisions)],
);

Project _project() => Project(
  id: const ProjectId('conte-project'),
  name: 'Conte',
  createdAt: DateTime.utc(2026, 7, 28),
  tracks: [
    Track(
      id: const TrackId('conte-track'),
      name: 'Video',
      cuts: [
        _cut('39', 10, {0: 5, 5: 5}),
        _cut('40', 12, {0: 12}),
      ],
      seLayers: [
        Layer(
          id: const LayerId('conte-se'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('line-1'),
              duration: 3,
              name: 'いくぞ',
              seName: 'ハヤト',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('line-1'), length: 3),
          },
        ),
      ],
    ),
  ],
);

Future<EditorSessionManager> _pumpConte(
  WidgetTester tester, {
  ConteInkController? inkController,
  ValueListenable<BrushToolState>? brushToolState,
  bool brushAllowed = false,
}) async {
  final session = EditorSessionManager(initialProject: _project());
  addTearDown(session.dispose);
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConteTabHost(
          session: session,
          thumbnails: null,
          // ⚠️An EXPLICIT render 1.0 — this file maps document coordinates
          // to screen offsets one for one, and an uncontrolled panel now
          // opens at the IDENTITY (one document px per DEVICE px), which
          // is 1/3 on the 3x test view.
          viewport: seedFromRender(tester, CanvasViewport()),
          inkController: inkController,
          brushToolState: brushToolState,
          brushAllowed: brushAllowed,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void main() {
  test('the sheet reads the project: cells are panels, the number is the '
      'cut NAME, and dialogue comes off the SE row', () {
    final source = buildConteSheetSource(_project());

    expect(source.cuts.map((cut) => cut.name), ['39', '40']);
    // Cut 39 is divided in two; cut 40 has one panel over the whole of it.
    expect(source.cuts.first.cells, hasLength(2));
    expect(source.cuts.last.cells, hasLength(1));
    expect(source.cuts.first.cells.map((cell) => cell.startFrame), [0, 5]);
    // The line lives on the SE block and prints in the sheet's shape.
    expect(source.cuts.first.dialogue.single.printed, 'ハヤト「いくぞ」');
    expect(source.cuts.first.dialogue.single.startFrame, 2);
    // The running total is the storyboard layout's global frame.
    expect(source.cuts.last.cumulativeEndFrames, 22);
  });

  test('the cover\'s words are the work\'s: its title — the project\'s name '
      'while it has none — its episode, its pictures and its conte artist', () {
    final project = _project();
    expect(buildConteSheetSource(project).title, project.name);

    final source = buildConteSheetSource(
      project.copyWith(
        timesheetInfo: TimesheetInfo.empty
            .copyWith(
              title: 'YOASOBI',
              episode: '#3',
              logoAssetPath: () => 'media/logo.png',
              coverImagePath: () => 'media/cover.png',
            )
            // 유저 답 conte-cover-staff: 「コンテ 한 줄」 — the conte
            // process's own assignee.
            .withStaff(
              LayerProcess.conte.jsonValue,
              const ProductionStaff(name: '大川'),
            ),
      ),
    );
    expect(source.title, 'YOASOBI');
    expect(source.episode, '#3');
    expect(source.logoAssetPath, 'media/logo.png');
    expect(source.coverImagePath, 'media/cover.png');
    expect(source.conteStaffName, '大川');
  });

  testWidgets('the page prints in the NOTATION language the settings name — '
      'not the program\'s', (tester) async {
    // 유저 2026-09-25: 「출력용 언어설정있잖아. 그거따르게하고」.
    final session = await _pumpConte(tester);
    ContePagePainter painter() =>
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey<String>('conte-form-paint')),
                )
                .painter!
            as ContePagePainter;
    expect(
      painter().words,
      conteWordsIn(session.languageSettings.value.notationLanguage),
    );

    session.languageSettings.value = session.languageSettings.value.copyWith(
      notationLanguage: AppLanguage.ko,
      programLanguage: AppLanguage.en,
    );
    tester.element(find.byType(ConteTabHost)).markNeedsBuild();
    await tester.pump();

    expect(painter().words, conteWordsIn(AppLanguage.ko));
    expect(
      painter().marks().whereType<SheetWords>().map((word) => word.text),
      containsAll(['내용', '대사']),
    );
  });

  testWidgets('the panel opens on the body\'s first page — the cover and its '
      'blank back a turn away, each read for what it is', (tester) async {
    await _pumpConte(tester);

    expect(find.byKey(const ValueKey<String>('conte-form-paint')), findsOneWidget);
    // Three cells over two cuts: ONE body page, and the book around it
    // (유저 2026-09-25: 「1페이지는 표지, 2페이지는 … 빈용지, 3페이지부터 콘티
    // 본 페이지」).
    String readout() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('conte-page-readout')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(readout(), '1 / 1', reason: 'the number the page prints');

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-previous-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(), AppText.strings.cnPageBlank);
    await tester.tap(
      find.byKey(const ValueKey<String>('conte-previous-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(), AppText.strings.cnPageCover);

    // Typing reads the readout's own spelling: 1 is the BODY's first page,
    // not the first sheet of paper.
    await tester.tap(find.byKey(const ValueKey<String>('conte-page-readout')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('conte-page-input')),
      '1',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(readout(), '1 / 1');
  });

  testWidgets('a cell\'s picture picks its cut and frame; a tap on its '
      'ACTION edits the words ON the paper, and they land on the exposure '
      'that opens the cell', (tester) async {
    final session = await _pumpConte(tester);
    session.selectCut(const CutId('40'));
    await tester.pumpAndSettle();

    // The second cell of cut 39 — press its picture, through the shell's
    // viewport (identity at rest: document space = content-local space).
    final source = buildConteSheetSource(session.repository.requireProject());
    final pages = layoutConteSheet(
      source,
      metrics: ConteSheetMetrics(cameraAspect: session.camera.cameraFrameAspect),
    );
    final metrics = pages.first.metrics;
    final cell = pages.first.cells.firstWhere(
      (cell) => cell.cutId == '39' && cell.cellIndex == 1,
    );
    final pageTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('conte-form-paint')),
    );
    await tester.tapAt(pageTopLeft + cell.pictureRect.center);
    await tester.pumpAndSettle();

    expect(session.activeCutOrNull?.id, const CutId('39'));
    expect(session.editingFrameCursor.value, 5);
    // Nothing mounted under the page for it (유저 2026-09-25: 「해당 칸
    // 누르면 텍스트 편집」 — the field that used to appear below is gone).
    expect(
      find.byKey(const ValueKey<String>('conte-action-field')),
      findsNothing,
    );

    // The cell's own rows of the ACTION column.
    final action = Rect.fromLTRB(
      cell.actionRect.left,
      metrics.rowTop(cell.rowOnPage),
      cell.actionRect.right,
      metrics.rowTop(cell.rowOnPage + cell.source.rowSpan),
    );
    await tester.tapAt(pageTopLeft + action.center);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey<String>('conte-action-field'));
    expect(field, findsOneWidget);
    expect(
      action.contains(tester.getCenter(field) - pageTopLeft),
      isTrue,
      reason: 'the field sits on the cell\'s own ACTION, on the paper',
    );
    // It types in the face, size and ink the sheet prints (zoom 1 at
    // rest), so the words break while typing where they break on paper.
    final typed = tester.widget<TextField>(field).style!;
    expect(typed.fontFamily, AppTypography.bundledFamily);
    expect(typed.fontSize, conteCellTextSize);
    expect(typed.color, const Color(conteInkArgb));
    await tester.enterText(field, 'ハヤト走る');
    // A tap away commits, as on the timesheet.
    await tester.tapAt(pageTopLeft + const Offset(5, 5));
    await tester.pumpAndSettle();

    final layer = storyboardLayerForCut(session.requireActiveCut)!;
    expect(layer.timeline[5]!.memo?.actionMemo, 'ハヤト走る');
    // And the sheet reads it back where the cell is.
    expect(
      buildConteSheetSource(
        session.repository.requireProject(),
      ).cuts.first.cells.last.action,
      'ハヤト走る',
    );
  });

  // H40 ② (2026-09-24): the ink layer was rebuilt on every brush change —
  // each frame of a settings slider drag. Its windows read the brush when a
  // stroke starts now, so a change reaches none of them.
  testWidgets('a brush change rebuilds no ink window, and the windows read '
      'the brush in hand', (tester) async {
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brush.dispose);
    await _pumpConte(
      tester,
      inkController: ink,
      brushToolState: brush,
      brushAllowed: true,
    );
    expect(find.byType(ConteInkLayer), findsOneWidget);

    final next = brush.value.copyWith(size: 40, color: 0xFF336699);
    final census = await frameCensus(tester, () => brush.value = next);

    expect(census.rebuilt, isNot(contains(ConteInkLayer)));
    expect(census.rebuilt, isNot(contains(InteractiveBrushEditCanvasView)));
    final windows = tester.widgetList<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    expect(windows, isNotEmpty);
    for (final window in windows) {
      expect(window.inputSettings(), next.toInputSettings());
    }
  });

  testWidgets('R5: a stroke on a cell\'s row band lands on that CELL\'s ink '
      'surface (block-FrameId key); the margins land on the page plane — '
      'one undo clears each, through the app history', (
    tester,
  ) async {
    final source = buildConteSheetSource(_project());
    final pages = layoutConteSheet(
      source,
      metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
    );
    final page = pages.first;
    final metrics = page.metrics;
    final controller = ConteInkController();
    controller.syncGeometry(metrics);
    final historyManager = HistoryManager();
    final strokeActive = ValueNotifier<bool>(false);
    addTearDown(strokeActive.dispose);

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
                controller: controller,
                page: page,
                brushToolState: ValueNotifier(BrushToolState.defaults),
                historyManager: historyManager,
                // ⛔NOT `seedFromRender`. The device-unit rule is
                // `BrushCanvasPanel`'s boundary and the hosts that forward
                // to it; this is a LEAF that paints, so it takes the logical
                // viewport every painter takes.
                viewport: CanvasViewport(),
                strokeActive: strokeActive,
              ),
            ),
          ),
        ),
      ),
    );

    final firstCell = page.cells.first;
    final rowKey = conteInkRowKey(
      CutId(firstCell.cutId),
      firstCell.source.frameId!,
    );
    final page0 = conteInkPageKey(0);
    expect(controller.hasInkFor(ConteInkPlane.row, rowKey), isFalse);
    expect(controller.hasInkFor(ConteInkPlane.page, page0), isFalse);

    // (120,120) → (180,150) lies inside the first cell's row band: the
    // stroke lands on ITS surface.
    final layerBox = tester.getTopLeft(find.byType(ConteInkLayer));
    final gesture = await tester.startGesture(
      layerBox + const Offset(120, 120),
      pointer: 7,
    );
    await tester.pump();
    expect(strokeActive.value, isTrue, reason: 'nav holds during strokes');
    await gesture.moveTo(layerBox + const Offset(180, 150));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(strokeActive.value, isFalse);

    expect(controller.hasInkFor(ConteInkPlane.row, rowKey), isTrue);
    expect(
      controller.hasInkFor(ConteInkPlane.page, page0),
      isFalse,
      reason: 'the band shows every spot of it; the paper got nothing',
    );

    // The band above the table: paper-anchored, the page plane's.
    final headerStroke = await tester.startGesture(
      layerBox + Offset(120, metrics.topBandTop + 10),
      pointer: 8,
    );
    await tester.pump();
    await headerStroke.moveTo(
      layerBox + Offset(200, metrics.topBandTop + 14),
    );
    await tester.pump();
    await headerStroke.up();
    await tester.pump();
    expect(controller.hasInkFor(ConteInkPlane.page, page0), isTrue);

    // App-history undo parity, per plane, newest first.
    historyManager.undo();
    expect(controller.hasInkFor(ConteInkPlane.page, page0), isFalse);
    expect(controller.hasInkFor(ConteInkPlane.row, rowKey), isTrue);
    historyManager.undo();
    expect(controller.hasInkFor(ConteInkPlane.row, rowKey), isFalse);
    historyManager.redo();
    expect(controller.hasInkFor(ConteInkPlane.row, rowKey), isTrue);
  });

  // 🚨ONE PAPER (유저 2026-09-25: 「진짜 하나의 용지처럼. 데이터는
  // 나누더라도」): the stroke used to belong to the window it started in
  // and ran on over the cells below it, in the paper's ink.
  testWidgets('one paper: a stroke from the band above the table down into '
      'a cell leaves the paper and the cell each its piece — ONE undo', (
    tester,
  ) async {
    final source = buildConteSheetSource(_project());
    final page = layoutConteSheet(
      source,
      metrics: const ConteSheetMetrics(cameraAspect: 16 / 9),
    ).first;
    final metrics = page.metrics;
    final controller = ConteInkController()..syncGeometry(metrics);
    addTearDown(controller.dispose);
    final historyManager = HistoryManager();
    final strokeActive = ValueNotifier<bool>(false);
    addTearDown(strokeActive.dispose);
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
                controller: controller,
                page: page,
                brushToolState: ValueNotifier(BrushToolState.defaults),
                historyManager: historyManager,
                viewport: CanvasViewport(),
                strokeActive: strokeActive,
              ),
            ),
          ),
        ),
      ),
    );

    final firstCell = page.cells.first;
    final windows = conteInkWindows(page);
    final paper = windows.singleWhere(
      (window) => window.key == conteInkPageKey(0),
    );
    final cell = windows.singleWhere(
      (window) =>
          window.key ==
          conteInkRowKey(CutId(firstCell.cutId), firstCell.source.frameId!),
    );
    bool inkUnder(SheetInkWindow window, Offset at) {
      final surface = controller
          .sessionStateFor(window.plane! as ConteInkPlane, window.key)
          .canvasState
          .currentSurface;
      final pixel = window.placement.pixelOf(at);
      return (surfacePixelRgba(
                surface,
                pixel.dx.floor(),
                pixel.dy.floor(),
              ) ??
              0) !=
          0;
    }

    final start = Offset(120, metrics.topBandTop + 10);
    const end = Offset(120, 120);
    final layerBox = tester.getTopLeft(find.byType(ConteInkLayer));
    final gesture = await tester.startGesture(layerBox + start, pointer: 7);
    await tester.pump();
    await gesture.moveTo(layerBox + (start + end) / 2);
    await tester.pump();
    await gesture.moveTo(layerBox + end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(inkUnder(paper, start), isTrue);
    expect(inkUnder(cell, end), isTrue);
    expect(
      inkUnder(paper, end),
      isFalse,
      reason: 'the cell shows that spot, so the cell keeps it',
    );

    historyManager.undo();
    expect(controller.hasInkFor(ConteInkPlane.page, paper.key), isFalse);
    expect(controller.hasInkFor(ConteInkPlane.row, cell.key), isFalse);
  });
}
