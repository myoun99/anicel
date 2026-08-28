import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/ui/theme/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

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
    expect(settings.toJson(), {'accent': 0xFF123456});
    expect(AppAccentSettings.fromJson(settings.toJson()), settings);
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
    addTearDown(() => dir.delete(recursive: true));
    final store = AppAccentSettingsStore(
      filePath: '${dir.path}/accent_settings.json',
    );
    expect(await store.load(), isNull);

    const settings = AppAccentSettings(accent: Color(0xFF2244CC));
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
}
