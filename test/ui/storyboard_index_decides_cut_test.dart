import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// ⑭: the INDEX decides the active cut, whichever row was pressed.
///
/// This file used to pin the opposite (feedback #7): pressing an SE row said
/// WHERE you are without saying WHICH cut you edit, and released the active
/// cut even where the V row had one under that frame. That sentence answered
/// a question only multitrack could ask — "several cuts cover this frame, so
/// which did you mean". One track later the index names exactly one cut, and
/// the row a press landed on never was the thing that chose it.
///
/// The half that SURVIVES is the gap: a frame no cut covers still parks, and
/// that is what keeps ⑭ from swallowing UI-R9 #3.
Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

StoryboardPanel _panel(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));

TrackRowAddress _cutRow(WidgetTester tester) =>
    TrackRowAddress(_panel(tester).project.tracks.single.id);

LayerRowAddress _seRow(WidgetTester tester) =>
    LayerRowAddress(_panel(tester).project.tracks.single.seLayers.first.id);

/// The first global frame PAST every cut on the track — the trailing gap.
int _pastTheEnd(WidgetTester tester) {
  var total = 0;
  for (final cut in _panel(tester).project.tracks.single.cuts) {
    total += cut.duration;
  }
  return total + 2;
}

/// Presses [row] at global frame [frame] through the panel's own press
/// contract — the same call the cells make.
void _pressRow(WidgetTester tester, TimelineRowAddress row, int frame) {
  _panel(tester).onRowFramePress!(row, frame);
}

void main() {
  testWidgets('pressing an SE row over a cut TAKES that cut active — the '
      'index decides, not the row', (tester) async {
    await _openStoryboard(tester);

    // Park first, so "a cut is active" is something this press produced
    // rather than something it merely failed to disturb.
    _pressRow(tester, _seRow(tester), _pastTheEnd(tester));
    await tester.pumpAndSettle();
    expect(_panel(tester).activeCutId, isNull, reason: 'parked in the gap');

    _pressRow(tester, _seRow(tester), 10);
    await tester.pumpAndSettle();

    expect(
      _panel(tester).activeCutId,
      isNotNull,
      reason: 'a cut covers frame 10, so pressing ANY row there takes it',
    );
    expect(_panel(tester).playheadFrame?.value, 10);
  });

  testWidgets('an SE row press in a GAP still parks — ⑭ says "if a cut is '
      'there", and in a gap there is none', (tester) async {
    await _openStoryboard(tester);

    _pressRow(tester, _cutRow(tester), 10);
    await tester.pumpAndSettle();
    expect(_panel(tester).activeCutId, isNotNull);

    final gapFrame = _pastTheEnd(tester);
    _pressRow(tester, _seRow(tester), gapFrame);
    await tester.pumpAndSettle();

    expect(
      _panel(tester).activeCutId,
      isNull,
      reason: 'no cut covers that frame, so none is taken',
    );
    expect(_panel(tester).playheadFrame?.value, gapFrame);
  });

  testWidgets('the CUT row still takes its cut active — the verb that was '
      'never supposed to move', (tester) async {
    await _openStoryboard(tester);

    _pressRow(tester, _seRow(tester), _pastTheEnd(tester));
    await tester.pumpAndSettle();
    expect(_panel(tester).activeCutId, isNull);

    _pressRow(tester, _cutRow(tester), 6);
    await tester.pumpAndSettle();

    expect(_panel(tester).activeCutId, isNotNull);
    expect(_panel(tester).playheadFrame?.value, 6);
  });

  testWidgets('taking the cut does NOT move the selected row (확정 #25): the '
      'SE row stays the row you are on', (tester) async {
    await _openStoryboard(tester);

    _pressRow(tester, _seRow(tester), 12);
    await tester.pumpAndSettle();
    expect(
      _panel(tester).selectedRow,
      _seRow(tester),
      reason: 'the press activated a cut; the V row must not steal the row',
    );
    expect(_panel(tester).activeCutId, isNotNull);

    _pressRow(tester, _cutRow(tester), 12);
    await tester.pumpAndSettle();
    expect(_panel(tester).selectedRow, _cutRow(tester));
  });
}
