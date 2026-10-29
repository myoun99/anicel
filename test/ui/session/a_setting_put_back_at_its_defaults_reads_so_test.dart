import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 — 「통째로 바뀐다(백업
/// 복원처럼)」. A settings file that put a setting back at its defaults
/// leaves its store holding nothing, and what reads it again reads the
/// defaults — as the app does at its start — not the value it had: the
/// hands-on verify's accent colour stayed as changed after the export.
void main() {
  test('an app setting its store holds nothing of reads back at its '
      'defaults — and a commit back to the value it had is written', () async {
    addTearDown(
      () => AppColors.accentSettings.value = const AppAccentSettings(),
    );
    final accents = _Accents();
    final settings = EditorAppSettings(accentSettingsStore: accents);
    addTearDown(settings.dispose);
    const picked = AppAccentSettings(accent: Color(0xFF123456));
    expect(picked, isNot(const AppAccentSettings()), reason: '⛔CONTROL');
    settings.setAccentSettings(picked);
    expect(accents.saves, 1);

    accents.saved = null;
    settings.restore();
    await pumpEventQueue();

    expect(AppColors.accentSettings.value, const AppAccentSettings());
    settings.setAccentSettings(picked);
    expect(
      accents.saves,
      2,
      reason: 'nothing is held of a store at its defaults — the first '
          'commit writes, as at the start',
    );
  });

  test('the shortcut keys their store holds nothing of read back as an '
      'install opens on them', () async {
    final keys = _Keys();
    final bindings = EditorShortcutBindings(store: keys);
    addTearDown(bindings.dispose);
    final opensOn = bindings.preset;
    final other = ShortcutPreset.values.firstWhere((p) => p != opensOn);
    bindings.setPreset(other);
    await bindings.pendingPersist;
    expect(keys.saved, isNotNull, reason: '⛔CONTROL: the pick was written');

    keys.saved = null;
    await bindings.restore();

    expect(bindings.preset, opensOn);
  });
}

class _Accents extends AppAccentSettingsStore {
  _Accents() : super(filePath: 'unused/accent_settings.json');

  AppAccentSettings? saved;
  int saves = 0;

  @override
  Future<AppAccentSettings?> load() async => saved;

  @override
  Future<void> save(AppAccentSettings settings) async {
    saved = settings;
    saves += 1;
  }
}

class _Keys extends ShortcutSettingsStore {
  _Keys() : super(filePath: 'unused/shortcut_overrides.json');

  Map<String, Object?>? saved;

  @override
  Future<Map<String, Object?>?> load() async => saved;

  @override
  Future<void> save(Map<String, Object?> payload) async => saved = payload;
}
