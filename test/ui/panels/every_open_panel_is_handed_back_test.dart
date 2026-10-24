import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/panels/open_tab_content.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨★EVERY OPEN PANEL is handed back as it was built while it stays open
/// (R12-①, every tab since 2026-10-24) — the tool column on the strip too.
///
/// ↩️Only the tabs once kept alive offstage were: on the user's layout a
/// tab switch in one dock rebuilt the tool library, the tool settings, the
/// colour and the onion panels in the others, about 2ms of a fold's 10.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  /// Each open panel's content as the framework holds it, by tab.
  Map<String, Widget> openContents() => {
    for (final element in find.byType(OpenTabContent).evaluate())
      (element.widget as OpenTabContent).tabId: _onlyChildOf(element).widget,
  };

  EditorDockHost dockHost(String dockId) => find
      .byType(EditorDockHost)
      .evaluate()
      .map((element) => element.widget as EditorDockHost)
      .singleWhere((host) => host.dockId == dockId);

  testWidgets('a tab switch in one dock builds no panel open in another', (
    tester,
  ) async {
    await pumpHome(tester);
    final before = openContents();
    final brushesHost = dockHost('rail-L1');
    expect(
      before.keys,
      containsAll(<String>['brushes', 'canvas', 'timesheet']),
      reason: 'premise: the default layout has these open',
    );
    expect(
      before.keys,
      contains('tools'),
      reason: "the strip's tool column is held as a dock's panel is",
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-conte-button')),
    );
    await tester.pumpAndSettle();
    final after = openContents();
    expect(after.keys, contains('conte'));
    expect(after.keys, isNot(contains('timesheet')));
    expect(
      identical(dockHost('rail-L1'), brushesHost),
      isFalse,
      reason: 'premise: the switch rebuilt the workspace round every dock',
    );
    for (final tabId in before.keys.where(after.containsKey)) {
      expect(
        identical(after[tabId], before[tabId]),
        isTrue,
        reason: '$tabId was built again for another dock\'s tab switch',
      );
    }
  });

  testWidgets('a language change builds every open panel again', (
    tester,
  ) async {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    await pumpHome(tester);
    final before = openContents();
    expect(before, isNotEmpty);

    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ja,
    );
    await tester.pumpAndSettle();
    final after = openContents();
    expect(after.keys, unorderedEquals(before.keys));
    for (final tabId in before.keys) {
      expect(
        identical(after[tabId], before[tabId]),
        isFalse,
        reason: '$tabId kept the words it was built in',
      );
    }
  });
}

Element _onlyChildOf(Element element) {
  final children = <Element>[];
  element.visitChildren(children.add);
  return children.single;
}
