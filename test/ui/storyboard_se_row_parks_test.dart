import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// Pressing an SE row says WHERE you are, not WHICH cut you are editing
/// (feedback #7): the active cut is released even where the V row has one
/// under that frame. Taking a cut active is the cut row's own verb.
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

/// Presses [row] at global frame [frame] through the panel's own press
/// contract — the same call the cells make.
void _pressRow(WidgetTester tester, TimelineRowAddress row, int frame) {
  _panel(tester).onRowFramePress!(row, frame);
}

void main() {
  testWidgets('pressing an SE row RELEASES the active cut, even where the V '
      'row has one under that frame', (tester) async {
    await _openStoryboard(tester);

    // Land on the cut through the CUT row first, so there is something to
    // release and we know the frame is not a gap.
    _pressRow(tester, _cutRow(tester), 10);
    await tester.pumpAndSettle();
    expect(_panel(tester).activeCutId, isNotNull);

    _pressRow(tester, _seRow(tester), 10);
    await tester.pumpAndSettle();

    expect(
      _panel(tester).activeCutId,
      isNull,
      reason: 'an SE row owns no cuts, so pressing one takes none active',
    );
    // The playhead still went there: the press says where you are.
    expect(_panel(tester).playheadFrame?.value, 10);
  });

  testWidgets('the CUT row still takes its cut active — the verb that was '
      'never supposed to move', (tester) async {
    await _openStoryboard(tester);

    // Release it first, so the re-take is what the assertion sees.
    _pressRow(tester, _seRow(tester), 6);
    await tester.pumpAndSettle();
    expect(_panel(tester).activeCutId, isNull);

    _pressRow(tester, _cutRow(tester), 6);
    await tester.pumpAndSettle();

    expect(_panel(tester).activeCutId, isNotNull);
    expect(_panel(tester).playheadFrame?.value, 6);
  });

  testWidgets('either press still selects ITS row on the rail — releasing the '
      'cut is not the same as selecting nothing', (tester) async {
    await _openStoryboard(tester);

    _pressRow(tester, _seRow(tester), 12);
    await tester.pumpAndSettle();
    expect(_panel(tester).selectedRow, _seRow(tester));

    _pressRow(tester, _cutRow(tester), 12);
    await tester.pumpAndSettle();
    expect(_panel(tester).selectedRow, _cutRow(tester));
  });
}
