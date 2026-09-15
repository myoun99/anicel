import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_defaults.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// Every built-in brush, group and tip has its name in every translated
/// table, no two of a kind share one, and no row names a built-in the
/// defaults no longer make.
///
/// 유저 2026-09-15 (brush-preset-names-language-Q1): 「만들 때 그 언어로
/// 적는다」.
///
/// ⚠️「Tabled」 is asked with a fallback no word can equal, never as 「differs
/// from English」: French says Pastel, Gouache and Texture.
void main() {
  const untabled = ' ';
  const translated = [
    AppLanguage.ja,
    AppLanguage.ko,
    AppLanguage.fr,
    AppLanguage.zhHans,
  ];

  for (final language in translated) {
    group(language.name, () {
      final strings = AppStrings.of(language);

      test('names every built-in brush, group and tip', () {
        bool untabledBrush(String id) =>
            strings.builtinBrushName(id, untabled) == untabled;
        expect([
          for (final group in defaultBrushGroups)
            if (untabledBrush(group.id.value)) group.id.value,
        ], isEmpty, reason: 'groups');
        expect([
          for (final preset in defaultBrushPresets)
            if (untabledBrush(preset.id.value)) preset.id.value,
        ], isEmpty, reason: 'brushes');
        expect([
          for (final tip in defaultBrushTipEntries)
            if (strings.builtinTipName(tip.id, untabled) == untabled) tip.id,
        ], isEmpty, reason: 'tips');
      });

      test('⛔gives no two brushes, groups or tips one name', () {
        // The roster's rule (유저 2026-09-09), in every language: two rows
        // the picker cannot tell apart are one brush wearing two names.
        final brushes = [
          for (final preset in namedDefaultBrushPresets(
            strings.builtinBrushName,
          ))
            preset.name,
        ];
        final groups = [
          for (final group in namedDefaultBrushGroups(strings.builtinBrushName))
            group.name,
        ];
        final tips = [
          for (final tip in namedDefaultBrushTips(strings.builtinTipName))
            tip.name,
        ];
        expect(brushes.toSet(), hasLength(brushes.length), reason: 'brushes');
        expect(groups.toSet(), hasLength(groups.length), reason: 'groups');
        expect(tips.toSet(), hasLength(tips.length), reason: 'tips');
      });
    });
  }

  test('⛔and no table names a built-in the defaults no longer make', () {
    final made = {
      for (final group in defaultBrushGroups) 'builtinBrush.${group.id.value}',
      for (final preset in defaultBrushPresets)
        'builtinBrush.${preset.id.value}',
      for (final tip in defaultBrushTipEntries) 'builtinTip.${tip.id}',
    };
    final source = File('lib/src/ui/text/app_strings.dart').readAsStringSync();
    final named = RegExp(r"'(builtin(?:Brush|Tip)\.builtin-[a-z0-9-]+)'")
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toSet();
    // ⛔A scan that reached nothing would pass the line below.
    expect(named, isNotEmpty);
    expect(named.difference(made), isEmpty);
  });
}
