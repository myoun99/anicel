import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings_store.dart';

/// SAVE-1: the save/autosave policy — defaults, persistence, and the
/// sidecar location resolution (beside the file vs the user's sidecar
/// directory, with recovery checking every candidate).
void main() {
  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
  });

  test('defaults: autosave ON at 5 minutes, sidecar beside the file', () {
    const settings = AppSaveSettings();
    expect(settings.autosaveEnabled, isTrue);
    expect(settings.autosaveIntervalMinutes, 5);
    expect(settings.sidecarDirectory, isNull);
    expect(AppSave.autosaveInterval, const Duration(minutes: 5));
  });

  test('json roundtrip incl. the null sidecar directory', () {
    const settings = AppSaveSettings(
      autosaveEnabled: false,
      autosaveIntervalMinutes: 12,
      sidecarDirectory: '/tmp/sidecars',
      recordingsDirectory: '/tmp/takes',
    );
    expect(AppSaveSettings.fromJson(settings.toJson()), settings);
    expect(
      AppSaveSettings.fromJson(const AppSaveSettings().toJson()),
      const AppSaveSettings(),
    );
    // copyWith can EXPLICITLY clear the directories back to defaults.
    expect(settings.copyWith(sidecarDirectory: null).sidecarDirectory, isNull);
    expect(settings.copyWith().sidecarDirectory, '/tmp/sidecars');
    expect(
      settings.copyWith(recordingsDirectory: null).recordingsDirectory,
      isNull,
    );
    expect(settings.copyWith().recordingsDirectory, '/tmp/takes');
  });

  test('store roundtrip; missing/corrupt files yield null', () async {
    final directory = await Directory.systemTemp.createTemp('save-settings');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppSaveSettingsStore(
      filePath: '${directory.path}/save_settings.json',
    );
    expect(await store.load(), isNull);
    const settings = AppSaveSettings(autosaveIntervalMinutes: 30);
    await store.save(settings);
    expect(await store.load(), settings);

    await File(store.filePath).writeAsString('not json');
    expect(await store.load(), isNull);
  });

  test('sidecar resolution: beside by default; the custom directory gets '
      'an origin-encoded name (no cross-folder collisions)', () {
    expect(
      AppSave.sidecarPathFor('/projects/scene.qap'),
      '/projects/scene.qap.autosave',
    );

    AppSave.settings.value = const AppSaveSettings(
      sidecarDirectory: '/sidecars',
    );
    final a = AppSave.sidecarPathFor('/projects/a/scene.qap');
    final b = AppSave.sidecarPathFor('/projects/b/scene.qap');
    expect(a, startsWith('/sidecars/scene.qap.'));
    expect(a, endsWith('.autosave'));
    expect(a, isNot(b), reason: 'same basename, different folders');
    expect(
      AppSave.sidecarPathFor('/projects/a/scene.qap'),
      a,
      reason: 'the encoding is stable across calls/runs',
    );
    // Windows separators normalize into the same encoding.
    expect(
      AppSave.sidecarPathFor('\\projects\\a\\scene.qap'),
      a,
      reason: 'backslash and slash forms are the same origin',
    );

    expect(AppSave.sidecarCandidatesFor('/projects/a/scene.qap'), [
      '/projects/a/scene.qap.autosave',
      a,
    ]);
  });

  test('newestExistingSidecarFor picks the newest across candidate '
      'locations', () async {
    final directory = await Directory.systemTemp.createTemp('sidecar-loc');
    addTearDown(() => directory.delete(recursive: true));
    final projectPath = '${directory.path}/scene.qap'.replaceAll('\\', '/');
    final sidecarDir = '${directory.path}/sidecars'.replaceAll('\\', '/');
    AppSave.settings.value = AppSaveSettings(sidecarDirectory: sidecarDir);

    expect(AppSave.newestExistingSidecarFor(projectPath), isNull);

    // Older beside-the-file sidecar…
    final beside = File('$projectPath.autosave');
    await beside.writeAsString('old');
    await beside.setLastModified(DateTime(2020));

    // …newer one in the custom directory.
    final custom = File(AppSave.sidecarPathFor(projectPath));
    await custom.create(recursive: true);
    await custom.writeAsString('new');
    await custom.setLastModified(DateTime(2024));

    expect(AppSave.newestExistingSidecarFor(projectPath), custom.path);

    await custom.setLastModified(DateTime(2019));
    expect(AppSave.newestExistingSidecarFor(projectPath), beside.path);
  });
}
