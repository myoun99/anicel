import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/ui/theme/app_accents.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// UI-R22 #5: the two program accents — accent 2 defaults to accent 1's
/// COMPLEMENT and both persist.
void main() {
  tearDown(() {
    // The accents are app-global — every test restores the default.
    AppColors.accentSettings.value = const AppAccentSettings();
  });

  test('accent 2 follows the complement (teal → pink family) until '
      'overridden; clearing returns to automatic', () {
    const settings = AppAccentSettings();
    expect(settings.accent2FollowsComplement, isTrue);
    final autoHue = HSLColor.fromColor(settings.accent2).hue;
    final baseHue = HSLColor.fromColor(settings.accent).hue;
    expect(((autoHue - baseHue).abs() - 180.0).abs(), lessThan(0.5));

    final custom = settings.copyWith(accent2: const Color(0xFFFF00FF));
    expect(custom.accent2FollowsComplement, isFalse);
    expect(custom.accent2, const Color(0xFFFF00FF));

    final cleared = custom.copyWith(clearAccent2: true);
    expect(cleared.accent2FollowsComplement, isTrue);

    // Changing accent 1 moves the automatic accent 2 with it.
    final moved = settings.copyWith(accent: const Color(0xFF2244CC));
    expect(HSLColor.fromColor(moved.accent2).hue, isNot(closeTo(autoHue, 1.0)));
  });

  test('json round-trips: automatic omits accent2, overrides persist', () {
    const auto = AppAccentSettings(accent: Color(0xFF123456));
    expect(auto.toJson().containsKey('accent2'), isFalse);
    expect(AppAccentSettings.fromJson(auto.toJson()), auto);

    const custom = AppAccentSettings(
      accent: Color(0xFF123456),
      accent2: Color(0xFF654321),
    );
    final restored = AppAccentSettings.fromJson(custom.toJson());
    expect(restored, custom);
    expect(restored.accent2, const Color(0xFF654321));
  });

  test('the store round-trips through its json file', () async {
    final dir = await Directory.systemTemp.createTemp('accents');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppAccentSettingsStore(
      filePath: '${dir.path}/accent_settings.json',
    );
    expect(await store.load(), isNull);

    const settings = AppAccentSettings(
      accent: Color(0xFF2244CC),
      accent2: Color(0xFFCC8822),
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
    expect(
      AppColors.accent2,
      AppAccentSettings.complementOf(const Color(0xFF2244CC)),
    );
  });
}
