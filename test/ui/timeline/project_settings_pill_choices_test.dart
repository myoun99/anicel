// THE SETTINGS BUTTON'S VALUE ROWS OPEN A CHOICE WINDOW, AND THE ROW YOU
// PICK IS THE SETTING YOU GET.
//
// 유저 2026-08-27: the menu is VALUE ROWS, and each row opens its own small
// change window. Two of those rows — the project audio sample rate and the
// playback quality — asked the same question the same way and were one
// body copied twice; G3 (2026-09-07) made them one `_editChoice` differing
// only in values, and these are the pins that say the two branches still
// behave. Without them the shared body could apply the wrong setting, or
// the wrong preset, and nothing would say so.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';
import 'package:anicel/src/ui/timeline/project_settings_pill.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() => session.dispose());

  Future<void> pumpPill(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: ProjectSettingsPill(session: session))),
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
    final target = ProjectSettingsPill.audioSampleRatePresets.firstWhere(
      (preset) => preset != before,
    );

    await pumpPill(tester);
    await openRow(tester, 'project-settings-audio-rate');

    // Every preset is a row, and only the presets are.
    for (final preset in ProjectSettingsPill.audioSampleRatePresets) {
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

  testWidgets('the quality row picks the quality the tapped preset says — the '
      'SAME body, a different setting', (tester) async {
    final before = session.playbackRig.playbackQuality;
    final rateBefore = session.projectAudio.projectAudioSampleRate;
    final target = PlaybackQuality.values.firstWhere(
      (preset) => preset != before,
    );

    await pumpPill(tester);
    await openRow(tester, 'project-settings-quality');

    for (final preset in PlaybackQuality.values) {
      expect(
        find.byKey(ValueKey<String>('playback-quality-${preset.name}')),
        findsOneWidget,
      );
      expect(
        find.text(PlaybackTransportControls.qualityLabel(preset)),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(ValueKey<String>('playback-quality-${target.name}')),
    );
    await tester.pumpAndSettle();

    expect(session.playbackRig.playbackQuality, target);
    expect(
      session.projectAudio.projectAudioSampleRate,
      rateBefore,
      reason: 'the shared body applied the quality, not the sample rate',
    );
  });

  testWidgets('closing a choice window without picking changes nothing', (
    tester,
  ) async {
    final before = session.projectAudio.projectAudioSampleRate;

    await pumpPill(tester);
    await openRow(tester, 'project-settings-audio-rate');
    // The window's own close, which pops NOTHING — the null the shared body
    // reads as "cancelled".
    Navigator.of(tester.element(find.byType(ProjectSettingsPill))).pop();
    await tester.pumpAndSettle();

    expect(session.projectAudio.projectAudioSampleRate, before);
  });
}
