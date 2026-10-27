import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/timeline/instruction_icon_palette.dart';

import '../../helpers/native_engine_path.dart';

/// 🗣️F-230 (유저 2026-09-29): 「오디오의 출력 선택이나 트랜지션레이어의 ol선택등
/// 선택하는 ui가 구식 ui 쓰는곳있는데, 앵커팝오버? 공용화된 ui 통일적용.
/// 다른곳도 확인해서」.
///
/// Every picker Preferences has is the shared flyout now: its button opens
/// the one list and a row writes the setting. Driven the way a hand does —
/// the button, then the row — so a picker that went back to a framework menu
/// has no rows under these keys to tap.
void main() {
  final enginePath = nativeEngineLibraryPathOrNull();
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

  // play-press-first-frame-stall-Q1 (유저 10-15): 「출력 장치 설정을 바꾸면
  // 그때 백그라운드에서 다시 엽니다」.
  testWidgets('🚨audio: the output follows the device picked — opened again '
      'off the UI thread once the frame that lists the outputs is drawn', (
    tester,
  ) async {
    if (enginePath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = enginePath;
    addTearDown(() {
      QaAudioDevice.instance?.close();
      QaAudioDevice.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
    });
    // The bench's device: opened once on the null backend, so the program's
    // own road opens it there again.
    final device = QaAudioDevice.instance!;
    expect(device.open(useNullBackend: true), greaterThan(0));
    device.close();
    session.playbackRig.debugTransportOutput = () => device;
    session.appSettings.setAudioSyncSettings(
      session.appSettings.audioSyncSettings.value.copyWith(
        outputDeviceName: 'Studio Monitor',
      ),
    );
    session.playbackRig.audioDeviceTransport.openAhead();
    await tester.pump();
    expect(device.openedFor, 'Studio Monitor', reason: 'fixture');
    await pumpPreferences(tester, PreferencesSection.audio);

    final output = byKey('settings-audio-output-device');
    await tester.ensureVisible(output);
    await tester.pumpAndSettle();
    await tester.tap(output);
    await tester.pumpAndSettle();
    await tester.tap(byKey('settings-audio-output-device-system-default'));
    expect(device.openedFor, 'Studio Monitor',
        reason: 'not before the frame: a list asked for while the worker '
            'opens waits on the C');
    await tester.pumpAndSettle();

    expect(device.isOpen, isTrue);
    expect(device.openedFor, isNull, reason: 'the system default');
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
      byKey('settings-notation-language'),
      'settings-notation-language-${other.name}',
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
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    // However wide the strip, projects are opened until one waits in its
    // list — the row's own rule (see `the_top_strip_gives_way_test`). A new
    // project opens, so the one before it is the first to wait that is not
    // the open one.
    int before() => projects.sessions.length - 2;
    bool oneWaits() =>
        before() >= 0 && byKey('project-tab-${before()}').evaluate().isEmpty;
    for (var opened = 0; !oneWaits(); opened += 1) {
      expect(opened, lessThan(16), reason: '⛔the strip never fills');
      await pick(tester, byKey('top-strip-project-button'), 'menu-file-new');
    }
    final waiting = projects.sessions[before()];
    expect(identical(projects.active, waiting), isFalse);

    await pick(
      tester,
      byKey('project-tab-overflow'),
      'project-tab-overflow-${before()}',
    );
    expect(identical(projects.active, waiting), isTrue);
  });
}
