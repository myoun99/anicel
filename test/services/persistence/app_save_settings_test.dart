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

  test('defaults: the two cheap triggers on, the clock off', () {
    const settings = AppSaveSettings();
    expect(settings.lifecycleSnapshotEnabled, isTrue);
    expect(settings.pauseSnapshotEnabled, isTrue);
    // The clock is opt-in: pauses cover a session that has them, and the
    // interval only earns its keep on a long unbroken stretch.
    expect(settings.periodicSnapshotMinutes, isNull);
    expect(settings.toJson().keys, unorderedEquals(<String>[
      'lifecycleSnapshotEnabled',
      'pauseSnapshotEnabled',
      'periodicSnapshotMinutes',
      'recordingsDirectory',
      'conformDirectory',
    ]));
    // Both folders default to the app's own, so a fresh install writes
    // nothing beside a project.
    expect(settings.recordingsDirectory, isNull);
    expect(settings.conformDirectory, isNull);
  });

  test('json roundtrip', () {
    const settings = AppSaveSettings(
      lifecycleSnapshotEnabled: false,
      pauseSnapshotEnabled: false,
      periodicSnapshotMinutes: 20,
      recordingsDirectory: '/tmp/takes',
      conformDirectory: '/tmp/conforms',
    );
    expect(AppSaveSettings.fromJson(settings.toJson()), settings);
    expect(
      AppSaveSettings.fromJson(const AppSaveSettings().toJson()),
      const AppSaveSettings(),
    );
    // copyWith can EXPLICITLY clear either directory back to the default.
    expect(
      settings.copyWith(recordingsDirectory: null).recordingsDirectory,
      isNull,
    );
    expect(settings.copyWith(conformDirectory: null).conformDirectory, isNull);
    expect(settings.copyWith().recordingsDirectory, '/tmp/takes');
    expect(settings.copyWith().conformDirectory, '/tmp/conforms');
    // The two must not be one field wearing two names: moving the cache
    // must not move the take shelf with it.
    expect(
      settings.copyWith(conformDirectory: '/elsewhere').recordingsDirectory,
      '/tmp/takes',
    );
  });

  test('a setting whose feature is gone is read and DROPPED', () {
    // The sidecar location is fixed now, and a setting that outlives its
    // feature is a value the next reader has to work out is dead.
    final revived = AppSaveSettings.fromJson(const {
      'sidecarDirectory': '/somewhere/old',
      'recordingsDirectory': null,
    });
    expect(revived, const AppSaveSettings());
    expect(revived.toJson().containsKey('sidecarDirectory'), isFalse);
  });

  test('the two OLD names still mean something, so they are carried', () {
    // `autosaveEnabled` was one switch over every trigger; the closest
    // thing it now names is the pause. `autosaveIntervalMinutes` was a
    // clock a build in between dropped — a user who had set one gets it
    // back rather than silently starting from the default.
    final revived = AppSaveSettings.fromJson(const {
      'autosaveEnabled': false,
      'autosaveIntervalMinutes': 12,
    });
    expect(revived.pauseSnapshotEnabled, isFalse);
    expect(revived.periodicSnapshotMinutes, 12);
    // The switch the old name never covered keeps its own default.
    expect(revived.lifecycleSnapshotEnabled, isTrue);
    // And the new name wins when both are present.
    expect(
      AppSaveSettings.fromJson(const {
        'autosaveEnabled': false,
        'pauseSnapshotEnabled': true,
      }).pauseSnapshotEnabled,
      isTrue,
    );
  });

  test('a non-positive interval is OFF, not a clock that never stops', () {
    for (final bad in const <Object?>[0, -5, 'ten', null]) {
      expect(
        AppSaveSettings.fromJson({'periodicSnapshotMinutes': bad})
            .periodicSnapshotMinutes,
        isNull,
        reason: 'for $bad',
      );
    }
  });

  test('store roundtrip; missing/corrupt files yield null', () async {
    final directory = await Directory.systemTemp.createTemp('save-settings');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppSaveSettingsStore(
      filePath: '${directory.path}/save_settings.json',
    );
    expect(await store.load(), isNull);
    const settings = AppSaveSettings(recordingsDirectory: '/takes');
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
