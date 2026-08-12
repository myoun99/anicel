import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings_store.dart';

/// SAVE-1: the save/recovery policy — defaults, persistence, and where a
/// recovery snapshot is looked for now that its location is no longer a
/// setting (the app's own support folder, with the old beside-the-file
/// spot still checked so a crash from a previous build is not stranded).
void main() {
  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
  });

  test('defaults: autosave ON at 5 minutes', () {
    const settings = AppSaveSettings();
    expect(settings.autosaveEnabled, isTrue);
    expect(settings.autosaveIntervalMinutes, 5);
    expect(AppSave.autosaveInterval, const Duration(minutes: 5));
  });

  test('json roundtrip', () {
    const settings = AppSaveSettings(
      autosaveEnabled: false,
      autosaveIntervalMinutes: 12,
      recordingsDirectory: '/tmp/takes',
    );
    expect(AppSaveSettings.fromJson(settings.toJson()), settings);
    expect(
      AppSaveSettings.fromJson(const AppSaveSettings().toJson()),
      const AppSaveSettings(),
    );
    // copyWith can EXPLICITLY clear the directory back to the default.
    expect(
      settings.copyWith(recordingsDirectory: null).recordingsDirectory,
      isNull,
    );
    expect(settings.copyWith().recordingsDirectory, '/tmp/takes');
  });

  test('a sidecarDirectory left by an older build is read and dropped', () {
    // The location is not configurable any more. Carrying the key forward
    // would let a path that names a folder nothing writes to survive in
    // the settings file and confuse whoever reads it next.
    final revived = AppSaveSettings.fromJson(const {
      'autosaveEnabled': true,
      'autosaveIntervalMinutes': 5,
      'sidecarDirectory': '/somewhere/old',
      'recordingsDirectory': null,
    });
    expect(revived, const AppSaveSettings());
    expect(revived.toJson().containsKey('sidecarDirectory'), isFalse);
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

  test('the recovery snapshot lives in app support, never beside the '
      'project, under an ORIGIN-encoded name', () {
    // Origin-encoded because they all share one folder now: two projects
    // both called `C-045.anicel` in different works would otherwise write
    // over each other's crash work.
    final a = AppSave.recoveryPathFor('/projects/a/scene.anicel');
    final b = AppSave.recoveryPathFor('/projects/b/scene.anicel');

    expect(a, isNot(startsWith('/projects/')));
    expect(a, endsWith('.autosave'));
    expect(a, contains('scene.anicel.'));
    expect(a, isNot(b), reason: 'same basename, different folders');
    expect(
      AppSave.recoveryPathFor('/projects/a/scene.anicel'),
      a,
      reason: 'the encoding is stable across calls and runs',
    );
    expect(
      AppSave.recoveryPathFor('\\projects\\a\\scene.anicel'),
      a,
      reason: 'backslash and slash forms are the same origin',
    );
  });

  test('the OLD beside-the-file spot is still searched, so a crash from a '
      'previous build survives the update', () async {
    final directory = await Directory.systemTemp.createTemp('recovery-loc');
    addTearDown(() => directory.delete(recursive: true));
    final projectPath = '${directory.path}/scene.anicel'.replaceAll('\\', '/');

    expect(AppSave.recoveryCandidatesFor(projectPath), [
      AppSave.recoveryPathFor(projectPath),
      '$projectPath.autosave',
    ]);
    expect(AppSave.newestExistingRecoveryFor(projectPath), isNull);

    // Only the legacy one exists: it is still offered.
    final beside = File('$projectPath.autosave');
    await beside.writeAsString('old');
    await beside.setLastModified(DateTime(2020));
    expect(AppSave.newestExistingRecoveryFor(projectPath), beside.path);

    // Once the app has written its own, the newest wins either way.
    final current = File(AppSave.recoveryPathFor(projectPath));
    await current.create(recursive: true);
    addTearDown(() => current.parent.delete(recursive: true));
    await current.writeAsString('new');
    await current.setLastModified(DateTime(2024));
    expect(AppSave.newestExistingRecoveryFor(projectPath), current.path);

    await current.setLastModified(DateTime(2019));
    expect(AppSave.newestExistingRecoveryFor(projectPath), beside.path);
  });

  test('under FLUTTER_TEST the snapshot is redirected out of the real '
      'app-support folder', () {
    // Tests reach this through the production save and open wiring. Without
    // the redirect a run would drop snapshots into the user's own folder
    // and then read the ones an earlier run left there.
    final path = AppSave.recoveryPathFor('/projects/scene.anicel');
    expect(
      path.startsWith(Directory.systemTemp.path.replaceAll('\\', '/')),
      isTrue,
      reason: 'got $path',
    );
  });
}
