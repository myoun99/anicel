import 'package:flutter/material.dart';
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
}
