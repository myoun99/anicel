import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// 🚨F-244: AN EDIT KEEPS EVERY X-SHEET COLUMN IT LEFT ALONE.
///
/// The timeline's rows kept theirs (`zoom_does_not_rebuild_rows_test`,
/// `timeline_row_memo_test`); the x-sheet built every column again at every
/// commit — and every bucket crossing — the same row turned on its side
/// with nothing kept. Both keep a row by one reading of what it shows now
/// ([keptTimelineCellsRow]), so an edit to one layer hands every other
/// column back as the widget it already was.
void main() {
  Project project() => Project(
    id: const ProjectId('kept-rows'),
    name: 'Kept rows',
    createdAt: DateTime.utc(2026, 9, 30),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: 96,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (final row in const ['a', 'b', 'c', 'd'])
                Layer(
                  id: LayerId(row),
                  name: row.toUpperCase(),
                  frames: [
                    for (var i = 0; i < 8; i += 1)
                      Frame(
                        id: FrameId('$row-$i'),
                        duration: 1,
                        strokes: const [],
                        name: '${i + 1}',
                      ),
                  ],
                  timeline: {
                    for (var i = 0; i < 8; i += 1)
                      i * 6: TimelineExposure.drawing(
                        FrameId('$row-$i'),
                        length: 6,
                      ),
                  },
                ),
            ],
          ),
        ],
      ),
    ],
  );

  Map<String, TimelineFrameCellsRow> columns(WidgetTester tester) => {
    for (final row in tester.widgetList<TimelineFrameCellsRow>(
      find.byType(TimelineFrameCellsRow),
    ))
      row.baseLayer!.id.value: row,
  };

  testWidgets('a comma drag released on B hands the x-sheet\'s A, C and D '
      'columns back as they were', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(XSheetTimelineGrid),
      findsOneWidget,
      reason: 'premise: the x-sheet is up',
    );
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final before = columns(tester);
    expect(
      before.keys,
      containsAll(const ['a', 'b', 'c', 'd']),
      reason: 'premise: every layer has its cells column on screen',
    );

    expect(
      session.edgeDrag.beginExposureEdgeDrag(
        layerId: const LayerId('b'),
        blockStartIndex: 12,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: 'premise: the block is there to grab',
    );
    session.edgeDrag.updateExposureEdgeDrag(2);
    await tester.pump();
    session.edgeDrag.endExposureEdgeDrag();
    await tester.pumpAndSettle();

    final after = columns(tester);
    expect(
      identical(after['b'], before['b']),
      isFalse,
      reason: 'premise: the edit reached the column it changed',
    );
    for (final untouched in const ['a', 'c', 'd']) {
      expect(
        identical(after[untouched], before[untouched]),
        isTrue,
        reason: 'column $untouched showed nothing the edit changed',
      );
    }
  });
}
