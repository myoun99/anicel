import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

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

Future<EditorSessionManager> _pumpConte(WidgetTester tester) async {
  final session = EditorSessionManager(initialProject: _project());
  addTearDown(session.dispose);
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ConteTabHost(session: session, thumbnailFor: null)),
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

  testWidgets('the panel draws a page inside the canvas shell, and a '
      'ONE-page conte offers nothing to turn', (tester) async {
    await _pumpConte(tester);

    expect(find.byKey(const ValueKey<String>('conte-page')), findsOneWidget);
    // Three cells over two cuts: one page.
    //
    // 유저 확정 ⑥ (2026-08-13): the page cluster left the pill for a capsule
    // on the left edge, and that capsule appears only where there is a page
    // to turn TO. It used to read "1 / 1" — a control that could do nothing,
    // standing in a row that was shedding controls that could.
    expect(
      find.byKey(const ValueKey<String>('canvas-page-strip')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('conte-page-readout')),
      findsNothing,
    );
  });

  testWidgets('a cell press picks its cut and frame, and the ACTION text '
      'lands on the exposure that opens the cell', (tester) async {
    final session = await _pumpConte(tester);
    session.selectCut(const CutId('40'));
    await tester.pumpAndSettle();

    // The second cell of cut 39 — press its picture, through the shell's
    // viewport (identity at rest: document space = content-local space).
    final source = buildConteSheetSource(session.repository.requireProject());
    final pages = layoutConteSheet(
      source,
      metrics: ConteSheetMetrics(cameraAspect: session.cameraFrameAspect),
    );
    final cell = pages.first.cells.firstWhere(
      (cell) => cell.cutId == '39' && cell.cellIndex == 1,
    );
    final pageTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('conte-page')),
    );
    await tester.tapAt(pageTopLeft + cell.pictureRect.center);
    await tester.pumpAndSettle();

    expect(session.activeCutOrNull?.id, const CutId('39'));
    expect(session.editingFrameCursor.value, 5);

    await tester.enterText(
      find.byKey(const ValueKey<String>('conte-action-field')),
      'ハヤト走る',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
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

  testWidgets('R5: a stroke STARTING on a cell\'s row band lands on that '
      'CELL\'s ink surface (block-FrameId key); the margins land on the '
      'page plane — one undo clears each, through the app history', (
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
                brushToolState: BrushToolState.defaults,
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
    final rowKey = ConteInkController.rowKey(
      CutId(firstCell.cutId),
      firstCell.source.frameId!,
    );
    final page0 = ConteInkController.pageKey(0);
    expect(controller.hasInkFor(ConteInkPlane.row, rowKey), isFalse);
    expect(controller.hasInkFor(ConteInkPlane.page, page0), isFalse);

    // (120,120) sits inside the first cell's row band: the stroke binds
    // to ITS surface — the start cell owns the whole stroke.
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
      reason: 'the band claimed the stroke; the paper got nothing',
    );

    // The header sits above the body: paper-anchored, the page plane's.
    final headerStroke = await tester.startGesture(
      layerBox + Offset(120, metrics.margin + 10),
      pointer: 8,
    );
    await tester.pump();
    await headerStroke.moveTo(layerBox + Offset(200, metrics.margin + 14));
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
}
