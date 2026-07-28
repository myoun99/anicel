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

  testWidgets('the panel draws a page and steps through pages', (tester) async {
    await _pumpConte(tester);

    expect(find.byKey(const ValueKey<String>('conte-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conte-page-readout')),
      findsOneWidget,
    );
    // Three cells over two cuts: one page.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('conte-page-readout')),
          )
          .data,
      '1 / 1',
    );
  });

  testWidgets('a cell press picks its cut and frame, and the ACTION text '
      'lands on the exposure that opens the cell', (tester) async {
    final session = await _pumpConte(tester);
    session.selectCut(const CutId('40'));
    await tester.pumpAndSettle();

    // The second cell of cut 39 — press its picture.
    final page = find.byKey(const ValueKey<String>('conte-page'));
    final box = tester.getRect(page);
    // Cell 2 of cut 39 sits on the sheet's second row.
    await tester.tapAt(
      Offset(box.left + box.width * 0.35, box.top + box.height * 0.32),
    );
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
}
