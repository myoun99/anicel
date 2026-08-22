import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show
        LaneRowSubject,
        LayerRowSubject,
        TrackRowSubject,
        timelineRowAddressOfDragSubject;
import 'package:anicel/src/models/timeline_row_address.dart';

/// 🚨A5-3② (유저 2026-08-22) — **THE STORYBOARD SELECTS BEFORE IT MOVES.**
///
/// > 「스토리보드패널에서는 되긴 하는데 **통일이 안 돼 있다** — 선택범위로
/// > 선택하고 이동하는 게 규칙인데 **그냥 바로 드래그 작동**해버림」
///
/// ⑨'s law is ONE law: the first drag SELECTS, and a drag that starts INSIDE
/// the selection moves it — the cells' grammar transposed onto rows. It was
/// never the timeline's own, and both rails draw cells.
///
/// ⚠️The rail did not have a rule of its own to delete. Its hooks for the
/// selection phase are OPTIONAL and it passed null for every one of them,
/// and null means "this surface takes no part in row selection at all" — so
/// the press skipped the first phase entirely. The same shape as H12, D8-2
/// and B4-3: the law was already right and one surface was not using it.
///
/// 🚨What this file pins is the WIRING, deliberately. The behaviour behind
/// it (select-then-move) already has its own coverage on the timeline, and
/// re-driving a pointer here would test the shared drag widget a third time
/// while leaving the actual defect — a null hook — invisible. The hooks are
/// exercised, not merely counted: each is CALLED and its answer checked, so
/// a hook wired to something that cannot answer still fails.
void main() {
  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 6,
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

  Project project() => Project(
    id: const ProjectId('sb-select-first'),
    name: 'SB',
    createdAt: DateTime.utc(2026, 8, 22),
    tracks: [
      Track(
        id: const TrackId('sb-track'),
        name: 'Video',
        cuts: [cut('cut-1')],
        seLayers: [
          Layer(
            id: const LayerId('se-row-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: const [],
            timeline: const {},
          ),
          Layer(
            id: const LayerId('se-row-2'),
            name: 'S2',
            kind: LayerKind.se,
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
    ],
  );

  Future<StoryboardPanel> pumpStoryboard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    return tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
  }

  testWidgets("the rail's row drag knows about the row selection at all",
      (tester) async {
    final panel = await pumpStoryboard(tester);
    final hooks = panel.rowDragHooks;
    expect(hooks, isNotNull, reason: 'presence first');

    // ⛔`isInRowSelection` returning NULL is the defect, and it is not the
    // same as returning false: null means "this subject does not take part
    // in row selection", which is how the whole select phase was skipped.
    const subject = LayerRowSubject(LayerId('se-row-1'));
    expect(
      hooks!.isInRowSelection!(subject),
      isFalse,
      reason: 'nothing is selected yet, so a press here must START a '
          'selection rather than go straight to the move (A5-3②)',
    );
    expect(hooks.onSelectBegin, isNotNull);
    expect(hooks.onSelectEnd, isNotNull);
    expect(
      panel.onSeRowSelectionSpan,
      isNotNull,
      reason: 'arming without the span would select one row and then refuse '
          'to grow — half a law is not the law',
    );
  });

  testWidgets('arming really selects, and the drag that follows is then '
      'INSIDE the selection', (tester) async {
    final panel = await pumpStoryboard(tester);
    final hooks = panel.rowDragHooks!;
    const subject = LayerRowSubject(LayerId('se-row-1'));

    hooks.onSelectBegin!(subject);
    await tester.pump();
    expect(
      hooks.isInRowSelection!(subject),
      isTrue,
      reason: 'the first drag selected it — so the NEXT drag on this row is '
          'the move, which is the whole of ⑨',
    );
    hooks.onSelectEnd!();
  });

  testWidgets('every subject the rail can raise has a name in the '
      "selection's own words", (tester) async {
    final panel = await pumpStoryboard(tester);
    final hooks = panel.rowDragHooks!;
    // The mapper moved out of the timeline host so BOTH rails could reach
    // it; a subject with no address is exactly what made this rail unable
    // to offer selection in the first place. Asking each kind here keeps a
    // new subject from quietly reintroducing that hole.
    expect(
      hooks.isInRowSelection!(const LayerRowSubject(LayerId('se-row-2'))),
      isFalse,
    );
    expect(
      hooks.isInRowSelection!(const LaneRowSubject(LayerId('se-row-1'), 'x')),
      isFalse,
    );

    // ⛔THE V ROWS ARE OUT, and null is the hook's own word for it. A5-3 is
    // about the S rows (「se트랙은 트랙끼리 드래그이동」); putting a track
    // reorder behind a select step is a change to a different gesture that
    // nobody asked for, and the track-reorder pins caught it the moment
    // this hook answered unconditionally.
    expect(
      hooks.isInRowSelection!(const TrackRowSubject(TrackId('sb-track'))),
      isNull,
      reason: 'null is "takes no part in row selection" — a V row still '
          'moves on the FIRST drag, which is what it always did',
    );
    // Naming is still universal even where selecting is not: the shared map
    // answers for every subject, which is what let this rail offer the
    // phase at all.
    expect(
      timelineRowAddressOfDragSubject(
        const TrackRowSubject(TrackId('sb-track')),
      ),
      const TrackRowAddress(TrackId('sb-track')),
    );
  });
}
