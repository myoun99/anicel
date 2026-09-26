import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/services/persistence/app_input_settings_store.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart'
    show DragVerbClaim;
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🗣️F-191 (유저 2026-09-27): 「환경설정에서 필압곡선이나 속도곡선이 앱
/// 재기동하면 초기화되있음. 앱 설정으로서 저장하게하고 설정창 등
/// 다른곳에서도 문제파악」.
///
/// A RUN is the settings object the shell builds and restores once; the
/// next run is a new one on the SAME store. What the user set in one must
/// be what the next opens with — asked through the real controls: a drag
/// on the Preferences sliders, a press on the toolbar's toggle.
void main() {
  tearDown(() => AppInput.settings.value = AppInputSettings.testCorpusBaseline);

  /// A run: the app's settings on [store], restored, and a session on them.
  EditorSessionManager run(_RecordingInputStore store) {
    final settings = EditorAppSettings(inputSettingsStore: store)..restore();
    addTearDown(settings.dispose);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      appSettings: settings,
    );
    addTearDown(session.dispose);
    return session;
  }

  /// The next run on [store], with the live value put back first — or a
  /// restore could "pass" on the notifier still holding the last pick.
  Future<void> restart(WidgetTester tester, _RecordingInputStore store) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    run(store);
    await tester.pump();
  }

  Future<void> openInputPreferences(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPreferencesDialog(
                context,
                session: session,
                openSessions: [session],
                initialSection: PreferencesSection.input,
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

  Finder barOf(String key) => find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(DragVerbClaim),
  );

  testWidgets('the pressure curve dragged in Preferences is the one the next '
      'run opens with', (tester) async {
    final store = _RecordingInputStore();
    await openInputPreferences(tester, run(store));
    final before = AppInput.settings.value.pressureCurveGamma;

    await tester.drag(barOf('settings-pressure-curve'), const Offset(60, 0));
    await tester.pumpAndSettle();
    final dragged = AppInput.settings.value.pressureCurveGamma;
    expect(dragged, isNot(before), reason: 'premise: the drag moved it');
    expect(
      store.saved?.pressureCurveGamma,
      dragged,
      reason: 'the release writes it down — the drag had already previewed '
          'the same value, and the guard used to take that for "saved"',
    );

    expect(
      store.saves,
      1,
      reason: 'ONE write for the drag — the steps preview, the release '
          'commits (the guard\'s own reason: a disk touch per step)',
    );

    await restart(tester, store);
    expect(AppInput.settings.value.pressureCurveGamma, dragged);

    // What the next run read back is what the file holds: setting it again
    // writes nothing.
    final session = run(store);
    session.setInputSettings(AppInput.settings.value);
    await tester.pump();
    expect(store.saves, 1, reason: 'the restored value is already held');
  });

  testWidgets('so is the speed reference', (tester) async {
    final store = _RecordingInputStore();
    await openInputPreferences(tester, run(store));
    final before = AppInput.settings.value.speedReferencePixelsPerSecond;

    await tester.drag(barOf('settings-speed-reference'), const Offset(60, 0));
    await tester.pumpAndSettle();
    final dragged = AppInput.settings.value.speedReferencePixelsPerSecond;
    expect(dragged, isNot(before), reason: 'premise: the drag moved it');
    expect(store.saved?.speedReferencePixelsPerSecond, dragged);

    await restart(tester, store);
    expect(AppInput.settings.value.speedReferencePixelsPerSecond, dragged);
  });

  testWidgets('the toolbar\'s 「프레임 자동 생성」 is written down too', (
    tester,
  ) async {
    final store = _RecordingInputStore();
    final session = run(store);
    await tester.binding.setSurfaceSize(const Size(1600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Row(
            children: [
              TimelineActionToolbar(
                session: session,
                panelContext: TimelineToolbarPanelContext(session),
                onAddLayer: () {},
                onRenameLayer: () {},
                onDeleteLayer: () {},
                onEditInstance: () {},
                onCreateInstance: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = AppInput.settings.value.autoCreateFrameOnDraw;

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppIconButton && w.keyValue == 'auto-frame-toggle-button',
      ),
    );
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.autoCreateFrameOnDraw, !before);
    expect(store.saved?.autoCreateFrameOnDraw, !before);

    await restart(tester, store);
    expect(AppInput.settings.value.autoCreateFrameOnDraw, !before);
  });
}

/// An input store that keeps what it was handed instead of writing a file —
/// the round trip through a real file is `editor_app_settings_test`'s.
class _RecordingInputStore extends AppInputSettingsStore {
  _RecordingInputStore() : super(filePath: 'unused/input_settings.json');

  AppInputSettings? saved;
  int saves = 0;

  @override
  Future<AppInputSettings?> load() async => saved;

  @override
  Future<void> save(AppInputSettings settings) async {
    saved = settings;
    saves += 1;
  }
}
