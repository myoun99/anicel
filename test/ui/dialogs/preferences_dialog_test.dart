import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';

/// SAVE-1: the unified Preferences dialog — sections switch in place and
/// the Autosave section drives the live save policy.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() {
    session.dispose();
    AppSave.settings.value = const AppSaveSettings();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Future<void> pumpPreferences(
    WidgetTester tester, {
    PreferencesSection initialSection = PreferencesSection.input,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPreferencesDialog(
                context,
                session: session,
                initialSection: initialSection,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sections switch in place: Input first, every section '
      'reachable from the rail', (tester) async {
    // ⚠️The tab strip SCROLLS by design (`AppWindow._tabBar`) — the window's
    // width is not allowed to be decided by how many tabs it carries — so
    // reaching the last ones means scrolling to them, exactly as a user
    // does. Tapping without this silently misses once a tab lands past the
    // strip's right edge, which is what the seventh section did.
    Future<void> openSection(String name) async {
      final tab = find.byKey(ValueKey<String>('preferences-section-$name'));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    await pumpPreferences(tester);
    expect(
      find.byKey(const ValueKey<String>('preferences-dialog')),
      findsOneWidget,
    );
    // Input is the landing section.
    expect(
      find.byKey(const ValueKey<String>('settings-pressure-curve')),
      findsOneWidget,
    );

    await openSection('autosave');
    expect(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
      findsOneWidget,
    );

    await openSection('audio');
    expect(
      find.byKey(const ValueKey<String>('settings-av-offset-value')),
      findsOneWidget,
    );

    await openSection('language');
    expect(
      find.byKey(const ValueKey<String>('settings-program-language')),
      findsOneWidget,
    );

    await openSection('accent');
    expect(
      find.byKey(const ValueKey<String>('settings-accent1-swatch')),
      findsOneWidget,
    );

    await openSection('display');
    expect(
      find.byKey(const ValueKey<String>('ui-scale-stop-100')),
      findsOneWidget,
    );

    await openSection('system');
    expect(
      find.byKey(const ValueKey<String>('system-status-section')),
      findsOneWidget,
    );
  });

  testWidgets('🚨F-1: the Autosave section is ONE switch and ONE slider', (
    tester,
  ) async {
    await pumpPreferences(tester, initialSection: PreferencesSection.autosave);

    // ⛔Three switches stood here — leaving the app, pausing, and the
    // clock — and two of them named triggers that no longer exist
    // (유저 2026-08-26: 「자동저장 on off만 남기고 … 심플하게 명시적저장 /
    // n분주기 자동저장만 남김」). Asserted rather than merely deleted, so
    // putting a trigger back has to argue with a test.
    expect(
      find.byKey(const ValueKey<String>('settings-autosave-pause')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-autosave-periodic')),
      findsNothing,
    );
    for (final minutes in const <int>[5, 10, 20, 30]) {
      expect(
        find.byKey(ValueKey<String>('settings-autosave-$minutes')),
        findsNothing,
        reason: 'the four chips are a slider now',
      );
    }

    // ⛔The slider's ROW is here whether autosave is on or off — 없다가
    // 생기는 UI 금지. It goes inert instead of absent.
    final slider = find.byKey(
      const ValueKey<String>('settings-autosave-minutes'),
    );
    expect(AppSave.settings.value.periodicSnapshotMinutes, isNull);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    expect(slider, findsOneWidget, reason: 'reserved while switched off');
    expect(
      tester.widget<FieldSlider>(slider).onChanged,
      isNull,
      reason: 'and inert — a null onChanged dims it and refuses input',
    );

    // Scrolled back into view first: the section has grown below (the
    // recovery-snapshot list), and a tap that misses records nothing.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
    );
    await tester.pumpAndSettle();
    expect(
      AppSave.settings.value.periodicSnapshotMinutes,
      AppSaveSettings.defaultPeriodicSnapshotMinutes,
    );

    // The track is the model's range, in whole minutes.
    final live = tester.widget<FieldSlider>(slider);
    expect(live.min, AppSaveSettings.minPeriodicSnapshotMinutes.toDouble());
    expect(live.max, AppSaveSettings.maxPeriodicSnapshotMinutes.toDouble());
    expect(live.onChanged, isNotNull);
    live.onChanged!(23.4);
    await tester.pumpAndSettle();
    expect(
      AppSave.settings.value.periodicSnapshotMinutes,
      23,
      reason: 'whole minutes — the clock cannot use a fraction',
    );

    // Off again, and the number goes with it.
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-autosave-enabled')),
    );
    await tester.pumpAndSettle();
    expect(AppSave.settings.value.periodicSnapshotMinutes, isNull);

    // The sidecar-folder row is GONE: the recovery snapshot lives in the
    // app's own support folder and there is nothing to point anywhere.
    // Asserted rather than merely deleted, so re-adding a control for a
    // location that no longer varies has to argue with a test.
    expect(
      find.byKey(const ValueKey<String>('settings-sidecar-custom')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-sidecar-browse')),
      findsNothing,
    );

    // 🪦**THE RECORDINGS FOLDER ROW WAS ASSERTED HERE** — the live shelf
    // path, a custom choice, and the reset back to the default. The row is
    // gone with the folder it configured (유저 2026-09-08: 앱이 쓰는 곳은
    // 앱 컨테이너와 프로젝트 파일 둘뿐), so a take is staged like every
    // other carried asset and there is nothing left to point anywhere.
  });

  testWidgets('the Audio section drives the live A/V offset: typed values '
      'clamp, the unit switch keeps the number, and the inspector reports '
      'the fallback while no device is open', (tester) async {
    await pumpPreferences(tester, initialSection: PreferencesSection.audio);

    final offset = find.byKey(
      const ValueKey<String>('settings-av-offset-value'),
    );
    await tester.enterText(offset, '120');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(session.appSettings.audioSyncSettings.value.offset, 120);
    expect(session.appSettings.audioSyncSettings.value.unit, AvOffsetUnit.milliseconds);

    // A typo-sized value clamps instead of being accepted as a "setup"
    // (5000 ms of shift would just look like a sync bug).
    await tester.enterText(offset, '5000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      session.appSettings.audioSyncSettings.value.offset,
      AudioSyncSettings.maxMilliseconds,
    );

    // Switching units keeps the typed number, re-clamped for the unit.
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-av-offset-unit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('frames').last);
    await tester.pumpAndSettle();
    expect(session.appSettings.audioSyncSettings.value.unit, AvOffsetUnit.frames);
    expect(
      session.appSettings.audioSyncSettings.value.offset,
      AudioSyncSettings.maxFrames,
    );

    // No device in widget tests → the inspector says so rather than
    // showing nothing.
    expect(
      find.textContaining('not open', findRichText: true),
      findsOneWidget,
    );
  });
}
