import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// auto-frame-toggle-hitch (유저 2026-09-11: 「자동생성 누르면 0.5초정도
/// 버벅임이 생겻어」). A theme built afresh is never `==` the last one, so
/// every app-root rebuild handed `AnimatedTheme` a "new" theme to lerp to
/// and the whole app rebuilt on each frame of it — 7,777 widgets over four
/// frames for one toggle, measured 2026-09-29. The theme is one instance
/// per accent and language now.
void main() {
  tearDown(() {
    AppColors.accentSettings.value = const AppAccentSettings();
    AppText.settings.value = const AppLanguageSettings();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  test('while the accent and the language hold, the theme is ONE '
      'instance', () {
    expect(identical(buildAppTheme(), buildAppTheme()), isTrue);
  });

  test('a new accent is a new theme, in the new colour', () {
    final before = buildAppTheme();
    const lime = Color(0xFF9CCC65);

    AppColors.accentSettings.value = const AppAccentSettings(accent: lime);

    expect(identical(buildAppTheme(), before), isFalse);
    expect(buildAppTheme().colorScheme.primary, lime);
  });

  test('a new language is a new theme — the face follows it', () {
    final before = buildAppTheme();

    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ja,
    );

    expect(identical(buildAppTheme(), before), isFalse);
  });

  test('a new platform is a new theme — a theme carries the platform it '
      'was built on, and the scroll behaviour reads it back', () {
    final before = buildAppTheme();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final android = buildAppTheme();

      expect(identical(android, before), isFalse);
      expect(android.platform, TargetPlatform.android);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an input toggle leaves the app at rest after its one frame '
      '— there is no theme to animate', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();

    final input = AppInput.settings.value;
    AppInput.settings.value = input.copyWith(
      autoCreateFrameOnDraw: !input.autoCreateFrameOnDraw,
    );
    await tester.pump();

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'a lerp between two copies of one theme asks for more frames',
    );
  });
}
