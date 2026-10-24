import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_scrubber.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';
import 'package:anicel/src/ui/timeline/frame_panel_transport.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/device_paced.dart';
import '../../helpers/native_engine_path.dart';

/// I-85 — how loud the canvas plays.
///
/// 유저 2026-10-08: 「캔버스에서 재생시 발생하는 소리의 사운드크기를 어디선가
/// 조절하게하고싶음」. Answered 2026-10-24: Q1 「그냥 막대 가로형. 늘
/// 쓰던거」 (the viewer's bar) · Q2 「레벨 미터 오른쪽(줄 끝)」 · Q3 「캔버스
/// 소리 전부」 (a run, a scrub, the count-in's beeps) · Q4 「다시 켜도 기억」.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  /// One track whose SE row sounds `tone.wav` over its first ten frames.
  Project withTone() => Project(
    id: const ProjectId('level-project'),
    name: 'Level',
    createdAt: DateTime.utc(2026, 10, 25),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-a'),
            name: 'A',
            duration: 10,
            canvasSize: const CanvasSize(width: 64, height: 36),
            layers: const [],
          ),
        ],
        seLayers: [
          Layer(
            id: const LayerId('se'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(id: const FrameId('tone'), duration: 1, strokes: const []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('tone'), length: 10),
            },
            audioClips: [
              AudioClip(filePath: 'tone.wav', frameId: const FrameId('tone')),
            ],
          ),
        ],
      ),
    ],
  );

  /// A conform that lands at once: a second of a steady 0.05.
  AudioConformStore residentStore() => AudioConformStore(
    resolveConformPath: (_) => null,
    runner: (request) async => ConformResult(
      outcome: ConformOutcome.built,
      samples: Float32List(48000)..fillRange(0, 48000, 0.05),
      channels: 1,
      sampleRate: 48000,
      frames: 48000,
    ),
    log: (_) {},
  );

  group('the level is the app\'s, and lasts', () {
    test('full is the default and is not written; any other level is', () {
      expect(AudioSyncSettings.defaults.playbackLevel, 1);
      expect(
        AudioSyncSettings.defaults.toJson().containsKey('playbackLevel'),
        isFalse,
      );
      const quieter = AudioSyncSettings(playbackLevel: 0.4);
      final back = AudioSyncSettings.fromJson(quieter.toJson());
      expect(back.playbackLevel, 0.4);
      expect(back, quieter);
      expect(quieter == AudioSyncSettings.defaults, isFalse);
    });

    test('a level read back is a level the bar can stand at', () {
      double read(Object? stored) =>
          AudioSyncSettings.fromJson({'playbackLevel': stored}).playbackLevel;
      expect(read(3), 1);
      expect(read(-1), 0);
      expect(read(null), 1);
      expect(AudioSyncSettings.fromJson(const {}).playbackLevel, 1);
    });
  });

  group('every sound of the canvas is heard at it', () {
    const cue = ScheduledAudioClip(
      filePath: 'cue.wav',
      startFrame: 2,
      endFrameExclusive: 3,
    );
    List<ScheduledAudioClip> schedule({double? level}) {
      const window = PlaybackWindow(
        trackId: TrackId('track'),
        trackStart: 0,
        frames: 10,
      );
      const rate = ProjectFrameRate.integer(10);
      return level == null
          ? buildAudioPlaybackSchedule(
              window: window,
              project: withTone(),
              rate: rate,
              durationSecondsFor: (_) => 1,
              extraClips: [cue],
            )
          : buildAudioPlaybackSchedule(
              window: window,
              project: withTone(),
              rate: rate,
              durationSecondsFor: (_) => 1,
              extraClips: [cue],
              level: level,
            );
    }

    test('a quarter level quarters every entry — the sound and the cue — '
        'and moves nothing else', () {
      final full = schedule();
      final quarter = schedule(level: 0.25);
      expect(full, hasLength(2), reason: 'fixture: the tone and the cue');
      expect(quarter, hasLength(full.length));
      for (final (at, entry) in quarter.indexed) {
        final heard = full[at];
        expect(entry.gain, heard.gain * 0.25, reason: heard.filePath);
        expect(
          ScheduledAudioClip(
            filePath: entry.filePath,
            startFrame: entry.startFrame,
            endFrameExclusive: entry.endFrameExclusive,
            offsetFrames: entry.offsetFrames,
            gain: heard.gain,
            fadeInFrames: entry.fadeInFrames,
            fadeOutFrames: entry.fadeOutFrames,
            pan: entry.pan,
            fadeCurve: entry.fadeCurve,
            volumeKeys: entry.volumeKeys,
          ),
          heard,
          reason: '${heard.filePath}: only the gain moves',
        );
      }
    });

    test('at full, the schedule is the one it always was', () {
      expect(schedule(level: 1), schedule());
    });

    test('the run and the scrub each read the one level the app keeps', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final rig = session.playbackRig;
      final paths = <String, double Function()?>{
        'the device transport': rig.audioDeviceTransport.resolvePlaybackLevel,
        'the scrubber': rig.audioScrubber.resolvePlaybackLevel,
      };
      void expectEvery(double level, String when) {
        for (final path in paths.entries) {
          expect(path.value?.call(), level, reason: '${path.key}, $when');
        }
      }

      expectEvery(1, 'before the bar moves');
      rig.setPlaybackLevel(0.3);
      expect(session.appSettings.audioSyncSettings.value.playbackLevel, 0.3);
      expectEvery(0.3, 'once a step is kept');
      rig.settlePlaybackLevel(0.6);
      expectEvery(0.6, 'once the hand lets go');
    });

    test('🚨a run is heard at the level where the hand lets go of it, '
        'without stopping', () async {
      final device = QaAudioDevice.instance!;
      expect(device.open(useNullBackend: true), greaterThan(0));
      device.close();
      final store = residentStore();
      final session = EditorSessionManager(
        initialProject: withTone(),
        audioConformStore: store,
      );
      addTearDown(session.dispose);
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final rig = session.playbackRig..debugTransportOutput = (() => device);
      final playback = rig.playback..loopMode = PlaybackLoopMode.loop;

      playback.play(scope: PlaybackScope.activeCut);
      addTearDown(playback.stop);
      expect(rig.audioDeviceTransport.carryingPlayback, isTrue);
      rig.audioDeviceTransport.clockStatus(); // its first look starts it
      expect(
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.03),
        isTrue,
        reason: 'fixture: the 0.05 tone is heard at full',
      );

      rig.settlePlaybackLevel(0.1);
      expect(device.isPlaying, isTrue, reason: 'the run goes on');
      expect(
        await waitOnTheDevice(
          device,
          () => device.peakFor(0) > 0 && device.peakFor(0) < 0.01,
        ),
        isTrue,
        reason: 'a tenth of 0.05 is heard as soon as the hand lets go',
      );
    }, skip: skip);

    test('a scrub is heard at it', () async {
      final device = QaAudioDevice.instance!;
      expect(
        device.open(sampleRate: 48000, channels: 2, useNullBackend: true),
        greaterThan(0),
      );
      final project = withTone();
      final controller = CanvasPlaybackController(
        resolveProject: () => project,
        resolveActiveCutId: () => const CutId('cut-a'),
        resolveActiveTrackId: () => const TrackId('track'),
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );
      addTearDown(controller.dispose);
      final store = residentStore();
      addTearDown(store.dispose);
      store.resultFor('tone.wav');
      await pumpEventQueue();
      final scrubber = AudioScrubber(
        controller: controller,
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
        resolveProject: () => project,
        conformStore: store,
        resolveDevice: () => QaAudioDevice.instance,
        resolvePlaybackLevel: () => 0.25,
      );
      addTearDown(scrubber.dispose);

      scrubber.onScrubFrame(3);
      expect(scrubber.isArmed, isTrue, reason: 'fixture: the scrub sounds');
      final mix = scrubber.debugWindow.mix;
      expect(mix?.clips.map((clip) => clip.gain), [0.25]);
      scrubber.onScrubEnd();
    }, skip: skip);
  });

  group('the bar', () {
    Project project() => Project(
      id: const ProjectId('bar-project'),
      name: 'Bar',
      frameRate: const ProjectFrameRate.integer(10),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'Cut',
              layers: const [],
              duration: 40,
              canvasSize: const CanvasSize(width: 8, height: 8),
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    );

    const barKey = ValueKey<String>('playback-level-bar');
    const meterKey = ValueKey<String>('audio-level-meter');

    testWidgets('it stands at the row\'s end, right of the level meter, at '
        'the level it is handed — and hands back each step and the release', (
      tester,
    ) async {
      final controller = CanvasPlaybackController(
        resolveProject: project,
        resolveActiveCutId: () => const CutId('cut'),
        resolveActiveTrackId: () => const TrackId('track'),
        resolveFrameRate: () => const ProjectFrameRate.integer(10),
      );
      addTearDown(controller.dispose);
      final steps = <double>[];
      final settled = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: PlaybackTransportControls(
                key: const ValueKey<String>('row'),
                controller: controller,
                scope: PlaybackScope.activeCut,
                resolveMeterPeaks: () => (left: 0.5, right: 0.5),
                playbackLevel: 0.4,
                onPlaybackLevelChanged: steps.add,
                onPlaybackLevelSettled: settled.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final bar = tester.getRect(find.byKey(barKey));
      final meter = tester.getRect(find.byKey(meterKey));
      final row = tester.getRect(find.byKey(const ValueKey<String>('row')));
      expect(bar.left, greaterThanOrEqualTo(meter.right));
      expect(bar.right, row.right, reason: 'nothing after it in the row');
      expect(tester.widget<FieldSlider>(find.byKey(barKey)).value, 0.4);
      expect(
        find.ancestor(
          of: find.byKey(barKey),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppTooltip && widget.message == 'Playback volume',
          ),
        ),
        findsOneWidget,
        reason: 'it is named, in the program\'s language (English here)',
      );

      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * 0.75, bar.center.dy),
      );
      await gesture.moveTo(Offset(bar.left + bar.width * 0.25, bar.center.dy));
      await gesture.up();
      await tester.pump();
      expect(steps, isNotEmpty);
      expect(steps.last, moreOrLessEquals(0.25, epsilon: 0.02));
      expect(settled, hasLength(1));
      expect(settled.single, steps.last);
    });

    testWidgets('a frame panel\'s transport stands it at the app\'s level, '
        'and a drag keeps where it is let go', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.playbackRig.setPlaybackLevel(0.5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FramePanelTransport(
                session: session,
                panel: WorkingPanel.timeline,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.widget<FieldSlider>(find.byKey(barKey)).value, 0.5);
      final row = tester.widget<PlaybackTransportControls>(
        find.byType(PlaybackTransportControls),
      );
      expect(
        row.onPlaybackLevelSettled,
        session.playbackRig.settlePlaybackLevel,
        reason: 'where the hand lets go is the rig\'s settle — the step a '
            'run hears (pinned on the rig above)',
      );

      final bar = tester.getRect(find.byKey(barKey));
      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * 0.5, bar.center.dy),
      );
      await gesture.moveTo(Offset(bar.left + bar.width * 0.2, bar.center.dy));
      await gesture.up();
      await tester.pump();
      final kept = session.appSettings.audioSyncSettings.value.playbackLevel;
      expect(kept, moreOrLessEquals(0.2, epsilon: 0.02));
      expect(tester.widget<FieldSlider>(find.byKey(barKey)).value, kept);
    });
  });
}
