import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/key_path.dart' show KeyPathKind;
import 'package:anicel/src/ui/dialogs/rename_frame_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/key_choice_row.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart' show Pill, PillStrip;

import '../../helpers/app_faces.dart';

/// I-89 ④-Q5 · anchor-walks-a-path-Q4: the key window's choice rows — how
/// the path passes through the covered keys (AE's four), whether their time
/// roves — lit as the keys agree, writing only what was picked, and offered
/// but refused where no covered key can say it.
void main() {
  bool? picked;

  Future<void> pumpRow(WidgetTester tester, List<bool> said) async {
    picked = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 368,
              child: StatefulBuilder(
                builder: (context, setState) => KeyChoiceRow<bool>(
                  label: 'Roving',
                  help: 'What roving is',
                  choices: const [
                    (id: 'row-off', word: 'Off', value: false),
                    (id: 'row-on', word: 'On', value: true),
                  ],
                  said: said,
                  picked: picked,
                  onPicked: (value) => setState(() => picked = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Pill pill(WidgetTester tester, String id) =>
      tester.widget<Pill>(find.byKey(ValueKey<String>('row-$id')));

  ({bool off, bool on}) lit(WidgetTester tester) =>
      (off: pill(tester, 'off').selected, on: pill(tester, 'on').selected);

  testWidgets('it lights what the keys all say, and nothing where they '
      'differ', (tester) async {
    await pumpRow(tester, [false, false]);
    expect(lit(tester), (off: true, on: false));

    await pumpRow(tester, [true, true]);
    expect(lit(tester), (off: false, on: true));

    await pumpRow(tester, [false, true]);
    expect(lit(tester), (off: false, on: false));
  });

  testWidgets('a pick lights itself over what the keys say, and is what '
      'the window hands on', (tester) async {
    await pumpRow(tester, [false, true]);
    await tester.tap(find.byKey(const ValueKey<String>('row-on')));
    await tester.pumpAndSettle();
    expect(picked, isTrue);
    expect(lit(tester), (off: false, on: true));

    await tester.tap(find.byKey(const ValueKey<String>('row-off')));
    await tester.pumpAndSettle();
    expect(picked, isFalse);
    expect(lit(tester), (off: true, on: false));
  });

  testWidgets('where no covered key can say it the row keeps its place and '
      'takes no pick', (tester) async {
    await pumpRow(tester, const []);
    expect(lit(tester), (off: false, on: false));
    expect(pill(tester, 'off').onTap, isNull);
    expect(pill(tester, 'on').onTap, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('row-on')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  group('the path row: After Effects\' four (anchor-walks-a-path-Q4)', () {
    KeyPathKind? kindPicked;

    Future<void> pumpPathRow(
      WidgetTester tester,
      List<KeyPathKind> said,
    ) async {
      kindPicked = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 368,
                child: StatefulBuilder(
                  builder: (context, setState) => KeyPathRow(
                    said: said,
                    picked: kindPicked,
                    onPicked: (kind) => setState(() => kindPicked = kind),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> lit(WidgetTester tester) => [
      for (final kind in KeyPathKind.values)
        if (tester
            .widget<Pill>(
              find.byKey(ValueKey<String>('rename-key-path-${kind.name}')),
            )
            .selected)
          kind.name,
    ];

    testWidgets('four pills in AE\'s order — the one the keys all are lit, '
        'and a pick lit over them and handed on', (tester) async {
      await pumpPathRow(tester, const [
        KeyPathKind.bezier,
        KeyPathKind.bezier,
      ]);
      expect(
        tester
            .widgetList<Pill>(find.byType(Pill))
            .map((pill) => (pill.key! as ValueKey<String>).value),
        [
          'rename-key-path-linear',
          'rename-key-path-bezier',
          'rename-key-path-continuousBezier',
          'rename-key-path-autoBezier',
        ],
      );
      expect(lit(tester), ['bezier']);

      await pumpPathRow(tester, const [
        KeyPathKind.linear,
        KeyPathKind.autoBezier,
      ]);
      expect(lit(tester), isEmpty);
      await tester.tap(
        find.byKey(const ValueKey<String>('rename-key-path-continuousBezier')),
      );
      await tester.pumpAndSettle();
      expect(kindPicked, KeyPathKind.continuousBezier);
      expect(lit(tester), ['continuousBezier']);
    });

    testWidgets('the four speak the program language — in Korean the words '
        'the user chose', (tester) async {
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      await pumpPathRow(tester, const []);
      expect(
        [
          for (final pill in tester.widgetList<Pill>(find.byType(Pill)))
            pill.label,
        ],
        ['선형', '베지어', '연속 베지어', '자동 베지어'],
      );
    });

    // As wide as the side rows' (I-89 ②, 400): every name says its word
    // whole, in the faces the app draws it in.
    for (final language in AppLanguage.values) {
      testWidgets('every name stands whole in the key window, in the app\'s '
          'own faces — ${language.name}', (tester) async {
        AppText.settings.value = AppLanguageSettings(programLanguage: language);
        addTearDown(
          () => AppText.settings.value = const AppLanguageSettings(),
        );
        await loadTheAppFaces();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Center(
                child: RenameFrameDialog(
                  initialName: '',
                  extra: KeyPathRow(
                    said: const [KeyPathKind.autoBezier],
                    picked: null,
                    onPicked: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          [
            for (final paragraph in tester.renderObjectList<RenderParagraph>(
              find.descendant(
                of: find.byType(PillStrip),
                matching: find.byType(RichText),
              ),
            ))
              if (paragraph.didExceedMaxLines) paragraph.text.toPlainText(),
          ],
          isEmpty,
          reason: 'no word ellipsised',
        );
      });
    }
  });
}
