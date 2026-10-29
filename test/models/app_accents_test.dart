import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import '../helpers/project_scratch_folder.dart';

/// UI-R22 #5: the program accent is customizable and persists.
///
/// There used to be a second accent here, the automatic complement of the
/// first. It is gone: it had one production consumer and its second
/// documented purpose was never wired, so the pair of tests that exercised
/// the complement and its override are gone with it. What survives is the
/// contract that still exists — one accent, persisted, read live — plus the
/// forward compatibility promise that a stored accent2 from an older build
/// cannot break the load.
void main() {
  tearDown(() {
    // The accent is app-global — every test restores the default.
    AppColors.accentSettings.value = const AppAccentSettings();
  });

  test('json round-trips', () {
    const settings = AppAccentSettings(accent: Color(0xFF123456));
    // ⚠️Spelled out rather than only round-tripped: `fromJson` hands defaults
    // back for missing keys, so a `toJson` that silently dropped one would
    // still round-trip clean.
    expect(settings.toJson(), {'accent': 0xFF123456, 'mode': 'dark'});
    expect(AppAccentSettings.fromJson(settings.toJson()), settings);
    const light = AppAccentSettings(
      accent: Color(0xFF123456),
      mode: AppColorMode.light,
    );
    expect(light.toJson()['mode'], 'light');
    expect(AppAccentSettings.fromJson(light.toJson()), light);
  });

  test('a file from before the light palette opens dark (I-143)', () {
    final restored = AppAccentSettings.fromJson(const <String, dynamic>{
      'accent': 0xFF123456,
    });
    expect(restored.mode, AppColorMode.dark);
    expect(
      AppAccentSettings.fromJson(const <String, dynamic>{'mode': 'sepia'}).mode,
      AppColorMode.dark,
      reason: 'a mode this build does not know is the default, not a crash',
    );
  });

  test('the retired 색 라벨 keys are simply not read, and the accent '
      'survives them', () {
    // 🪦Builds in between wrote `layerMarkPalette`, then `layerMarkHardEdges`
    // with its threshold, then `layerMarkGlyphWeight`. All three rounds ended
    // in a fixed value, and a file still holding them must not fail to load —
    // the keys stay on disk until the next save.
    final read = AppAccentSettings.fromJson(const <String, dynamic>{
      'accent': 0xFF123456,
      'layerMarkPalette': 'pastel',
      'layerMarkHardEdges': true,
      'layerMarkHardEdgeThreshold': 0.35,
      'layerMarkGlyphWeight': 900,
    });
    expect(read.accent, const Color(0xFF123456));
  });

  test('a stored accent2 from an older build is ignored, not fatal', () {
    final restored = AppAccentSettings.fromJson(const <String, dynamic>{
      'accent': 0xFF123456,
      'accent2': 0xFF654321,
    });
    expect(restored.accent, const Color(0xFF123456));
    expect(restored.toJson().containsKey('accent2'), isFalse);
  });

  test('a missing accent falls back to the default', () {
    final restored = AppAccentSettings.fromJson(const <String, dynamic>{});
    expect(restored.accent, AppAccentSettings.defaultAccent);
  });

  test('the store round-trips through its json file', () async {
    final dir = await Directory.systemTemp.createTemp('accents');
    deleteAfterSessionEnds(dir);
    final store = AppAccentSettingsStore(
      filePath: '${dir.path}/accent_settings.json',
    );
    expect(await store.load(), isNull);

    const settings = AppAccentSettings(
      accent: Color(0xFF2244CC),
      mode: AppColorMode.light,
    );
    await store.save(settings);
    expect(await store.load(), settings);
  });

  test('AppColors reads the LIVE settings', () {
    expect(AppColors.accent, AppAccentSettings.defaultAccent);
    AppColors.accentSettings.value = const AppAccentSettings(
      accent: Color(0xFF2244CC),
    );
    expect(AppColors.accent, const Color(0xFF2244CC));
  });

  /// 🗣️I-143: the neutrals read the palette of the mode worn, live.
  test('the chrome\'s tokens read the palette of the mode worn', () {
    expect(AppColors.surface, AppPalette.dark.surface);
    expect(AppColors.text, AppPalette.dark.text);
    AppColors.accentSettings.value = const AppAccentSettings(
      mode: AppColorMode.light,
    );
    for (final (name, token, light) in [
      ('backdrop', AppColors.backdrop, AppPalette.light.backdrop),
      ('surface', AppColors.surface, AppPalette.light.surface),
      ('surfaceHigh', AppColors.surfaceHigh, AppPalette.light.surfaceHigh),
      ('washUp', AppColors.washUp, AppPalette.light.washUp),
      ('washDown', AppColors.washDown, AppPalette.light.washDown),
      ('hairline', AppColors.hairline, AppPalette.light.hairline),
      (
        'hairlineStrong',
        AppColors.hairlineStrong,
        AppPalette.light.hairlineStrong,
      ),
      ('gripHover', AppColors.gripHover, AppPalette.light.gripHover),
      ('text', AppColors.text, AppPalette.light.text),
      ('textDim', AppColors.textDim, AppPalette.light.textDim),
      ('danger', AppColors.danger, AppPalette.light.danger),
    ]) {
      expect(token, light, reason: name);
    }
  });

  double contrast(Color a, Color b) {
    final (x, y) = (a.computeLuminance(), b.computeLuminance());
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// 🗣️I-143-Q4 (유저 2026-10-30, 「라이트에서만 진하게」).
  test('on the light palette the accent is its hue darkened to 3:1 on the '
      'panel; on the dark one it is the colour picked', () {
    const picked = Color(0xFF9BBF4E);
    AppColors.accentSettings.value = const AppAccentSettings(accent: picked);
    expect(AppColors.accent, picked);

    AppColors.accentSettings.value = const AppAccentSettings(
      accent: picked,
      mode: AppColorMode.light,
    );
    expect(
      contrast(picked, AppColors.surface),
      lessThan(3),
      reason: '⛔전제: the picked green is pale on the light panel',
    );
    final shown = AppColors.accent;
    expect(contrast(shown, AppColors.surface), greaterThanOrEqualTo(3));
    expect(
      HSLColor.fromColor(shown).hue,
      moreOrLessEquals(HSLColor.fromColor(picked).hue, epsilon: 0.5),
      reason: 'the same hue, only darker',
    );
    expect(
      AppColors.accentSettings.value.accent,
      picked,
      reason: 'what is stored — and what the swatch shows — is the pick',
    );
  });
}
