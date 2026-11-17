import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../helpers/app_faces.dart';
import '../helpers/rail_group_button.dart';

/// 🗣️tool-settings-segments-overlap-at-the-narrowest-Q1 (유저 2026-11-17):
/// 「도구 설정이 든 레일은 설정 칸이 서는 폭보다 좁아지지 않게 한다」 — in the
/// workspace: the rail's grip stops there, a rail stored narrower is drawn
/// there, and a rail without them goes on to its own floor.
void main() {
  final rightRail = EditorWorkspace.railGroupId(right: true, slot: 2);

  /// The tool settings share their rail with the library above them; the
  /// rail is one width, and the library's grip pulls it.
  const library = EditorWorkspace.leftGroupId;

  Future<void> pumpApp(WidgetTester tester, AppLanguage language) async {
    await loadTheAppFaces();
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    // Wide enough that the rail opens wider than their floor.
    await tester.binding.setSurfaceSize(const Size(2000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  double widthOf(WidgetTester tester, String railId) => tester
      .getSize(find.byKey(ValueKey<String>('rail-group-body-$railId')))
      .width;

  /// What the tool settings' rail needs where the workspace lays it out.
  double floorIn(WidgetTester tester) =>
      ToolSettingsPanel.minPanelWidthIn(
        tester.element(find.byType(EditorWorkspace)),
      ) +
      DockEdgeSplitter.thickness;

  Matcher atTheFloorOf(double floor) =>
      allOf(greaterThanOrEqualTo(floor), lessThan(floor + 1));

  /// Pulls [railId]'s width grip [dx] across.
  Future<void> pull(WidgetTester tester, String railId, double dx) async {
    await tester.drag(
      find.byKey(ValueKey<String>('dock-resize-$railId')),
      Offset(dx, 0),
    );
    await tester.pumpAndSettle();
  }

  /// Every answer's word in the tool settings at its whole width.
  void expectWordsWhole(WidgetTester tester) {
    final words = find
        .descendant(
          of: find.descendant(
            of: find.byType(ToolSettingsPanel),
            matching: find.byType(Pill),
          ),
          matching: find.byWidgetPredicate((line) => line is RichText),
        )
        .evaluate()
        .map((line) => line.renderObject! as RenderParagraph)
        .toList();
    expect(words, isNotEmpty, reason: '⛔premise: a choice stands');
    for (final word in words) {
      expect(
        word.size.width + 0.01,
        greaterThanOrEqualTo(word.getMaxIntrinsicWidth(double.infinity)),
        reason: word.text.toPlainText(),
      );
    }
  }

  testWidgets('the tool settings\' rail is pulled no narrower than they '
      'stand whole at, and their words are whole there — and a rail '
      'without them goes on past it', (tester) async {
    await pumpApp(tester, AppLanguage.zhHans);
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    final floor = floorIn(tester);
    expect(
      widthOf(tester, toolSettingsGroupId),
      greaterThan(floor + 1),
      reason: '⛔premise: the rail opens wider than their floor',
    );

    // The left rail's inner edge is its right one.
    await pull(tester, library, -250);
    expect(widthOf(tester, toolSettingsGroupId), atTheFloorOf(floor));
    expectWordsWhole(tester);

    // The GRIP stopped there, not only the drawing: the way back out moves
    // the edge from the first pixel (유저 R4 #13 — a grip that banked travel
    // past a floor followed the cursor late and short).
    final held = widthOf(tester, toolSettingsGroupId);
    await pull(tester, library, 40);
    expect(widthOf(tester, toolSettingsGroupId), closeTo(held + 40, 1));

    // The right rail's inner edge is its left one.
    await pull(tester, rightRail, 250);
    expect(widthOf(tester, rightRail), lessThan(floor));
  });

  testWidgets('a rail held at one language\'s floor is drawn at a wider '
      'one\'s, and the tool settings\' group shut still holds it', (
    tester,
  ) async {
    await pumpApp(tester, AppLanguage.zhHans);
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    await pull(tester, library, -250);
    final narrower = floorIn(tester);
    expect(widthOf(tester, toolSettingsGroupId), atTheFloorOf(narrower));

    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.fr,
    );
    await tester.pumpAndSettle();
    final wider = floorIn(tester);
    expect(wider, greaterThan(narrower), reason: '⛔premise');
    expect(widthOf(tester, toolSettingsGroupId), atTheFloorOf(wider));
    expectWordsWhole(tester);

    // 🗣️Q3: shut, the tool settings still hold the rail — the library
    // above them keeps their width.
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('rail-group-body-$toolSettingsGroupId')),
      findsNothing,
      reason: '⛔premise: shut',
    );
    await pull(tester, library, -250);
    expect(widthOf(tester, library), atTheFloorOf(wider));
  });
}
