import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';

/// 🚨T16ⓑ′ — the collapsed overlay's rail is the TIMELINE's rail.
///
/// 유저: 「간편오버레이 버튼같은거 **다 표시용으로 살릴텐데**, **레이어영역의
/// 가로길이같은거 타임라인 그대로 가져와.** 그래야 **열의 규격이 맞을**
/// 거니까」.
///
/// ⛔The overlay used to be handed a number:
/// `rail?.value ?? layerRailMinimumWindowExtent`. A stored extent of null
/// does not mean the minimum — it means 「자연폭」, lay the rail out at its
/// own size — so a project that had never dragged the rail splitter got
/// `layerRailLeadingWidth + 14`: the leading cluster plus one letter of the
/// name. That is the `▸ ▦ ● 🎞 A` in the user's photograph, and it produced
/// three separate complaints from one line — 「버튼이 없다」, 「길이가
/// 다르다」, 「열이 안 맞는다」. The buttons were never removed. They were
/// outside the window.
void main() {
  testWidgets('with no stored width the rail lies at its NATURAL size, not '
      'the minimum', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();

    // Fold it: the overlay is the folded panel's row.
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();

    final overlay = find.byType(CollapsedRowOverlay);
    expect(overlay, findsOneWidget, reason: 'the folded row is up');

    final window = find.descendant(
      of: overlay,
      matching: find.byType(LayerRailWindow),
    );
    expect(
      window,
      findsOneWidget,
      reason: 'the overlay mounts the rail model rather than re-deriving it '
          'from a number — that hand copy is what could not tell natural '
          'from minimum',
    );

    final natural = tester.widget<LayerRailWindow>(window).naturalExtent;
    expect(
      natural,
      greaterThan(layerRailMinimumWindowExtent),
      reason: 'the fixture never dragged the splitter, so the old code would '
          'have sized this rail at the minimum — a leading cluster and one '
          'letter',
    );
    expect(
      tester.getRect(window).width,
      moreOrLessEquals(natural, epsilon: 1),
      reason: 'and with nothing stored the window IS the natural width, so '
          'the overlay\'s columns line up with the timeline\'s',
    );
  });
}
