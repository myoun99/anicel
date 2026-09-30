import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart' show drawingBlocks;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/canned_audio_recorder.dart';

/// 🗣️F-227 ④ (유저 2026-09-29): 「재생도 타임라인패널의 재생이면 여백까지
/// 재생」 — and the cut an O.L arrives into plays its のりしろ FIRST: its own
/// frame 0 is where its material starts, ahead of its conte start (08-09's
/// settled form, 메모리 `cut-ol-design.md`). The sound, the V row's frame and
/// a take played over it count from that same place.
///
/// Two 24-frame cuts a and b and an O.L over 18..29: b's のりしろ is frames
/// 18..23, so b's own frame 0 is track frame 18. A sound sits at b's conte
/// start, track frame 24.
void main() {
  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: const [],
  );

  Layer seRow() => Layer(
    id: const LayerId('se'),
    name: 'SE',
    kind: LayerKind.se,
    frames: const [],
    timeline: {
      24: const TimelineExposure.drawing(FrameId('f'), length: 4),
    },
    audioClips: [AudioClip(filePath: '/take.wav', frameId: const FrameId('f'))],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut('a'), cut('b')],
            seLayers: [seRow()],
          ),
        ],
      ),
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async => const ConformResult(
          outcome: ConformOutcome.undecodable,
          error: 'test stub',
        ),
        log: (_) {},
      ),
    );
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    s.selectCut(const CutId('b'));
    return s;
  }

  test('b played alone carries its のりしろ at its head, and its sound at '
      'the conte start rings six frames in — where the picture is there', () {
    final s = session();
    addTearDown(s.dispose);
    final playlist = s.playbackRig.playback.playlistForScope(
      PlaybackScope.activeCut,
    );
    expect(playlist.single.mediaLead, 6);

    final scheduled = buildAudioPlaybackSchedule(
      playlist: playlist,
      project: s.repository.requireProject(),
      rate: s.projectSettings.projectFrameRate,
      durationSecondsFor: (_) => 100,
    );
    expect(scheduled.single.startFrame, 6);
  });

  test('a cut with nothing in front plays its sound where it always did', () {
    final s = session();
    addTearDown(s.dispose);
    s.selectCut(const CutId('a'));
    final playlist = s.playbackRig.playback.playlistForScope(
      PlaybackScope.activeCut,
    );
    expect(playlist.single.mediaLead, 0);
    expect(
      buildAudioPlaybackSchedule(
        playlist: playlist,
        project: s.repository.requireProject(),
        rate: s.projectSettings.projectFrameRate,
        durationSecondsFor: (_) => 100,
      ).single.startFrame,
      24,
      reason: 'a\'s own frames run 0..29; the sound at track 24 is its 24',
    );
  });

  test('b\'s own frame 0 is track frame 18 — the V row reads its effects '
      'there', () {
    final s = session();
    addTearDown(s.dispose);
    expect(s.rowSpans.trackGlobalFrameOf(const CutId('b'), 0), 18);
    expect(s.rowSpans.trackGlobalFrameOf(const CutId('a'), 0), 0);
  });

  testWidgets('a run of b alone states its frames on the track from 18 — '
      'where a take or a cue lands', (tester) async {
    final s = session();
    addTearDown(s.dispose);
    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    final atZero = playback.trackFrameOf(0);
    final atSix = playback.trackFrameOf(6);
    playback.stop();
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
    expect(atZero, 18);
    expect(atSix, 24);
  });

  test('a take spoken three frames into b\'s run lands at track frame 21 — '
      'b\'s material start and three, not its conte start', () async {
    final s = session();
    addTearDown(s.dispose);
    s.selectLayer(const LayerId('se'));
    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    playback.seekToGlobalFrame(3);
    // An eighth of a second: three frames, clear of the sound at 24.
    s.voiceRecording.debugVoiceRecorderFactory = () => CannedAudioRecorder(
      AudioRecording(
        samples: Float32List(6000)..fillRange(0, 6000, 0.25),
        channels: 1,
        sampleRate: 48000,
        droppedFrames: 0,
      ),
    );
    expect(
      s.voiceRecording.startVoiceRecording(),
      VoiceRecordStartResult.started,
    );
    expect(await s.voiceRecording.stopVoiceRecordingAndPlace(), isNull);
    playback.stop();
    await pumpEventQueue();

    final lane = s.activeTrack.seLayers.single;
    final take = lane.audioClips.singleWhere(
      (clip) => clip.filePath != '/take.wav',
    );
    expect(
      drawingBlocks(
        lane.timeline,
      ).singleWhere((block) => block.frameId == take.frameId).startIndex,
      21,
    );
  });

  test('a punch ahead of b\'s run is counted into on b\'s own frames — the '
      'streamer runs where the run is', () async {
    final s = session();
    addTearDown(s.dispose);
    s.selectLayer(const LayerId('se'));
    s.trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: const TrackId('t'),
      anchorRow: const LayerRowAddress(LayerId('se')),
      startFrame: 30,
      endFrameExclusive: 34,
    );
    final playback = s.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    // A second: it outlasts the twelve-frame run-up the head trim eats.
    s.voiceRecording.debugVoiceRecorderFactory = () => CannedAudioRecorder(
      AudioRecording(
        samples: Float32List(48000)..fillRange(0, 48000, 0.25),
        channels: 1,
        sampleRate: 48000,
        droppedFrames: 0,
      ),
    );
    expect(
      s.voiceRecording.startVoiceRecording(),
      VoiceRecordStartResult.started,
    );
    // The roll is b's frame 0, track 18; the punch at track 30 is b's 12.
    expect(
      s.voiceRecording.voiceRecordStreamerWindow,
      (startFrame: 0, punchFrame: 12),
    );
    await s.voiceRecording.stopVoiceRecordingAndPlace();
    playback.stop();
    await pumpEventQueue();
  });
}
