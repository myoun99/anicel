import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/timeline/instruction_icon_palette.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🗣️F-230 (유저 2026-09-29): 「오디오의 출력 선택이나 트랜지션레이어의 ol선택등
/// 선택하는 ui가 구식 ui 쓰는곳있는데, 앵커팝오버? 공용화된 ui 통일적용.
/// 다른곳도 확인해서」.
///
/// Every picker Preferences has is the shared flyout now: its button opens
/// the one list and a row writes the setting. Driven the way a hand does —
/// the button, then the row — so a picker that went back to a framework menu
/// has no rows under these keys to tap.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() {
    session.dispose();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Finder byKey(String key) => find.byKey(ValueKey<String>(key));

  Future<void> pumpPreferences(
    WidgetTester tester,
    PreferencesSection section,
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
                initialSection: section,
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

  /// Opens [button]'s list and picks the row keyed [row].
  Future<void> pick(WidgetTester tester, Finder button, String row) async {
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(byKey(row));
    await tester.pumpAndSettle();
  }

  testWidgets('input: a touch slot and a canvas mapping are picked from the '
      'list — and the release only a held tool has stays shut', (
    tester,
  ) async {
    await pumpPreferences(tester, PreferencesSection.input);

    await pick(
      tester,
      byKey('settings-touch-slot-1'),
      'settings-touch-slot-1-navigate',
    );
    expect(
      AppInput.settings.value.touchDragOneFinger,
      CanvasTouchDragAction.navigate,
    );

    final release = byKey('settings-canvas-right-release');
    await pick(
      tester,
      byKey('settings-canvas-right-action'),
      'settings-canvas-right-action-pan',
    );
    expect(
      AppInput.settings.value.canvasRightClick.action,
      CanvasPointerAction.pan,
    );
    await tester.ensureVisible(release);
    await tester.pumpAndSettle();
    await tester.tap(release, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      byKey('settings-canvas-right-release-keep'),
      findsNothing,
      reason: 'a pan is not a tool held — its release has nothing to pick',
    );

    await pick(
      tester,
      byKey('settings-canvas-right-action'),
      'settings-canvas-right-action-eraser',
    );
    await pick(tester, release, 'settings-canvas-right-release-keep');
    expect(
      AppInput.settings.value.canvasRightClick.release,
      CanvasPointerRelease.keep,
    );
  });

  testWidgets('audio: a saved device that is gone still shows in the list; '
      'the system default is picked from it like any other row', (
    tester,
  ) async {
    session.appSettings.setAudioSyncSettings(
      session.appSettings.audioSyncSettings.value.copyWith(
        outputDeviceName: 'Studio Monitor',
      ),
    );
    await pumpPreferences(tester, PreferencesSection.audio);

    final output = byKey('settings-audio-output-device');
    await tester.ensureVisible(output);
    await tester.pumpAndSettle();
    await tester.tap(output);
    await tester.pumpAndSettle();
    expect(
      byKey('settings-audio-output-device-device-Studio Monitor'),
      findsOneWidget,
      reason: 'the choice is visible rather than silently reverted',
    );
    await tester.tap(byKey('settings-audio-output-device-system-default'));
    await tester.pumpAndSettle();
    expect(
      session.appSettings.audioSyncSettings.value.outputDeviceName,
      isNull,
    );

    await pick(
      tester,
      byKey('settings-input-channel-mode'),
      'settings-input-channel-mode-left',
    );
    expect(
      session.appSettings.audioSyncSettings.value.inputChannelMode,
      VoiceInputChannelMode.left,
    );
  });

  testWidgets('language: the notation language is picked from the list', (
    tester,
  ) async {
    await pumpPreferences(tester, PreferencesSection.language);
    final before = session.languageSettings.value.notationLanguage;
    final other = AppLanguage.values.firstWhere(
      (language) => language != before,
    );

    await pick(
      tester,
      find.descendant(
        of: byKey('settings-notation-language'),
        matching: find.byType(PanelFlyoutButton),
      ),
      'language-option-${other.name}',
    );
    expect(session.languageSettings.value.notationLanguage, other);
  });

  testWidgets('the instruction picker wears the kind it holds — the glyph '
      'the list gives that kind', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InstructionEventDialog(
            instructionSet: CameraInstructionSet.standard,
            initialInstructionId: 'pan',
          ),
        ),
      ),
    );
    final button = byKey('instruction-def-dropdown');
    Finder wearing(String iconKey) => find.descendant(
      of: button,
      matching: find.byIcon(instructionIconFor(iconKey)),
    );
    expect(wearing('pan'), findsOneWidget);

    await pick(tester, button, 'instruction-option-ol');
    expect(wearing('overlap'), findsOneWidget);
    expect(wearing('pan'), findsNothing);
  });

  testWidgets('a project tab waiting in the overflow list is picked from it', (
    tester,
  ) async {
    // The test window's strip holds no two tabs, so they wait in its list —
    // the row's own rule (see `project_tabs_test`).
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    final first = projects.active;
    await pick(tester, byKey('top-strip-project-button'), 'menu-file-new');
    expect(identical(projects.active, first), isFalse);

    await pick(tester, byKey('project-tab-overflow'), 'project-tab-overflow-0');
    expect(identical(projects.active, first), isTrue);
  });
}
