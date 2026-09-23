import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨F-170 (유저 2026-09-20): 「앱 초기 실행시, 레이어의 블렌드 모드가 영어가
/// 되있음. Normal로. 그 상태에서 다른 레이어로 이동하거나 프레임 생성하면
/// 표준이라고 한글로 바뀜」.
///
/// The saved program language is restored AFTER the first frame — the
/// session reads its file asynchronously — which is the same event as
/// picking a language in Preferences: the value changes under a screen that
/// is already built. The app root rebuilds for it and every word read at
/// build reads again; the blend chip's did not, because a host read the
/// language ONCE and handed it down as a value, with English as the default.
///
/// ⛔THE WHOLE SCREEN, NOT THE CHIP. 🔬Measured before the fix: of the nine
/// words the default screen translates, the two blend names were the only
/// ones left behind. A second word handed down the same way would pass a
/// test that looks at the chip alone.
///
/// ⚠️The real root ([AnicelApp]) and not a MaterialApp around HomePage: the
/// root's rebuild IS the mechanism every other word relies on. Without it
/// six of the nine stay behind (measured) — a pin without it would be
/// measuring a screen the app never shows.
void main() {
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  List<String> wordsOnScreen(WidgetTester tester) => [
    for (final text in tester.widgetList<RichText>(
      find.byType(RichText, skipOffstage: false),
    ))
      if (text.text.toPlainText().trim() case final word when word.isNotEmpty)
        word,
  ]..sort();

  Future<void> openTheApp(WidgetTester tester, AppLanguage language) async {
    AppText.settings.value = AppLanguageSettings(programLanguage: language);
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
  }

  testWidgets('a language that lands after the first frame reaches every '
      'word — the screen reads as if it had been born in it', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openTheApp(tester, AppLanguage.ko);
    final born = wordsOnScreen(tester);
    await tester.pumpWidget(const SizedBox());

    await openTheApp(tester, AppLanguage.en);
    final english = wordsOnScreen(tester);
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    await tester.pumpAndSettle();
    final late = wordsOnScreen(tester);

    expect(
      born,
      contains('표준'),
      reason: 'LIVENESS — the blend name the user saw is on this screen',
    );
    expect(
      english,
      isNot(born),
      reason: 'LIVENESS — the screen has words that change with the language',
    );
    expect(
      late,
      born,
      reason: '「Normal로 … 다른 레이어로 이동하거나 프레임 생성하면 표준이라고 '
          '한글로 바뀜」 — a word still in the old language waited for a '
          'rebuild it had no reason to get',
    );
  });

  /// The legend's bulk pick names the same modes, in a list built when it
  /// OPENS — so the screen above never sees it. It read the same handed-down
  /// value.
  testWidgets('the legend\'s blend list, opened after the language landed, '
      'names the modes in it', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openTheApp(tester, AppLanguage.en);
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('legend-blend')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('legend-blend-normal')),
        matching: find.text('표준'),
      ),
      findsOneWidget,
    );
  });
}
