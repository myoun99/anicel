import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/app_save_settings_store.dart';

/// SAVE-1: the save/recovery policy — defaults, persistence, and where a
/// recovery snapshot is looked for now that its location is no longer a
/// setting (the app's own support folder, with the old beside-the-file
/// spot still checked so a crash from a previous build is not stranded).
void main() {
  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
  });

  test('🚨F-1 defaults: autosave OFF, and the clock is the whole policy', () {
    const settings = AppSaveSettings();
    // Two switches used to stand beside this one — leaving the app, and
    // pausing — and they are gone with their triggers (유저 2026-08-26:
    // 「자동저장 on off만 남기고 … 심플하게 명시적저장 / n분주기 자동저장
    // 만 남김」).
    expect(settings.periodicSnapshotMinutes, isNull);
    expect(settings.toJson().keys, unorderedEquals(<String>[
      'periodicSnapshotMinutes',
      'recordingsDirectory',
      'conformDirectory',
    ]));
    // Both folders default to the app's own, so a fresh install writes
    // nothing beside a project.
    expect(settings.recordingsDirectory, isNull);
    expect(settings.conformDirectory, isNull);
  });

  test('the slider\'s range is the model\'s, and it is 3..60 minutes', () {
    // 유저 2026-08-26: 「최소 3분, 최대 60분으로 슬라이더사용」.
    expect(AppSaveSettings.minPeriodicSnapshotMinutes, 3);
    expect(AppSaveSettings.maxPeriodicSnapshotMinutes, 60);
    expect(
      AppSaveSettings.defaultPeriodicSnapshotMinutes,
      inInclusiveRange(
        AppSaveSettings.minPeriodicSnapshotMinutes,
        AppSaveSettings.maxPeriodicSnapshotMinutes,
      ),
      reason: 'the value the switch turns on has to sit on the track',
    );
  });

  test('a stored interval outside the range is CLAMPED onto the track', () {
    // Nothing could have written one — the chips this replaces were
    // 5/10/20/30 — but a stored number is a stranger's number, and a
    // slider whose value sits off its own track is an assert waiting for
    // a settings file.
    expect(
      AppSaveSettings.fromJson(const {
        'periodicSnapshotMinutes': 1,
      }).periodicSnapshotMinutes,
      3,
    );
    expect(
      AppSaveSettings.fromJson(const {
        'periodicSnapshotMinutes': 600,
      }).periodicSnapshotMinutes,
      60,
    );
  });

  test('json roundtrip', () {
    const settings = AppSaveSettings(
      periodicSnapshotMinutes: 20,
      recordingsDirectory: GrantedDirectory(path: '/tmp/takes'),
      conformDirectory: GrantedDirectory(
        path: '/tmp/conforms',
        bookmark: 'Ym9va21hcms=',
      ),
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
    expect(
      settings.copyWith().recordingsDirectory,
      const GrantedDirectory(path: '/tmp/takes'),
    );
    expect(
      settings.copyWith().conformDirectory?.path,
      '/tmp/conforms',
    );
    // The two must not be one field wearing two names: moving the cache
    // must not move the take shelf with it.
    expect(
      settings
          .copyWith(
            conformDirectory: const GrantedDirectory(path: '/elsewhere'),
          )
          .recordingsDirectory,
      const GrantedDirectory(path: '/tmp/takes'),
    );
  });

  test('a folder written by an older build (bare path) still reads — and '
      'the path travels with its token, never apart', () {
    // Q-scoped-folder-settings (유저 08-26 「알아서 맡김」 → A): the value
    // is ONE thing on purpose. A bookmark stored as a second field could
    // outlive the path it belongs to; travelling together makes a stale
    // token unrepresentable.
    final legacy = AppSaveSettings.fromJson(const {
      'recordingsDirectory': r'D:\old\takes',
    });
    expect(
      legacy.recordingsDirectory,
      const GrantedDirectory(path: 'D:/old/takes'),
      reason: 'the bare-string spelling reads as a token-less folder',
    );
    expect(GrantedDirectory.fromJson(''), isNull);
    expect(GrantedDirectory.fromJson(const {'bookmark': 'T'}), isNull);
  });

  test('resolving reopens moved folders and leaves unresolvable ones '
      'UNTOUCHED — unavailable is not deleted', () async {
    FolderPicker.debugBookmarkResolver = (base64, kind) async =>
        base64 == 'MOVED=='
            ? const FolderGrant.granted(
                path: '/mounted/conforms',
                bookmark: 'FRESH==',
              )
            : const FolderGrant.unavailable();
    addTearDown(() => FolderPicker.debugBookmarkResolver = null);

    AppSave.settings.value = const AppSaveSettings(
      recordingsDirectory: GrantedDirectory(
        path: '/gone/takes',
        bookmark: 'DEAD==',
      ),
      conformDirectory: GrantedDirectory(
        path: '/old/conforms',
        bookmark: 'MOVED==',
      ),
    );
    addTearDown(() => AppSave.settings.value = const AppSaveSettings());

    final resolved = await AppSave.resolveSettingsDirectories();
    expect(resolved, isNotNull, reason: 'one folder moved');
    expect(
      resolved!.conformDirectory,
      const GrantedDirectory(path: '/mounted/conforms', bookmark: 'FRESH=='),
    );
    expect(
      resolved.recordingsDirectory,
      const GrantedDirectory(path: '/gone/takes', bookmark: 'DEAD=='),
      reason: 'the provider may simply not be signed in yet — the setting '
          'still names what the user meant',
    );

    // Nothing to resolve, nothing to store.
    AppSave.settings.value = resolved;
    FolderPicker.debugBookmarkResolver = (base64, kind) async =>
        FolderGrant.granted(
          path: base64 == 'FRESH==' ? '/mounted/conforms' : '/gone/takes',
          bookmark: base64,
        );
    expect(await AppSave.resolveSettingsDirectories(), isNull);
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

  test('the OLD interval name is still carried — the clock survived', () {
    // `autosaveIntervalMinutes` was a clock a build in between dropped: a
    // user who had set one gets it back rather than silently starting from
    // the default.
    expect(
      AppSaveSettings.fromJson(const {
        'autosaveIntervalMinutes': 12,
      }).periodicSnapshotMinutes,
      12,
    );
  });

  test('🚨F-1: the two SWITCHES are read and dropped, triggers and all', () {
    // Their triggers are gone, so a stored value is a number the next
    // reader has to work out is dead — the same treatment
    // `sidecarDirectory` got above. ⚠️In particular a settings file that
    // says `autosaveEnabled: false` must NOT come back as a clock that is
    // off: that flag switched the PAUSE, and the clock it now meets is a
    // different question with its own answer.
    final revived = AppSaveSettings.fromJson(const {
      'autosaveEnabled': false,
      'lifecycleSnapshotEnabled': false,
      'pauseSnapshotEnabled': false,
      'periodicSnapshotMinutes': 12,
    });
    expect(revived.periodicSnapshotMinutes, 12);
    expect(revived.toJson().keys, isNot(contains('autosaveEnabled')));
    expect(revived.toJson().keys, isNot(contains('lifecycleSnapshotEnabled')));
    expect(revived.toJson().keys, isNot(contains('pauseSnapshotEnabled')));
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
    const settings = AppSaveSettings(
      recordingsDirectory: GrantedDirectory(path: '/takes'),
    );
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
