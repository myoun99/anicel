// TWO OPEN RAIL GROUPS SIT ONE GAP APART — MEASURED ON THEIR OWN GRIPS.
//
// A survivor of the mutation campaign (2026-09-04, the rail column cut):
// the `run.take(_railGroupGap)` between groups was dropped and the rail
// test stayed green — it measured the PANELS inside the groups, which sit
// inside their own insets, so "the second is below the first" held with
// no gap at all. This pin reads the group boxes through the grips that lie
// on their edges: the first group's height grip along its bottom, the
// second group's side grip along its height.
//
// ⚠️A grip stops one corner short of each end of its edge (I-60: 「곡선
// 전에 끝나도록」), so a box read off a grip's span is that span and one
// corner more at each end.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';

import '../helpers/rail_group_button.dart';

const _corner = DockEdgeSplitter.endInset;

void main() {
  testWidgets('the second group starts one rail gap below the first', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    final first = EditorWorkspace.railGroupId(right: false, slot: 1);
    final second = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(railGroupButton(second));
    await tester.pumpAndSettle();

    final firstSide = find.byKey(ValueKey<String>('dock-resize-$first'));
    final secondSide = find.byKey(ValueKey<String>('dock-resize-$second'));
    final firstBottom = tester
        .getRect(find.byKey(ValueKey<String>('dock-resize-$first-height')))
        .bottom;
    final secondTop = tester.getRect(secondSide).top - _corner;
    // The rail's gap between groups: _EditorWorkspaceState._railGroupGap.
    expect(
      secondTop - firstBottom,
      closeTo(8, 0.5),
      reason: 'the groups float one gap apart, not flush',
    );

    // The column is exactly as tall as the groups it stacks: the trailing
    // gap after the last group is not part of it.
    final column = find
        .ancestor(
          of: secondSide,
          matching: find.byWidgetPredicate(
            (widget) => widget is SizedBox && widget.child is Stack,
          ),
        )
        .first;
    final firstTop = tester.getRect(firstSide).top - _corner;
    final secondBottom = tester.getRect(secondSide).bottom + _corner;
    expect(
      tester.getSize(column).height,
      closeTo(secondBottom - firstTop, 0.5),
      reason: 'no gap trails the last group',
    );
  });

  testWidgets('the RIGHT rail keeps its gap on the strip side', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    // The right rail opens with its second group (the timesheet); the
    // gap between the panels and the strip lies on the strip's side, so
    // the group is flush with the rail's canvas edge and one gap short of
    // its strip edge.
    final sheet = EditorWorkspace.railGroupId(right: true, slot: 2);
    final dock = tester.getRect(
      find.byKey(const ValueKey<String>('editor-panel-dock-right')),
    );
    final grip = tester.getRect(
      find.byKey(ValueKey<String>('dock-resize-$sheet-height')),
    );
    expect(grip.left - _corner, closeTo(dock.left, 0.5));
    expect(dock.right - (grip.right + _corner), closeTo(8, 0.5));
  });
}
