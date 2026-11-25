import '../../helpers/screens_left_of_the_engine.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_paper.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timesheet/timesheet_paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/panel_finders.dart';
import '../../helpers/rail_group_button.dart';

/// 🗣️F-607 ② (유저 2026-11-16): 「타임시트패널 전환할때 팬이 오른쪽으로
/// 튕기는느낌? 1프레임?」 — a panel laid on the floor from the top strip
/// framed its first frame without the left pill's band past the rail,
/// which only a layout learns, and stood again a frame later: the
/// timesheet's paper 32 px to the left of where it stood next. The floor
/// keeps where its pill stood ([CanvasFloorInsets.leftPillBeside]), so
/// every panel laid there frames its first frame as it stands.
void main() {
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofAShot});
  final sheets = EditorWorkspace.railGroupId(right: true, slot: 2);
  String top(int slot) => EditorWorkspace.topGroupId(slot: slot);
  Finder band(String groupId) =>
      find.byKey(ValueKey<String>('rail-group-band-$groupId'));
  Finder floorButton(String tabId) =>
      find.byKey(ValueKey<String>('top-strip-floor-$tabId'));

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  /// Lifts the sheets' button by its band and lets it go on the top strip.
  Future<void> carrySheetsToTheTopStrip(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getCenter(band(sheets)));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    final to = tester.getCenter(railGroupButton(top(1)));
    await gesture.moveTo(to + const Offset(0, -5));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// The views each sheet's paper is painted at in the frame just pumped.
  final papers = <String, List<CanvasViewport> Function(WidgetTester)>{
    'timesheet': (tester) => [
      for (final paper in tester.widgetList<TimesheetPaper>(
        find.byType(TimesheetPaper),
      ))
        paper.viewport,
    ],
    'conte': (tester) => [
      for (final page in tester.widgetList<ConteBookPage>(
        find.byType(ConteBookPage),
      ))
        page.viewport,
    ],
    'envelope': (tester) => [
      for (final paper in tester.widgetList<CutEnvelopePaper>(
        find.byType(CutEnvelopePaper),
      ))
        paper.viewport,
    ],
  };

  testWidgets('each sheet laid on the floor again paints its first frame '
      'where it stands after', (tester) async {
    await pumpApp(tester);
    await carrySheetsToTheTopStrip(tester);

    for (final (slot, sheet) in [
      (1, 'timesheet'),
      (2, 'conte'),
      (3, 'envelope'),
    ]) {
      await tester.tap(floorButton(EditorWorkspace.canvasTabId));
      await tester.pumpAndSettle();
      expect(mainCanvasPanel(), findsOneWidget);

      await tester.tap(railGroupButton(top(slot)));
      await tester.pump();
      final first = papers[sheet]!(tester);
      await tester.pumpAndSettle();
      final standing = papers[sheet]!(tester);

      expect(first, isNotEmpty, reason: '$sheet paints a paper');
      expect(first, standing, reason: sheet);
    }

    // And not for nothing: the pill stands past the rail here, which the
    // floor learned — else a frame framed without it would stand where it
    // stands anyway.
    final floor = tester.widget<CanvasFloorInsets>(
      find.byType(CanvasFloorInsets),
    );
    expect(floor.leftPillBeside?.value, isTrue);
  });
}
