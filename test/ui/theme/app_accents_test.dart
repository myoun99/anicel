import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/ui/theme/app_accents.dart';
import 'package:anicel/src/ui/theme/layer_mark_palette.dart';
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
    const settings = AppAccentSettings(
      accent: Color(0xFF123456),
      layerMarkPalette: LayerMarkPalette.cream,
    );
    expect(settings.toJson(), {
      'accent': 0xFF123456,
      'layerMarkPalette': 'cream',
    });
    expect(AppAccentSettings.fromJson(settings.toJson()), settings);
  });

  test('a file written before the 색 라벨 tone existed keeps the DEFAULT '
      'tone rather than losing the accent with it', () {
    // A settings file from before I-4 has no `layerMarkPalette` key, and
    // reading that as a failure would throw the accent away too.
    //
    // ⛔THE TOKEN, not the tone's name. This spelled out
    // `LayerMarkPalette.original` and so broke the day the default moved to
    // 크림 (유저 실기 확정 2026-08-28) — a test that writes the value out is a
    // copy exactly like the code would be, and it is the third place that
    // was answering 「고른 적이 없으면 무엇인가」.
    final restored = AppAccentSettings.fromJson(const <String, dynamic>{
      'accent': 0xFF123456,
    });
    expect(restored.accent, const Color(0xFF123456));
    expect(restored.layerMarkPalette, LayerMarkPalette.fallback);
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
