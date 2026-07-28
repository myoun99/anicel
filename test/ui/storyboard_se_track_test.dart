import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/home_page.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';
import 'package:quick_animaker_v2/src/ui/timeline/dialogue_fit_text.dart';

Cut _cut(String id, int duration) {
  return Cut(
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
}

/// A point on the storyboard's CUT row over [globalFrame] — the row that
/// owns cuts, and so the one that takes one active.
Offset _storyboardCutRowPoint(WidgetTester tester, {required int globalFrame}) {
  final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
  final row = find.byKey(
    const ValueKey<String>('storyboard-track-timeline-area-sb-se-track'),
  );
  final topLeft = tester.getTopLeft(row);
  return Offset(
    topLeft.dx + (globalFrame + 0.5) * panel.pixelsPerFrame,
    topLeft.dy + tester.getSize(row).height / 2,
  );
}

Frame _frame(String id, String name, int length) =>
    Frame(id: FrameId(id), duration: length, name: name, strokes: const []);

/// TRACK-owned SE row on the global frame axis: an entry inside cut 1, an
/// entry CROSSING the cut-1→cut-2 boundary (frame 8), and one inside
/// cut 2.
Project _project() {
  return Project(
    id: const ProjectId('sb-se-project'),
    name: 'SB SE Project',
    createdAt: DateTime.utc(2026, 7, 8),
    tracks: [
      Track(
        id: const TrackId('sb-se-track'),
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
            ],
            timeline: {
              1: const TimelineExposure.drawing(FrameId('f-one'), length: 3),
              6: const TimelineExposure.drawing(FrameId('f-cross'), length: 4),
              10: const TimelineExposure.drawing(FrameId('f-two'), length: 2),
            },
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
}

void main() {
  testWidgets("tapping an S-row label selects that row of the STORYBOARD's "
      "rail — and leaves the CUT's row selection alone", (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    // Nothing picked yet: the rail rests on the V row.
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-track-label-row-sb-se-track'),
        ),
        matching: find.byKey(
          const ValueKey<String>('storyboard-selected-row'),
        ),
      ),
      findsOneWidget,
    );

    // Tap the row's NAME (the row also carries controls; the text is the
    // safe dead zone, like the timeline label tests).
    final label = find.byKey(
      const ValueKey<String>('storyboard-se-label-sb-se-track-1'),
    );
    await tester.tap(find.descendant(of: label, matching: find.text('S1')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: label,
        matching: find.byKey(const ValueKey<String>('storyboard-selected-row')),
      ),
      findsOneWidget,
    );
    // ONE row is selected, never two: the V row let go the moment the S
    // row took it.
    expect(
      find.byKey(const ValueKey<String>('storyboard-selected-row')),
      findsOneWidget,
    );

    // The TIMELINE does not follow: its rail shows the CUT's row — the
    // drawing target, which this pick has no business moving (the two row
    // selections are separate). The S row it draws is a cut-local
    // projection of the same track layer, but selecting the projection and
    // selecting the original are different acts.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-timeline-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-row-se-row-1')),
        matching: find.byKey(const ValueKey<String>('timeline-selected-layer')),
      ),
      findsNothing,
    );
    // Still exactly one selected row THERE, on the cut's own cel.
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );
  });

  testWidgets('the storyboard renders the TRACK SE row on the global axis: '
      'true lengths across cut ends with a ~ crossing mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('storyboard-se-label-sb-se-track-1')),
      findsOneWidget,
    );
    expect(find.text('S1'), findsWidgets);

    final rowFinder = find.byKey(
      const ValueKey<String>('storyboard-se-row-0-1'),
    );
    expect(rowFinder, findsOneWidget);

    final spanOne = find.byKey(
      const ValueKey<String>('storyboard-se-span-se-row-1-1'),
    );
    final spanCross = find.byKey(
      const ValueKey<String>('storyboard-se-span-se-row-1-6'),
    );
    final spanTwo = find.byKey(
      const ValueKey<String>('storyboard-se-span-se-row-1-10'),
    );
    expect(spanOne, findsOneWidget);
    expect(spanCross, findsOneWidget);
    expect(spanTwo, findsOneWidget);
    // Dialogue is painted (fitted glyphs) — read the widget fields.
    String dialogueOf(Finder span) => tester
        .widget<DialogueFitText>(
          find.descendant(of: span, matching: find.byType(DialogueFitText)),
        )
        .text;
    expect(dialogueOf(spanOne), 'One!');
    expect(dialogueOf(spanCross), 'Cross!');
    expect(dialogueOf(spanTwo), 'Two!');

    // Global placement with TRUE lengths: the crossing entry [6, 10) keeps
    // its 4 frames straight across the cut boundary at 8…
    final rowLeft = tester.getTopLeft(rowFinder).dx;
    final spanOneRect = tester.getRect(spanOne);
    final spanCrossRect = tester.getRect(spanCross);
    final spanTwoRect = tester.getRect(spanTwo);
    final pixelsPerFrame = (spanOneRect.left - rowLeft) / 1;
    expect(pixelsPerFrame, greaterThan(0));
    expect(
      spanCrossRect.left - rowLeft,
      moreOrLessEquals(6 * pixelsPerFrame, epsilon: 0.01),
    );
    expect(
      spanCrossRect.width,
      moreOrLessEquals(4 * pixelsPerFrame, epsilon: 0.01),
    );
    expect(
      spanTwoRect.left - rowLeft,
      moreOrLessEquals(10 * pixelsPerFrame, epsilon: 0.01),
    );
    expect(
      spanTwoRect.width,
      moreOrLessEquals(2 * pixelsPerFrame, epsilon: 0.01),
    );

    // …and NO ~ continuation mark here (UI-R7 #6): the storyboard shows
    // the whole flow — the cut-scoped timeline view carries the marks.
    expect(
      find.byKey(const ValueKey<String>('storyboard-se-crossing-se-row-1-8')),
      findsNothing,
    );
  });

  testWidgets('EVERY cut\'s SE blocks carry edge grips (UI-R7 #5) and an '
      'end drag edits + previews LIVE on the strip (UI-R7 #7)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    // The active cut is cut-1, yet the cut-2 block [10,12) has BOTH grips
    // (the active-cut gate is retired).
    final endGrip = find.byKey(
      const ValueKey<String>('storyboard-se-grip-se-row-1-2-end'),
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-se-grip-se-row-1-2-start')),
      findsOneWidget,
    );
    expect(endGrip, findsOneWidget);

    final span = find.byKey(
      const ValueKey<String>('storyboard-se-span-se-row-1-10'),
    );
    final widthBefore = tester.getSize(span).width;

    // Drag the end grip rightward and hold: the strip follows LIVE
    // through the drag-preview gate (UI-R7 #7 — it used to update only
    // on release). Stepped moves like a real pointer so the grip's
    // recognizer wins the arena over the scroll view.
    final gesture = await tester.startGesture(tester.getCenter(endGrip));
    await tester.pump();
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    final widthDuring = tester.getSize(span).width;
    expect(
      widthDuring,
      greaterThan(widthBefore),
      reason: 'the block stretches DURING the drag',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(span).width,
      greaterThan(widthBefore),
      reason: 'the release commits the global-axis edit',
    );
  });

  testWidgets('the TIMELINE marks the crossing (UI-R7 #6): ~ at the cut '
      'end on the owning cut, ~ at the cut start (no start grip) on the '
      'next cut', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();

    // Cut-1 active: the crossing block [6,10) runs past the cut end (8).
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-row-1-end')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-row-1-start')),
      findsNothing,
    );

    // Select cut-2 through the CUT row: taking a cut active is that row's
    // own verb (feedback #7 — an S row press moves the playhead and
    // RELEASES the cut, so it can no longer stand in for this). The
    // crossing block then spills IN — ~ at the cut start instead of a grip.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(_storyboardCutRowPoint(tester, globalFrame: 10));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-timeline-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-row-1-start')),
      findsOneWidget,
    );
    // The spill block's start grip stands down; its end grip (frame 1,
    // inside cut-2) stays. The cut-2 block [10,12) keeps both.
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-row-1-end')),
      findsNothing,
    );
  });
}
