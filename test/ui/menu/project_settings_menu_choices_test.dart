// THE PROJECT SETTINGS' VALUE ROWS OPEN A CHOICE WINDOW, AND THE ROW YOU
// PICK IS THE SETTING YOU GET.
//
// 유저 2026-08-27: the menu is VALUE ROWS, and each row opens its own small
// change window. Two of those rows — the project audio sample rate and the
// playback quality — asked the same question the same way and were one
// body copied twice; G3 (2026-09-07) made them one `_editChoice` differing
// only in values, and these are the pins that say it still behaves.
// Without them the shared body could apply the wrong setting, or the wrong
// preset, and nothing would say so. ↩️The playback quality left with its
// option (2026-10-08), so the sample rate is the one row pinned here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/menu/project_settings_menu.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() => session.dispose());

  /// The rows as the top strip's ⚙ shows them: a flyout of
  /// [ProjectSettingsMenu.entries] for [of] — the test's session unless
  /// given — opened from a button.
  Future<void> pumpMenu(
    WidgetTester tester, {
    EditorSessionManager? of,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                key: const ValueKey<String>('project-settings-button'),
                onPressed: () => showPanelFlyout(
                  context,
                  entries: ProjectSettingsMenu(of ?? session).entries(context),
                ),
                child: const Text('Project settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRow(WidgetTester tester, String rowKey) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(rowKey)));
    await tester.pumpAndSettle();
  }

  testWidgets('the audio-rate row picks the rate the tapped preset says', (
    tester,
  ) async {
    final before = session.projectAudio.projectAudioSampleRate;
    final target = ProjectSettingsMenu.audioSampleRatePresets.firstWhere(
      (preset) => preset != before,
    );

    await pumpMenu(tester);
    await openRow(tester, 'project-settings-audio-rate');

    // Every preset is a row, and only the presets are.
    for (final preset in ProjectSettingsMenu.audioSampleRatePresets) {
      expect(
        find.byKey(ValueKey<String>('timeline-samplerate-$preset')),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-samplerate-$target')),
    );
    await tester.pumpAndSettle();

    expect(session.projectAudio.projectAudioSampleRate, target);
  });

  testWidgets('the menu is a value row per setting, and the FPS row opens the '
      'presets with a rate of one\'s own', (tester) async {
    await pumpMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-button')),
    );
    await tester.pumpAndSettle();

    // 유저 2026-08-27: the menu is VALUE ROWS, one per setting — the
    // choices themselves are in each row's change window.
    for (final row in [
      'project-settings-fps',
      'project-settings-audio-rate',
      'project-settings-camera-size',
    ]) {
      expect(find.byKey(ValueKey<String>(row)), findsOneWidget, reason: row);
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('project-settings-fps')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('timeline-fps-24')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('project-fps-field')),
      findsOneWidget,
    );
  });

  testWidgets('the camera row opens the size window, and applying writes '
      'one undoable project frame', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Disposed at the BODY's end, not in a tearDown: the edit below arms
    // the session's debounce timers, and the pending-timer invariant runs
    // before tearDowns do.
    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final before = manager.camera.cameraFrameSize;

    await pumpMenu(tester, of: manager);
    await openRow(tester, 'project-settings-camera-size');

    await tester.enterText(
      find.byKey(const ValueKey<String>('camera-size-width-field')),
      '960',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('camera-size-height-field')),
      '430',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('camera-size-apply-button')),
    );
    await tester.pumpAndSettle();

    expect(
      manager.camera.cameraFrameSize,
      const CanvasSize(width: 960, height: 430),
    );

    manager.undo();
    expect(manager.camera.cameraFrameSize, before);

    await tester.pumpWidget(const SizedBox.shrink());
    manager.dispose();
  });

  testWidgets('closing a choice window without picking changes nothing', (
    tester,
  ) async {
    final before = session.projectAudio.projectAudioSampleRate;

    await pumpMenu(tester);
    await openRow(tester, 'project-settings-audio-rate');
    // The window's own close, which pops NOTHING — the null the shared body
    // reads as "cancelled".
    Navigator.of(tester.element(find.byType(TextButton))).pop();
    await tester.pumpAndSettle();

    expect(session.projectAudio.projectAudioSampleRate, before);
  });
}
