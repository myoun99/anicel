import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart' show drawingBlocks;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import '../../helpers/temp_dir.dart';

/// The landing half of recording (AUDIO-PRO R5 → REC1-B rolling record):
/// a finished take becomes a WAV named `<lane>_T<n>`, a pool entry and a
/// tape-style landing on the ARMED track SE lane — pool + lane swap in
/// ONE undo. Driven with made recordings; the microphone half is the
/// real-DLL suite's job.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-voice-rec-test');
  });

  tearDown(() => deleteTempQuietly(directory));

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

  AudioRecording takeOfSeconds(
    double seconds, {
    int channels = 1,
    int sampleRate = 48000,
    int droppedFrames = 0,
  }) {
    final length = (seconds * sampleRate).round();
    final samples = Float32List(length * channels);
    for (var index = 0; index < samples.length; index += 1) {
      samples[index] = 0.25;
    }
    return AudioRecording(
      samples: samples,
      channels: channels,
      sampleRate: sampleRate,
      droppedFrames: droppedFrames,
    );
  }

  test('REC1-B: a take lands on the given lane — <lane>_T01 WAV, pool '
      'entry, block at the anchor, ONE undo strips it all', () async {
    final manager = session();
    await manager.projectDoor.saveProjectToFile('${directory.path}/scene.anicel', asked: SaveAsked.byAPerson);
    final lane = manager.activeTrack.seLayers.first;

    final placed = await manager.voiceRecording.placeVoiceRecording(
      takeOfSeconds(1.0),
      laneId: lane.id,
      anchorFrame: 0,
    );
    expect(placed, isTrue);

    final landed = manager.activeTrack.seLayers.first;
    final clip = landed.audioClips.single;
    // On the shelf, saved project or not. A take used to land in the
    // project's `Media/` folder once it had one, which made that folder
    // the only copy of a performance; the project carries its own audio
    // now, so the recording stays somewhere a person can find it.
    // 🚨The take lives in THIS RUN'S 이사대기 room now, not a shelf outside
    // the container (유저 2026-09-08: 앱이 쓰는 곳은 앱 컨테이너와 프로젝트
    // 파일 둘뿐). Its pool path is an ADDRESS — the bytes sit at the name the
    // staging store derives — so every read below goes through the same door
    // playback and the save use.
    expect(clip.filePath, contains('/Staged/'));
    expect(clip.filePath, isNot(contains('.assets/Media/')));
    // The lane's name and a take ordinal, not a fixed one: the shelf
    // outlives a project, so the walk continues past earlier sessions.
    expect(
      RegExp('${lane.name}_T\\d+\\.wav\$').hasMatch(clip.filePath),
      isTrue,
      reason: clip.filePath,
    );
    expect(manager.projectFile.projectHoldsMediaBytes(clip.filePath), isTrue);
    expect(
      manager.mediaPool.mediaAssets.map((asset) => asset.path),
      contains(clip.filePath),
    );
    // 1 s @ 24 fps = a 24-frame block at the anchor carrying the clip.
    final block = drawingBlocks(landed.timeline).single;
    expect(block.startIndex, 0);
    expect(block.length, 24);
    expect(block.frameId, clip.frameId);
    // The WAV round-trips exactly as long as the recording.
    final decoded = decodeConform(
      manager.projectFile.mediaByteSourceFor(clip.filePath).readSync(),
    );
    expect(decoded.sampleRate, 48000);
    expect(decoded.length, 48000);

    // ONE undo: pool and lane both back to the clean slate.
    manager.undo();
    final reverted = manager.activeTrack.seLayers.first;
    expect(reverted.audioClips, isEmpty);
    expect(drawingBlocks(reverted.timeline), isEmpty);
    expect(manager.mediaPool.mediaAssets, isEmpty);
    manager.dispose();
  });

  test(
    'REC1-B: recording along trims the monitoring latency off the head',
    () async {
      final manager = session();
      await manager.projectDoor.saveProjectToFile('${directory.path}/scene.anicel', asked: SaveAsked.byAPerson);
      final lane = manager.activeTrack.seLayers.first;

      final placed = await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(1.0),
        laneId: lane.id,
        anchorFrame: 0,
        headTrimSamples: 12000, // 250 ms of monitoring delay
      );
      expect(placed, isTrue);
      final clip = manager.activeTrack.seLayers.first.audioClips.single;
      final decoded = decodeConform(
      manager.projectFile.mediaByteSourceFor(clip.filePath).readSync(),
    );
      expect(
        decoded.length,
        48000 - 12000,
        reason:
            'the performer spoke against delayed monitoring; the take '
            'shifts earlier by exactly that delay',
      );
      manager.dispose();
    },
  );

  test(
    'REC1-B: a take shorter than the latency it rode on places nothing',
    () async {
      final manager = session();
      await manager.projectDoor.saveProjectToFile('${directory.path}/scene.anicel', asked: SaveAsked.byAPerson);
      expect(
        await manager.voiceRecording.placeVoiceRecording(
          takeOfSeconds(0.1),
          laneId: manager.activeTrack.seLayers.first.id,
          anchorFrame: 0,
          headTrimSamples: 48000,
        ),
        isFalse,
      );
      manager.dispose();
    },
  );

  test('REC1-B: a second take over the first TRIMS it, tape-style — same '
      'lane, no new row, both files kept', () async {
    final manager = session();
    await manager.projectDoor.saveProjectToFile('${directory.path}/scene.anicel', asked: SaveAsked.byAPerson);
    final laneId = manager.activeTrack.seLayers.first.id;
    final rowsBefore = manager.activeTrack.seLayers.length;

    expect(
      await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(1.0), // 24 frames
        laneId: laneId,
        anchorFrame: 0,
      ),
      isTrue,
    );
    expect(
      await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(0.5), // 12 frames over the first take's tail
        laneId: laneId,
        anchorFrame: 12,
      ),
      isTrue,
    );

    expect(manager.activeTrack.seLayers.length, rowsBefore);
    final lane = manager.activeTrack.seLayers.first;
    final blocks = drawingBlocks(lane.timeline);
    expect(blocks, hasLength(2));
    expect(blocks[0].startIndex, 0);
    expect(blocks[0].length, 12, reason: 'the first take lost its tail');
    expect(blocks[1].startIndex, 12);
    expect(blocks[1].length, 12);
    // Take numbering advanced and the first WAV stays in the pool — two
    // files, not one overwritten.
    //
    // By SHAPE rather than by ordinal: takes land on the shelf now, and
    // the shelf outlives one project, so the walk continues past whatever
    // is already there instead of restarting per project folder.
    final takes = manager.mediaPool.mediaAssets.map((asset) => asset.path).toList();
    expect(takes, hasLength(2));
    expect(takes.toSet(), hasLength(2), reason: 'the first was not replaced');
    for (final take in takes) {
      expect(RegExp(r'_T\d+\.wav$').hasMatch(take), isTrue, reason: take);
      expect(manager.projectFile.projectHoldsMediaBytes(take), isTrue);
    }
    manager.dispose();
  });

  test('REC1-B: the punch window clamps the take — block AND file', () async {
    final manager = session();
    await manager.projectDoor.saveProjectToFile('${directory.path}/scene.anicel', asked: SaveAsked.byAPerson);
    final laneId = manager.activeTrack.seLayers.first.id;

    expect(
      await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(1.0), // would cover 24 frames
        laneId: laneId,
        anchorFrame: 0,
        punchEndFrame: 6,
      ),
      isTrue,
    );
    final lane = manager.activeTrack.seLayers.first;
    expect(drawingBlocks(lane.timeline).single.length, 6);
    final clip = lane.audioClips.single;
    final decoded = decodeConform(
      manager.projectFile.mediaByteSourceFor(clip.filePath).readSync(),
    );
    // 6 frames @ 24 fps @ 48 kHz = 12000 samples: capture past the
    // punch-out was context, not take.
    expect(decoded.length, 12000);
    manager.dispose();
  });

  test('REC1-B: an unsaved project still records — the WAV degrades to '
      'temp, like an import', () async {
    final manager = session();
    final placed = await manager.voiceRecording.placeVoiceRecording(
      takeOfSeconds(0.5),
      laneId: manager.activeTrack.seLayers.first.id,
      anchorFrame: 0,
    );
    expect(placed, isTrue);
    final clip = manager.activeTrack.seLayers.first.audioClips.single;
    expect(manager.projectFile.projectHoldsMediaBytes(clip.filePath), isTrue);
    expect(clip.filePath, isNot(contains('.assets/Media/')));
    manager.dispose();
  });

  test('REC1-B: a null lane refuses the take rather than landing it '
      'anywhere', () async {
    final manager = session();
    await manager.projectDoor.saveProjectToFile('${directory.path}/scene.anicel', asked: SaveAsked.byAPerson);
    expect(
      await manager.voiceRecording.placeVoiceRecording(
        takeOfSeconds(0.5),
        laneId: null,
        anchorFrame: 0,
      ),
      isFalse,
    );
    manager.dispose();
  });

  test('REC1-B: a start ROLLS the transport, mutes the lane, and stop '
      'lands the take', () async {
    final manager = session();
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(0.5));
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);
    // Record = play + capture: the transport rolls the whole track.
    expect(manager.playbackRig.playback.isPlaying, isTrue);
    expect(manager.playbackRig.playback.scope, PlaybackScope.allCuts);
    // The armed lane yields to the microphone (DAW armed-track rule).
    expect(manager.voiceRecording.recordingMutedLayerIds, {laneId});

    final message = await manager.voiceRecording.stopVoiceRecordingAndPlace();
    expect(message, isNull);
    expect(
      manager.playbackRig.playback.isActive,
      isFalse,
      reason: 'the roll this take started stops with it',
    );
    expect(manager.voiceRecording.recordingMutedLayerIds, isEmpty);
    final lane = manager.activeTrack.seLayers.first;
    expect(lane.audioClips, hasLength(1));
    expect(drawingBlocks(lane.timeline).single.length, 12);
    manager.dispose();
  });

  test('REC1-B: transport stop mid-take finishes the take through the '
      'notice channel', () async {
    final manager = session();
    final laneId = manager.activeTrack.seLayers.first.id;
    manager.selectLayer(laneId);
    manager.voiceRecording.debugVoiceRecorderFactory = () => _FakeRecorder(takeOfSeconds(0.5));
    expect(manager.voiceRecording.startVoiceRecording(), VoiceRecordStartResult.started);

    manager.playbackRig.playback.stop();
    // ⚠️The take lands a beat later now: `_onPlaybackStopped` awaits the
    // isolate that secures the take's bytes before the command that places
    // it runs, so the clip is not there the instant `stop()` returns. That
    // ordering is the point — the pool must never hold an asset whose bytes
    // are still being written — so the test waits rather than the code
    // racing.
    await pumpEventQueue();
    expect(manager.voiceRecording.isVoiceRecording.value, isFalse);
    expect(
      manager.activeTrack.seLayers.first.audioClips,
      hasLength(1),
      reason: 'the stop path places the take, not just abandons it',
    );
    manager.dispose();
  });

  // 🗣️F-178 (유저 2026-09-24): 「어디에 서있든 녹음가능하게하고, 동작을 se행에
  // 안서있으면 새 se레이어만들고 거기서하고, 서있으면 해당se행에서 시작하도록」.
  group('F-178: the take goes where you stand', () {
    Set<LayerId> laneIdsOf(EditorSessionManager manager) => {
      for (final lane in manager.activeTrack.seLayers) lane.id,
    };

    test('standing on an SE row the storyboard way records on THAT row — '
        'the drawing layer staying active does not refuse it', () async {
      final manager = session();
      final laneId = manager.activeTrack.seLayers.first.id;
      // The storyboard's rails stand on a row without taking the layer you
      // draw on (유저 2026-07-27): this is the stand the refusal missed.
      manager.standing.standOnRow(
        LayerRowAddress(laneId),
        takesLayerActive: false,
      );
      expect(manager.activeLayerId, isNot(laneId), reason: 'fixture');
      final lanesBefore = laneIdsOf(manager);
      manager.voiceRecording.debugVoiceRecorderFactory =
          () => _FakeRecorder(takeOfSeconds(0.5));

      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.started,
      );
      expect(manager.voiceRecording.recordingMutedLayerIds, {laneId});
      expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);

      expect(laneIdsOf(manager), lanesBefore, reason: 'no lane was opened');
      expect(
        manager.activeTrack.seLayers
            .firstWhere((lane) => lane.id == laneId)
            .audioClips,
        hasLength(1),
      );
      manager.dispose();
    });

    test('standing on any other row opens the lane 「Add layer ▸ SE」 makes, '
        'stands on it, and lands the take there', () async {
      final manager = session();
      // Stood on on purpose: a stand nobody made reads the active layer,
      // which would follow the new lane without the lane being stood on.
      manager.selectLayer(manager.activeLayerId!);
      final lanesBefore = laneIdsOf(manager);
      manager.voiceRecording.debugVoiceRecorderFactory =
          () => _FakeRecorder(takeOfSeconds(0.5));

      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.started,
      );
      final opened = laneIdsOf(manager).difference(lanesBefore).single;
      expect(manager.currentRow, LayerRowAddress(opened));
      expect(manager.voiceRecording.recordingMutedLayerIds, {opened});
      expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);

      final lanes = manager.activeTrack.seLayers;
      for (final lane in lanes) {
        expect(
          lane.audioClips,
          hasLength(lane.id == opened ? 1 : 0),
          reason: '${lane.name} holds the take only if it is the new lane',
        );
      }

      // The menu's lane, made from the same stand: same name, same slot.
      final byMenu = session();
      final menuBefore = laneIdsOf(byMenu);
      byMenu.layerStack.addLayerOfKind(LayerKind.se);
      final menuLane = laneIdsOf(byMenu).difference(menuBefore).single;
      final menuLanes = byMenu.activeTrack.seLayers;
      expect(
        lanes.indexWhere((lane) => lane.id == opened),
        menuLanes.indexWhere((lane) => lane.id == menuLane),
      );
      expect(
        lanes.firstWhere((lane) => lane.id == opened).name,
        menuLanes.firstWhere((lane) => lane.id == menuLane).name,
      );
      byMenu.dispose();
      manager.dispose();
    });

    test('a range selected on the S row in the storyboard is the punch '
        'window, as one selected on the timeline is (#16: the track range '
        'speaks first)', () async {
      final manager = session();
      manager.projectSettings.setProjectFps(4); // 1 s = 4 frames.
      final laneId = manager.activeTrack.seLayers.first.id;
      manager.standing.standOnRow(
        LayerRowAddress(laneId),
        takesLayerActive: false,
      );
      manager.trackFrameRangeSelection.value = TrackFrameRangeSelection(
        trackId: manager.selectedTrackId,
        anchorRow: LayerRowAddress(laneId),
        startFrame: 13,
        endFrameExclusive: 16,
      );
      // Outlasts the 13-frame run-up the head trim eats.
      manager.voiceRecording.debugVoiceRecorderFactory =
          () => _FakeRecorder(takeOfSeconds(4));

      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.started,
      );
      expect(
        manager.voiceRecording.voiceRecordCueClips.map(
          (clip) => clip.startFrame,
        ),
        [1, 5, 9],
        reason: 'the count-down into the punch a timeline range builds',
      );
      expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);
      final block = drawingBlocks(
        manager.activeTrack.seLayers
            .firstWhere((lane) => lane.id == laneId)
            .timeline,
      ).single;
      expect(block.startIndex, 13);
      expect(block.length, 3);
      manager.dispose();
    });

    test('a microphone that will not open leaves no lane behind', () {
      final manager = session();
      final lanesBefore = laneIdsOf(manager);
      manager.voiceRecording.debugVoiceRecorderFactory = _DeafRecorder.new;

      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.deviceFailed,
      );
      expect(laneIdsOf(manager), lanesBefore);
      manager.dispose();
    });

    // ④ 「지금 루프재생켜두면 녹음이 매번? 되서 뭔가 꼬이는거같은데」.
    test('the playhead turning back — the loop wrapping — ends the take '
        'where it had reached, and the roll the take started stops', () async {
      final manager = session();
      manager.selectLayer(manager.activeTrack.seLayers.first.id);
      manager.voiceRecording.debugVoiceRecorderFactory =
          () => _FakeRecorder(takeOfSeconds(0.5)); // 12 frames captured
      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.started,
      );
      final playback = manager.playbackRig.playback;

      playback.seekToGlobalFrame(5);
      expect(
        manager.voiceRecording.isVoiceRecording.value,
        isTrue,
        reason: 'forward is the take running on',
      );
      playback.seekToGlobalFrame(1); // The lap starts over.
      await pumpEventQueue();

      expect(manager.voiceRecording.isVoiceRecording.value, isFalse);
      expect(manager.voiceRecording.voiceRecordingNotice.value, isNull);
      expect(playback.isActive, isFalse);
      expect(
        drawingBlocks(manager.activeTrack.seLayers.first.timeline).single.length,
        6,
        reason: 'frames 0-5, what the take had reached — not all 12 captured',
      );
      manager.dispose();
    });

    test('a roll the take did not start rolls on past the turn', () async {
      final manager = session();
      manager.selectLayer(manager.activeTrack.seLayers.first.id);
      final playback = manager.playbackRig.playback;
      playback.play(scope: PlaybackScope.allCuts, startGlobalFrame: 0);
      manager.voiceRecording.debugVoiceRecorderFactory =
          () => _FakeRecorder(takeOfSeconds(0.5));
      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.started,
      );

      playback.seekToGlobalFrame(4);
      playback.seekToGlobalFrame(0);
      await pumpEventQueue();

      expect(manager.voiceRecording.isVoiceRecording.value, isFalse);
      expect(playback.isPlaying, isTrue);
      expect(
        drawingBlocks(manager.activeTrack.seLayers.first.timeline).single.length,
        5,
      );
      playback.stop();
      await pumpEventQueue();
      manager.dispose();
    });

    test('a gap is a place on the track too: parked in one, the take '
        'opens its lane there', () async {
      final manager = session();
      manager.cutVerbs.createCut();
      final track = manager.repository.requireProject().tracks.first;
      manager.repository.updateCutLeadingGap(
        cutId: track.cuts[1].id,
        leadingGapFrames: 4,
      );
      manager.selectCut(track.cuts[0].id);
      manager.selectGlobalFrame(track.cuts[0].duration + 1);
      expect(manager.activeCutOrNull, isNull, reason: 'fixture: in the gap');
      final lanesBefore = laneIdsOf(manager);
      manager.voiceRecording.debugVoiceRecorderFactory =
          () => _FakeRecorder(takeOfSeconds(0.5));

      expect(
        manager.voiceRecording.startVoiceRecording(),
        VoiceRecordStartResult.started,
      );
      final opened = laneIdsOf(manager).difference(lanesBefore).single;
      expect(manager.currentRow, LayerRowAddress(opened));
      expect(await manager.voiceRecording.stopVoiceRecordingAndPlace(), isNull);
      expect(
        manager.activeTrack.seLayers
            .firstWhere((lane) => lane.id == opened)
            .audioClips,
        hasLength(1),
      );
      manager.dispose();
    });
  });
}

/// A microphone the OS will not open: `start` answers no rate.
class _DeafRecorder extends AudioRecorder {
  @override
  bool get isRecording => false;

  @override
  int start({
    required int sampleRate,
    bool useNullBackend = false,
    int deviceIndex = -1,
  }) => 0;

  @override
  AudioRecording? stop() => null;
}

/// A microphone stand-in: start always succeeds at the take's rate and
/// stop hands the prepared take back once.
class _FakeRecorder extends AudioRecorder {
  _FakeRecorder(this.recording);

  final AudioRecording recording;
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
    return recording.sampleRate;
  }

  @override
  AudioRecording? stop() {
    if (!_started) {
      return null;
    }
    _started = false;
    return recording;
  }
}
