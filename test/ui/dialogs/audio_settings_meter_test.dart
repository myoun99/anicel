import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/dialogs/audio_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_input_monitor.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';

/// The settings meter + test tone (REC1-D2): lifecycle contracts under
/// the graceful-absence rule — no device in tests, nothing crashes, the
/// UI mounts inert.
void main() {
  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  test('REC1-D2: a device-less monitor stays inert and safe', () {
    final monitor = AudioInputMonitor();
    expect(monitor.start(), isFalse);
    expect(monitor.isRunning, isFalse);
    expect(monitor.peak.value, 0);
    monitor.stop();
    monitor.dispose();
  });

  test('REC1-D2: the meter yields to the recorder and the session cleans '
      'up on detach', () {
    final manager = session();
    final monitor = manager.attachInputMeter();
    expect(identical(manager.attachInputMeter(), monitor), isTrue,
        reason: 'one monitor per session');
    // Arming a take (fake recorder) must not fight the meter.
    manager.selectLayer(manager.activeTrack.seLayers.first.id);
    manager.debugVoiceRecorderFactory = () => _FakeRecorder();
    expect(manager.startVoiceRecording(), VoiceRecordStartResult.started);
    expect(monitor.isRunning, isFalse, reason: 'the recorder owns the mic');
    manager.stopVoiceRecordingAndPlace();
    manager.detachInputMeter();
    expect(manager.playOutputTestTone(), isFalse,
        reason: 'graceful absence: no device in tests');
    manager.dispose();
  });

  testWidgets('REC1-D2: the settings section mounts the meter bar, clip '
      'dot and test button', (tester) async {
    final manager = session();
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AudioSettingsSection(session: manager),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-input-meter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-input-meter-clip')),
      findsOneWidget,
    );
    final testButton = find.byKey(
      const ValueKey<String>('settings-output-test-button'),
    );
    expect(testButton, findsOneWidget);
    await tester.tap(testButton);
    await tester.pumpAndSettle();
  });
}

/// A microphone stand-in that always arms and returns an empty take.
class _FakeRecorder extends AudioRecorder {
  bool _started = false;

  @override
  bool get isRecording => _started;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    _started = true;
    return 48000;
  }

  @override
  AudioRecording? stop() {
    _started = false;
    return null;
  }
}
