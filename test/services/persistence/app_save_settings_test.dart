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

  test('🚨F-1 defaults: autosave OFF, and the clock is the whole policy', () {
    const settings = AppSaveSettings();
    // Two switches used to stand beside this one — leaving the app, and
    // pausing — and they are gone with their triggers (유저 2026-08-26:
    // 「자동저장 on off만 남기고 … 심플하게 명시적저장 / n분주기 자동저장
    // 만 남김」).
    expect(settings.periodicSnapshotMinutes, isNull);
    expect(settings.toJson().keys, unorderedEquals(const [
      'periodicSnapshotMinutes',
    ]));
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
    const settings = AppSaveSettings(periodicSnapshotMinutes: 20);
    expect(AppSaveSettings.fromJson(settings.toJson()), settings);
    expect(
      AppSaveSettings.fromJson(const AppSaveSettings().toJson()),
      const AppSaveSettings(),
    );
    expect(
      settings.copyWith().periodicSnapshotMinutes,
      20,
      reason: 'an empty copyWith keeps what it was not given',
    );
    expect(
      settings.copyWith(periodicSnapshotMinutes: null).periodicSnapshotMinutes,
      isNull,
      reason: 'and it can EXPLICITLY clear back to OFF',
    );
    // 🪦A conform folder and a recordings folder used to ride here too.
    // There are no folder settings left: a conform waits in the run's room
    // and a take is staged beside it, both absorbed by the next save.
  });

  // 🪦**TWO CASES STOOD HERE AND BOTH BELONGED TO THE ONE CONFIGURABLE
  // FOLDER.** Q-scoped-folder-settings pinned that a stored folder keeps
  // its TOKEN, not just its path, and that resolving it at launch reopens
  // a moved one while leaving an unresolvable one UNTOUCHED. The folder is
  // gone (유저 2026-09-08: 앱이 쓰는 곳은 앱 컨테이너와 프로젝트 파일
  // 둘뿐), so `resolveSettingsDirectories` had nothing left to resolve.
  // ⛔The LAW is not gone and `GrantedDirectory` still carries it for the
  // export dialog — see `app_export_settings_store_test`.

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
    const settings = AppSaveSettings(periodicSnapshotMinutes: 20);
    await store.save(settings);
    expect(await store.load(), settings);

    await File(store.filePath).writeAsString('not json');
    expect(await store.load(), isNull);
  });
}
