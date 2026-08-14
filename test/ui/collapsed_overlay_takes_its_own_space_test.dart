import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';

import '../helpers/panel_finders.dart';

/// 🚨UI 피드백 08-14 #12 — the folded row is a PARTICIPANT in the layout,
/// not a decal on top of one.
///
/// > 「간편오버레이가 **제대로 위젯으로서 공간 차지하도록 안되있는느낌?** …
/// > 캔버스패널 가로스크롤바는 간편오버레이 위에 오도록 되는데, **옆에
/// > 패널들은 간편오버레이를 침범해서 자리차지함** … 제대로 패널으로서 공간은
/// > 차지하도록. **그래야 수정했을때 아무것도 안고치고 반영되니까**」
///
/// The last sentence is the requirement: whatever the folded row grows into
/// later should be respected by everyone without another edit. So the span
/// it occupies belongs in the one number the rails already read, rather
/// than in a second place that has to be kept in step.
///
/// ⚠️Occupying space against PANELS is not the same as occupying it against
/// the ARTWORK. The row deliberately lies ON the drawing (유저 확정
/// 2026-08-10, "no panel fill, no ground") — that is why the floor's insets
/// leave it out and only the bars step aside. This test is about the other
/// half.
void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1600, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> collapseBottomDock(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
  }

  Finder overlay() => find.byType(CollapsedRowOverlay);

  /// The default rail is as tall as it was left at, and that default is
  /// SHORT — it never comes near the region, so a test that only collapses
  /// the dock passes without reproducing anything.
  ///
  /// 🚨And the ORDER is the reproduction. Growing the rail first and then
  /// folding leaves it at the height it was given, which is above the row;
  /// the rail only reaches into the row when it is grown WHILE folded,
  /// because that is when it asks where its stop is.
  Future<void> growRightRailToItsStop(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-rail-R2-height')),
      const Offset(0, 1200),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a rail grown to its stop lands on the region, not in it', (
    tester,
  ) async {
    await pumpApp(tester);
    await growRightRailToItsStop(tester);

    final open = tester.getRect(timesheetPanel());
    final region = tester.getRect(
      find.byKey(const ValueKey<String>('floating-bottom-region')),
    );
    expect(
      open.bottom,
      lessThanOrEqualTo(region.top + 0.5),
      reason: 'the stop is the region it cannot stand on',
    );
  });

  testWidgets('a rail grown while folded stops above the row, not inside it', (
    tester,
  ) async {
    await pumpApp(tester);
    await collapseBottomDock(tester);
    await growRightRailToItsStop(tester);

    expect(overlay(), findsOneWidget, reason: 'the fold is what we collapsed');
    final row = tester.getRect(overlay());
    final rail = tester.getRect(timesheetPanel());

    // Only meaningful if the two share a column of the window — a rail
    // narrow enough to pass BESIDE the region never meets the row.
    expect(
      rail.left < row.right && row.left < rail.right,
      isTrue,
      reason: 'the default right rail is wide enough to sit over the region',
    );
    expect(
      rail.bottom,
      lessThanOrEqualTo(row.top + 0.5),
      reason: 'the folded row is a panel-sized thing, not a decal the '
          'neighbours may stand on',
    );
  });
}
