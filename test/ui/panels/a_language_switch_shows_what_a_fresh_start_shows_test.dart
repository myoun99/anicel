import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/app_icon_button_probe.dart';

/// 🚨A LANGUAGE SWITCH SHOWS WHAT A FRESH START IN THAT LANGUAGE SHOWS, in
/// every open panel (2026-10-24).
///
/// ↩️The sheet's bar and the timeline's view cluster kept their tooltips in
/// the language they were built in — each held by a keep whose facts did
/// not carry it — while the panels round them changed; so did the brush
/// library, held by a keep of its own.
///
/// ⚠️Nothing above the panels is built again here: the app's root is const,
/// so what reaches them is what they hear themselves. The real app also
/// rebuilds its theme for a switch, which a switch between two languages of
/// one face never moves.
void main() {
  /// The app as it opens, with the frame dock's [tab] brought up.
  Future<void> pumpHome(WidgetTester tester, String? tab) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    if (tab != null) {
      await tester.tap(
        find.byKey(ValueKey<String>('timeline-mode-$tab-button')),
      );
      await tester.pumpAndSettle();
    }
  }

  /// Every tooltip each open dock wears, in tree order.
  Map<String, List<String>> tooltipsByDock() => {
    for (final dock in find.byType(EditorDockHost).evaluate())
      (dock.widget as EditorDockHost).dockId: [
        for (final tip in find
            .descendant(
              of: find.byElementPredicate((e) => identical(e, dock)),
              // Every kind of tooltip: the light faces' and the one around
              // anything else.
              matching: find.anyTooltip,
            )
            .evaluate())
          ?tooltipOf(tip.widget),
      ],
  };

  for (final tab in [null, 'timeline', 'storyboard', 'conte', 'envelope']) {
    testWidgets('every open dock wears the tooltips a fresh start wears'
        '${tab == null ? '' : ', the $tab tab up'}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      const japanese = AppLanguageSettings(programLanguage: AppLanguage.ja);

      await pumpHome(tester, tab);
      AppText.settings.value = japanese;
      await tester.pumpAndSettle();
      final switched = tooltipsByDock();

      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, tab);
      final fresh = tooltipsByDock();

      expect(switched.keys, unorderedEquals(fresh.keys));
      expect(
        fresh.values.where((tips) => tips.isNotEmpty),
        hasLength(fresh.length),
        reason: 'premise: every dock wears tooltips to compare',
      );
      for (final dock in fresh.keys) {
        expect(
          switched[dock],
          fresh[dock],
          reason: '$dock after a switch to Japanese',
        );
      }
    });
  }
}
