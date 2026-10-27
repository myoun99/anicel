import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_strata.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// 🚨THE SHEET PRINTS A DRAG ONLY WHERE IT SHOWS (F-244-sheet-print).
///
/// The values' print was the whole document's cells, so a block dragged
/// on rows the panel did not show re-printed the sheet at every step — its
/// bake standing down for a picture that stayed the same (measured on the
/// Surface, 10-27: the panel's pixels hashed the same at every step). The
/// print is the paint's own walk now: what the view reaches.
///
/// Read off the values' bake: standing down is the sheet re-printing them
/// at each step, and a capture is it re-recording them.
void main() {
  const cutId = CutId('cut-1');

  Layer cels(Map<int, TimelineExposure> timeline) => Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: <Frame>[
      Frame(id: const FrameId('a-f1'), duration: 1, strokes: const []),
    ],
    timeline: timeline,
  );
  final everySix = <int, TimelineExposure>{
    for (var frame = 0; frame < 240; frame += 6)
      frame: const TimelineExposure.drawing(FrameId('a-f1'), length: 6),
  };

  Layer se(String dialogue) => Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: <Frame>[
      Frame(
        id: const FrameId('se-f1'),
        duration: 1,
        name: dialogue,
        seName: 'SE',
        strokes: const [],
      ),
    ],
    timeline: <int, TimelineExposure>{
      0: const TimelineExposure.drawing(FrameId('se-f1'), length: 240),
    },
  );

  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: cutId,
      name: '1',
      duration: 240,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: <Layer>[cels(everySix)],
    ),
    projectName: 'P',
    fps: 24,
    trackSeLayers: [se('あいうえおかきくけこ')],
  );
  final layout = TimesheetDocumentLayout(document: document);
  final secondPage = document.pages[1];

  /// A drag on the cels that leaves [frame]'s drawing three frames short.
  TimelineDragPreview shortened(int frame) => ExposureEdgeDragPreview(
    previewLayer: cels({
      ...everySix,
      frame: const TimelineExposure.drawing(FrameId('a-f1'), length: 3),
    }),
  );

  /// The view with [page]'s first rows at its top.
  CanvasViewport onRowsOf(int page) => CanvasViewport(
    panX: 40 - layout.halfLeft(page, 0),
    panY: -(layout.halfRowsTop(page) - 20),
    zoom: 1,
  );

  late ValueNotifier<TimelineDragPreview?> drag;
  late ValueNotifier<CanvasViewport> view;
  late ValueNotifier<Size> box;

  Future<void> mount(WidgetTester tester, CanvasViewport at) async {
    drag = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(drag.dispose);
    view = ValueNotifier<CanvasViewport>(at);
    addTearDown(view.dispose);
    box = ValueNotifier<Size>(const Size(360, 320));
    addTearDown(box.dispose);
    final stroking = ValueNotifier<bool>(false);
    addTearDown(stroking.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ListenableBuilder(
            listenable: Listenable.merge([view, box]),
            builder: (context, _) => SizedBox.fromSize(
              size: box.value,
              child: TimesheetStrata(
                layout: layout,
                viewport: view.value,
                words: timesheetWordsIn(AppLanguage.en),
                dragPreview: drag,
                cutId: cutId,
                stroking: stroking,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderStaticRaster values(WidgetTester tester) => tester
      .renderObjectList<RenderStaticRaster>(find.byType(StaticRaster))
      .singleWhere((raster) => raster.debugLabel == 'timesheet-content');

  Future<void> step(WidgetTester tester, TimelineDragPreview? preview) async {
    drag.value = preview;
    await tester.pumpAndSettle();
  }

  test('⛔premise: each drag below moves cells of the sheet', () {
    final column = document.columns.firstWhere(
      (column) => column.layerId == const LayerId('a'),
    );
    for (final frame in [6, secondPage.startFrame + 6]) {
      expect(
        timesheetColumnCellsShowing(column, shortened(frame)),
        isNot(column.cells),
      );
    }
  });

  testWidgets('a drag on rows the view does not reach prints nothing — the '
      'values stay baked', (tester) async {
    await mount(tester, onRowsOf(0));
    final captures = values(tester).captureCount;
    expect(captures, greaterThan(0), reason: 'fixture: the values bake');

    for (final frame in [secondPage.startFrame + 6, secondPage.startFrame + 12]) {
      await step(tester, shortened(frame));
      expect(values(tester).standDown, StandDownReason.none);
    }
    expect(
      values(tester).captureCount,
      captures,
      reason: 'nothing the sheet shows moved: nothing re-records',
    );
  });

  testWidgets('a drag on rows in view re-prints them at each step', (
    tester,
  ) async {
    await mount(tester, onRowsOf(0));
    await step(tester, shortened(6));
    expect(values(tester).standDown, StandDownReason.disabled);

    await step(tester, null);
    expect(values(tester).standDown, StandDownReason.none);
  });

  testWidgets('the view panned onto a drag\'s rows mid-drag prints it — and '
      'panned off, stops', (tester) async {
    await mount(tester, onRowsOf(0));
    await step(tester, shortened(secondPage.startFrame + 6));
    expect(values(tester).standDown, StandDownReason.none);

    view.value = onRowsOf(1);
    await tester.pumpAndSettle();
    expect(
      values(tester).standDown,
      StandDownReason.disabled,
      reason: 'the rows the drag moves are on screen now',
    );

    view.value = onRowsOf(0);
    await tester.pumpAndSettle();
    expect(values(tester).standDown, StandDownReason.none);
  });

  testWidgets('a box grown onto a drag\'s rows mid-drag prints it', (
    tester,
  ) async {
    await mount(tester, onRowsOf(0));
    // Rows 27-29 of the page go empty: the box reaches row 17, its slack
    // row included, and the grown one row 30 (the test window is 600 tall).
    const row = 24;
    await step(tester, shortened(row));
    expect(values(tester).standDown, StandDownReason.none);

    box.value = const Size(360, 560);
    await tester.pumpAndSettle();
    expect(values(tester).standDown, StandDownReason.disabled);
  });

  // F-165: the half an SE entry runs on into writes its share of the words
  // from row 0 — read off the entry's START, which may lie on a page the
  // view does not reach.
  testWidgets('a drag that changes only an SE entry\'s start, off screen, '
      're-prints the share of its words on screen', (tester) async {
    final column = document.columns.firstWhere(
      (column) => column.kind == TimesheetColumnKind.se,
    );
    final retold = ExposureEdgeDragPreview(previewLayer: se('さしすせそ'));
    final cells = timesheetColumnCellsShowing(column, retold);
    expect(
      cells.sublist(secondPage.startFrame),
      column.cells.sublist(secondPage.startFrame),
      reason: '⛔premise: no cell of the page in view changes',
    );
    expect(cells.first, isNot(column.cells.first), reason: '⛔premise');

    await mount(tester, onRowsOf(1));
    await step(tester, retold);
    expect(values(tester).standDown, StandDownReason.disabled);
  });
}
