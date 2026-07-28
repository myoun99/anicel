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
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

/// SE globalization: the cut-internal timeline's track-SE rows are
/// open-ended on the right — the runway past the cut end shows the
/// NEIGHBOURS' sounds, editable like any other block. The `~` mark keeps
/// meaning exactly "this block crosses the current cut's end".
Cut _cut(String id, int duration) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ],
);

Frame _frame(String id, String name, int length) =>
    Frame(id: FrameId(id), duration: length, name: name, strokes: const []);

/// cut-1 [0,8), cut-2 [8,14). SE: one inside cut 1, one crossing the
/// boundary, one inside cut 2 (global 10 — BEYOND cut-1's end).
Project _project() => Project(
  id: const ProjectId('se-global-project'),
  name: 'SE Global',
  createdAt: DateTime.utc(2026, 7, 29),
  tracks: [
    Track(
      id: const TrackId('se-global-track'),
      name: 'Video',
      cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
      seLayers: [
        Layer(
          id: const LayerId('se-row-1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            _frame('f-one', 'One!', 3),
            _frame('f-cross', 'Cross!', 4),
            _frame('f-two', 'Two!', 2),
            _frame('f-far', 'Far!', 2),
          ],
          timeline: {
            1: const TimelineExposure.drawing(FrameId('f-one'), length: 3),
            6: const TimelineExposure.drawing(FrameId('f-cross'), length: 4),
            10: const TimelineExposure.drawing(FrameId('f-two'), length: 2),
            16: const TimelineExposure.drawing(FrameId('f-far'), length: 2),
          },
        ),
      ],
    ),
  ],
);

Future<EditorSessionManager> _openTimeline(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
      .session;
}

void main() {
  testWidgets('the NEXT cut\'s sound shows on the runway past the cut end '
      '(the end clip is gone) — and earns no crossing mark of its own', (
    tester,
  ) async {
    await _openTimeline(tester);

    // Cut-1 active (8 frames): the cut-2 sound at global 10 used to be
    // dropped by the display window; now it renders on the runway at its
    // rebased display start (10 — the cut start is 0 here).
    expect(
      find.byKey(const ValueKey<String>('timeline-se-label-se-row-1-10')),
      findsOneWidget,
    );
    // The crossing mark stays exactly one, on the block that CROSSES the
    // boundary — a block wholly beyond it is not "crossing".
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-row-1-end')),
      findsOneWidget,
    );
  });

  testWidgets('editing a runway block from the cut-internal timeline lands '
      'on the RIGHT global block — the neighbour cut\'s sound resizes', (
    tester,
  ) async {
    final session = await _openTimeline(tester);

    // The cut-2 sound sits at display key 10 (global 10, cut start 0).
    // Comma-drag its end through the timeline's own verb funnel.
    expect(
      session.beginExposureEdgeDrag(
        layerId: const LayerId('se-row-1'),
        blockStartIndex: 10,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: 'the runway block is a real, editable block now',
    );
    session.updateExposureEdgeDrag(2);
    session.endExposureEdgeDrag();
    await tester.pumpAndSettle();

    final global = session.repository
        .requireProject()
        .tracks
        .single
        .seLayers
        .single;
    expect(global.timeline[10]!.length, 4, reason: '2 frames longer');
    expect(global.timeline[6]!.length, 4, reason: 'the neighbour untouched');
  });

  testWidgets('the X-sheet carries the same crossing mark (the shared row '
      'mount) — pinned here because no test read the xsheet key before', (
    tester,
  ) async {
    await _openTimeline(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('xsheet-se-crossing-se-row-1-end')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-se-label-se-row-1-10')),
      findsOneWidget,
      reason: 'the runway block rides the transposed axis too',
    );
  });

  testWidgets('pull slack on a track-SE row measures ONE axis — the commit '
      'layer against the global anchor. Mixing them read zero slack in any '
      'cut past the first (the pull verb was silently dead there)', (
    tester,
  ) async {
    final session = await _openTimeline(tester);
    session.selectCut(const CutId('cut-2'));
    session.selectFrameIndex(4); // global 12 — cut-2 starts at 8
    await tester.pumpAndSettle();

    // The sound at global 16: pulling from the playhead may close the 4
    // frames down to the wall at 12 (the [10,12) sound's end). The mixed-
    // axis slack measured display-clone keys against the global anchor
    // and read 0 here — the verb stood down with real room on the row.
    const seRow = LayerRowAddress(LayerId('se-row-1'));
    expect(
      session.framePullSlack(currentRow: seRow),
      4,
      reason: 'global 16 may travel to 12, where the previous sound ends',
    );

    session.pullFrames(9, currentRow: seRow);
    await tester.pumpAndSettle();

    final global = session.repository
        .requireProject()
        .tracks
        .single
        .seLayers
        .single;
    expect(
      global.timeline[12],
      isNotNull,
      reason: 'pulled by the slack (4), stopping at the wall — not past it',
    );
    expect(global.timeline[16], isNull);
    expect(
      global.timeline[10]!.length,
      2,
      reason: 'the block before the anchor never moves',
    );
    expect(global.timeline[6]!.length, 4);
  });
}
