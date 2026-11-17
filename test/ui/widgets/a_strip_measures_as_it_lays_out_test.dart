import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/app_faces.dart';

/// F-486: a box that sizes itself to its pills asks the strip what its
/// words need ([PillStrip.naturalWidthIn]) — so the answer is what the
/// strip lays out at, to the pixel, in every language's face.
void main() {
  const wordSets = [
    ['A'],
    ['셀', '콘티', '미술', '디렉션'],
    ['セル', '絵コンテ', '美術', 'ディレクション'],
    ['Cellulos', 'Storyboard', 'Décor', 'Direction'],
    ['Feuille de temps', 'Enveloppe de plan'],
  ];

  for (final language in AppLanguage.values) {
    testWidgets('the measure is the strip laid out — ${language.name}', (
      tester,
    ) async {
      await loadTheAppFaces();
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      for (final words in wordSets) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Center(
                child: PillStrip(
                  items: [
                    for (final (index, word) in words.indexed)
                      PillItem(
                        keyValue: 'pill-$index',
                        label: word,
                        selected: index == 0,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          PillStrip.naturalWidthIn(tester.element(find.byType(Center)), words),
          moreOrLessEquals(
            tester.getSize(find.byType(PillStrip)).width,
            epsilon: 0.01,
          ),
          reason: '${words.join(' · ')} in ${language.name}',
        );
      }
    });
  }

  // 🗣️tool-settings-segments-overlap-at-the-narrowest-Q1: an even strip
  // given its least width holds every word whole, and a pixel less cuts one
  // — the width the tool settings' least width reads.
  for (final language in AppLanguage.values) {
    testWidgets('an even strip\'s least width is the one its words stand '
        'whole at — ${language.name}', (tester) async {
      await loadTheAppFaces();
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      final sets = [
        ['なし', '1', '2', '3'],
        ...wordSets,
      ];
      for (final words in sets) {
        Future<bool> wholeAt(double width) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    child: PillStrip.even(
                      items: [
                        for (final (index, word) in words.indexed)
                          PillItem(
                            keyValue: 'pill-$index',
                            label: word,
                            selected: index == 0,
                            onTap: () {},
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          return [
            for (final (index, _) in words.indexed)
              tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: find.byKey(ValueKey<String>('pill-$index')),
                  // An [EllipsisText] lays its line as a kind of its own.
                  matching: find.byWidgetPredicate((line) => line is RichText),
                ),
              ),
          ].every(
            (word) =>
                word.size.width + 0.01 >=
                word.getMaxIntrinsicWidth(double.infinity),
          );
        }

        await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: const Scaffold()),
        );
        final least = PillStrip.evenWidthIn(
          tester.element(find.byType(Scaffold)),
          words,
        );
        final reason = '${words.join(' · ')} in ${language.name}';
        expect(await wholeAt(least), isTrue, reason: reason);
        expect(await wholeAt(least - 1), isFalse, reason: reason);
      }
    });
  }
}
