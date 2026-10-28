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
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

import '../helpers/named_finders.dart';
import '../helpers/storyboard_host.dart';
import '../helpers/the_classic_rail.dart';

/// THE cells contract, brought from the timeline to the storyboard: a press
/// on a row selects that row and seeks to the frame under the pointer.
///
/// There is deliberately no gap RULE — an empty cell is still a cell, so the
/// press hands its frame to the same seek the ruler uses, which parks when
/// the frame has no cut (UI-R9 #3).
Cut _cut(String id, int duration, {int leadingGapFrames = 0}) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  leadingGapFrames: leadingGapFrames,
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

/// Cut 1 covers [0,8), a GAP covers [8,12), cut 2 covers [12,18).
Project _project() => Project(
  id: const ProjectId('cells-project'),
  name: 'Cells',
  createdAt: DateTime.utc(2026, 7, 26),
  tracks: [
    Track(
      id: const TrackId('cells-track'),
      name: 'Video',
      cuts: [_cut('cut-1', 8), _cut('cut-2', 6, leadingGapFrames: 4)],
      seLayers: [
        Layer(
          id: const LayerId('cells-se-1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: const [],
          timeline: const {},
        ),
      ],
    ),
  ],
);

/// The conte as its tab hosts it ([pumpStoryboardHost]), in the test's
/// own window.
Future<void> _openStoryboard(WidgetTester tester) async {
  await pumpStoryboardHost(tester, _project(), surface: const Size(800, 600));
  // The second cut's frames on screen.
  await standTheClassicRail(tester);
}

double _pixelsPerFrame(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).pixelsPerFrame;

/// The cut the panel is handed as active — the session's answer; a cut
/// block no longer wears it (F-212).
CutId? _activeCut(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).activeCutId;

/// A point on the V row over [globalFrame] — the cut row spans the whole
/// track axis, so any frame has a position whether or not a cut is there.
Offset _cutRowPoint(WidgetTester tester, int globalFrame) {
  final row = find.byKey(
    const ValueKey<String>('storyboard-track-timeline-area-cells-track'),
  );
  final topLeft = tester.getTopLeft(row);
  return Offset(
    topLeft.dx + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    topLeft.dy + tester.getSize(row).height / 2,
  );
}

Offset _seRowPoint(WidgetTester tester, int globalFrame) {
  final row = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
  final topLeft = tester.getTopLeft(row);
  return Offset(
    topLeft.dx + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    topLeft.dy + tester.getSize(row).height / 2,
  );
}

/// The track-global frame and the cut-local one, both 1-based, joined the
/// way this file has always read them — which frame a press lands on.
///
/// ↩️They were the bar's frame counter's two lines (one string,
/// `global · local`, until 2026-08-10; stacked after), until F-463 took the
/// counter off. The channels it heard are read here.
String _frameCounter(WidgetTester tester) {
  final session = tester
      .widget<StoryboardTabHost>(find.byType(StoryboardTabHost))
      .session;
  final global = session.playheadCursors.trackFrame.value;
  return '${global == null ? '' : global + 1} · '
      '${session.editingFrameCursor.value + 1}';
}

void main() {
  testWidgets('pressing the cut row seeks to the PRESSED frame, not just to '
      'the cut it belongs to', (tester) async {
    await _openStoryboard(tester);
    expect(_frameCounter(tester), '1 · 1');

    // Global 14 = cut 2's local frame 2 (it starts at 12).
    await tester.tapAt(_cutRowPoint(tester, 14));
    await tester.pumpAndSettle();

    expect(_activeCut(tester), const CutId('cut-2'));
    expect(_frameCounter(tester), '15 · 3');
  });

  testWidgets('pressing a frame INSIDE the active cut moves the playhead '
      'there — the press used to discard the frame entirely', (tester) async {
    await _openStoryboard(tester);

    await tester.tapAt(_cutRowPoint(tester, 5));
    await tester.pumpAndSettle();

    expect(_activeCut(tester), const CutId('cut-1'));
    expect(_frameCounter(tester), '6 · 6');
  });

  testWidgets('pressing an empty cell PARKS in the gap: no cut is active, '
      'because an empty cell is a cell like any other', (tester) async {
    await _openStoryboard(tester);

    // Global 9 sits in the gap between the two cuts.
    await tester.tapAt(_cutRowPoint(tester, 9));
    await tester.pumpAndSettle();

    expect(_activeCut(tester), isNull);
    expect(_frameCounter(tester), startsWith('10 · '));
  });

  testWidgets('pressing an S row takes the row AND the frame — and the cut '
      'the INDEX names, over an empty cell too', (tester) async {
    await _openStoryboard(tester);

    await tester.tapAt(_seRowPoint(tester, 14));
    await tester.pumpAndSettle();

    // The S row is now THE selected row (its label carries the marker) —
    // the timeline's own row's, which it is (I-89 ①).
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-se-label-cells-track-1'),
        ),
        matching: find.named('storyboard-selected-layer'),
      ),
      findsOneWidget,
    );
    expect(_litRows(), 1, reason: 'one row is lit, never two');
    // The frame landed…
    expect(_frameCounter(tester), startsWith('15 · '));
    // …and the cut under it came with it (⑭). This used to assert the
    // opposite (feedback #7: an S row owns no cuts, so pressing one said
    // WHERE you are, not WHICH cut you edit) — a sentence that only had to
    // exist while several tracks could cover one frame. The row you pressed
    // never was the thing that chose the cut; the index is.
    expect(_activeCut(tester), const CutId('cut-2'));
  });

  testWidgets('pressing the cut row hands the row back to the V row after an '
      'S row held it', (tester) async {
    await _openStoryboard(tester);
    await tester.tapAt(_seRowPoint(tester, 2));
    await tester.pumpAndSettle();

    await tester.tapAt(_cutRowPoint(tester, 2));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-track-label-row-cells-track'),
        ),
        // The lit row's name is on the row's own plate.
        matching: find.named('storyboard-selected-row'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(_litRows(), 1, reason: 'the S row let go of it');
  });
}

/// How many rows of the rail are lit: a row that wears a layer carries the
/// timeline row's marker, the V row and a headless row the rail's own.
int _litRows() =>
    find.named('storyboard-selected-layer').evaluate().length +
    find.named('storyboard-selected-row').evaluate()
        .length;
