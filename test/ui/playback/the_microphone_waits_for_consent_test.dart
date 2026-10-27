import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_input_monitor.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/timeline/frame_panel_transport.dart';

/// 🗣️I-133 (유저 2026-10-26): 「환경설정 오디오탭에 입력항목에 마이크 허용버튼
/// 신설. 이게 허용되어있지 않으면 일절 마이크를 인식안함. 즉 앞으로는 앱 키고 이
/// 허용을 체크해야 권한묻도록 … 이게 체크 해제되있으면 마이크를 사용해야하는
/// 상황(타임라인에서 녹음버튼)에서 허용 체크해달라고 메시지 띄우도록」.
///
/// The consent stands where a microphone opens — a take and the settings
/// meter — and the OS is asked only behind it.
void main() {
  tearDown(() => AppStorage.debugMicrophoneAccess = null);

  const allowed = AudioSyncSettings(microphoneAllowed: true);

  test('without consent a take opens nothing — no device, no lane', () async {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final microphone = _Microphone();
    session.voiceRecording.debugVoiceRecorderFactory = microphone.lend;
    final lanes = session.activeTrack.seLayers.length;

    expect(
      session.voiceRecording.startVoiceRecording(),
      VoiceRecordStartResult.notAllowed,
    );
    expect(microphone.opened, 0);
    expect(session.activeTrack.seLayers, hasLength(lanes));
    expect(session.voiceRecording.isVoiceRecording.value, isFalse);

    session.appSettings.setAudioSyncSettings(allowed);
    expect(
      session.voiceRecording.startVoiceRecording(),
      VoiceRecordStartResult.started,
      reason: 'premise: the same press records once it is allowed',
    );
    expect(microphone.opened, 1);
    await session.voiceRecording.stopVoiceRecordingAndPlace();
  });

  test('the settings meter stays shut without consent, opens with it, and '
      'shuts when it is taken back', () {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    final meter = _Meter();
    session.voiceRecording.debugInputMonitorFactory = () => meter;

    session.voiceRecording.attachInputMeter();
    expect(meter.starts, 0);

    session.appSettings.setAudioSyncSettings(allowed);
    session.voiceRecording.restartInputMeter();
    expect(meter.starts, 1);
    expect(meter.isRunning, isTrue);

    session.appSettings.setAudioSyncSettings(AudioSyncSettings.defaults);
    session.voiceRecording.restartInputMeter();
    expect(meter.isRunning, isFalse);
    expect(meter.starts, 1);
    session.voiceRecording.detachInputMeter();
  });

  group('the record press', () {
    Future<EditorSessionManager> pumpTransport(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: FramePanelTransport(
                session: session,
                panel: WorkingPanel.timeline,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return session;
    }

    Future<void> press(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('playback-record-voice-button')),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> closeTheNotice(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
      await tester.pumpAndSettle();
    }

    testWidgets('without consent it asks the OS nothing, opens nothing, and '
        'says where to allow it', (tester) async {
      final session = await pumpTransport(tester);
      var asked = 0;
      AppStorage.debugMicrophoneAccess = () async {
        asked += 1;
        return true;
      };
      final microphone = _Microphone();
      session.voiceRecording.debugVoiceRecorderFactory = microphone.lend;

      await press(tester);
      expect(asked, 0);
      expect(microphone.opened, 0);
      expect(find.text(session.uiStrings.recordMicNotAllowed), findsOneWidget);
      await closeTheNotice(tester);
    });

    testWidgets('with consent it asks the OS first, and only a yes opens the '
        'microphone', (tester) async {
      final session = await pumpTransport(tester);
      session.appSettings.setAudioSyncSettings(allowed);
      var answer = false;
      var asked = 0;
      AppStorage.debugMicrophoneAccess = () async {
        asked += 1;
        return answer;
      };
      final microphone = _Microphone();
      session.voiceRecording.debugVoiceRecorderFactory = microphone.lend;

      await press(tester);
      expect(asked, 1);
      expect(microphone.opened, 0);
      expect(
        find.text(session.uiStrings.recordMicPermissionDenied),
        findsOneWidget,
      );
      await closeTheNotice(tester);

      answer = true;
      await press(tester);
      expect(asked, 2);
      expect(microphone.opened, 1);
      expect(session.voiceRecording.isVoiceRecording.value, isTrue);
      await session.voiceRecording.stopVoiceRecordingAndPlace();
      await tester.pumpAndSettle();
    });
  });
}

/// A microphone stand-in that counts how often it was opened and hands
/// back nothing — what these pins ask is whether it opened at all.
class _Microphone {
  int opened = 0;

  AudioRecorder lend() => _Opening(this);
}

class _Opening extends AudioRecorder {
  _Opening(this._microphone);

  final _Microphone _microphone;
  bool _started = false;

  @override
  bool get isRecording => _started;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) {
    _microphone.opened += 1;
    _started = true;
    return 48000;
  }

  @override
  AudioRecording? stop() {
    _started = false;
    return null;
  }
}

/// A meter stand-in that counts its opens.
class _Meter extends AudioInputMonitor {
  int starts = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  bool start({int sampleRate = 48000, int deviceIndex = -1}) {
    starts += 1;
    _running = true;
    return true;
  }

  @override
  void stop() {
    _running = false;
    super.stop();
  }
}
