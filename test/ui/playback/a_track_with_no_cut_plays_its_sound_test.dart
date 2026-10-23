
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';
import 'package:anicel/src/ui/timeline/frame_panel_sill_controls.dart';

/// 🗣️F-341 (유저 2026-10-12): 「콘티패널에서 컷이 없으면 사운드행에 사운드
/// 있어도 재생안됨. 분명 독립적인 글로벌 행이라고 했는데 아직도 연관시켜버린
/// 코드가 존재하나본데 독립적인 부분은 제대로 독립적으로 존재하도록」.
///
/// A track's axis and its sound rows are the track's, not its cuts': on a
/// track with no cut the storyboard's transport plays the movie to its end
/// line with the sound in it, and its playhead seeks, scrubs and stops on
/// the axis like anywhere else a cut is not.
void main() {
  Layer seRow({required int start, required int length}) => Layer(
    id: const LayerId('se'),
    name: 'SE',
    kind: LayerKind.se,
    frames: const [],
    timeline: {
      start: TimelineExposure.drawing(const FrameId('f'), length: length),
    },
    audioClips: [AudioClip(filePath: '/take.wav', frameId: const FrameId('f'))],
  );

  Cut cut(int duration) => Cut(
    id: const CutId('c'),
    name: 'c',
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: const [],
  );

  EditorSessionManager session({
    required Cut cut,
    int trailingFrames = 0,
    AudioConformStore? store,
  }) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 12),
      trailingFrames: trailingFrames,
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'T',
          cuts: [cut],
          seLayers: [seRow(start: 10, length: 4)],
        ),
      ],
    ),
    audioConformStore:
        store ??
        AudioConformStore(
          resolveConformPath: (_) => null,
          runner: (request) async => const ConformResult(
            outcome: ConformOutcome.undecodable,
            error: 'test stub',
          ),
          log: (_) {},
        ),
  );

  /// A 48-frame movie whose one cut the user deleted: the end line stays
  /// where it was (the trailing frames hold it), and the sound at frames
  /// 10..13 stays on the track's row.
  EditorSessionManager withNoCut({AudioConformStore? store}) {
    final s = session(cut: cut(48), store: store);
    s.cutVerbs.deleteActiveCut();
    expect(
      s.repository.requireProject().tracks.single.cuts,
      isEmpty,
      reason: 'fixture: the track holds no cut',
    );
    return s;
  }

  /// What the storyboard's play button — and its key — does (F-261).
  void pressStoryboardPlay(EditorSessionManager s) {
    final transport = panelTransportFor(WorkingPanel.storyboard, s);
    playOrStop(
      s.playbackRig.playback,
      scope: transport.scope,
      startFrame: transport.startFrame,
    );
  }

  Future<void> standDown(WidgetTester tester, EditorSessionManager s) async {
    s.playbackRig.playback.stop();
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  }

  testWidgets('the storyboard plays a track with no cut — the movie, to its '
      'end line, with the sound in it', (tester) async {
    final s = withNoCut();
    addTearDown(s.dispose);
    final playback = s.playbackRig.playback;

    pressStoryboardPlay(s);
    final playing = playback.isPlaying;
    final waiting = playback.isWaiting;
    final frames = playback.totalFrames;
    final scheduled = buildAudioPlaybackSchedule(
      window: playback.window,
      project: s.repository.requireProject(),
      rate: s.projectSettings.projectFrameRate,
      durationSecondsFor: (_) => 100,
    );
    await standDown(tester, s);

    expect(playing, isTrue, reason: 'a track with no cut still has a movie');
    expect(waiting, isFalse, reason: 'no picture there to wait for');
    expect(frames, 48);
    expect(scheduled, hasLength(1));
    expect(scheduled.single.startFrame, 10);
    expect(scheduled.single.endFrameExclusive, 14);
  });

  testWidgets('a run stopped there leaves the playhead where it stopped — '
      'and the next play starts from it', (tester) async {
    final s = withNoCut();
    addTearDown(s.dispose);
    final playback = s.playbackRig.playback;

    playback.play(scope: PlaybackScope.allCuts, startGlobalFrame: 20);
    await standDown(tester, s);
    expect(s.playheadCursors.trackFrameNow(), 20);

    pressStoryboardPlay(s);
    final from = playback.playlistFrame;
    await standDown(tester, s);
    expect(from, 20);
  });

  testWidgets('the ruler seeks and scrubs on a track with no cut', (
    tester,
  ) async {
    final s = withNoCut();
    addTearDown(s.dispose);

    s.selectGlobalFrame(30);
    expect(s.playheadCursors.trackFrameNow(), 30);

    s.frameScrub.scrubGlobalFrame(12);
    expect(s.playheadCursors.trackFrameNow(), 12);
    await tester.pump();
  });

  // The session's scrubber is never handed an audio device under
  // `flutter test` (`audioDeviceUnlessTesting`), so what the ruler's scrub
  // can be seen to do here is LOOK for the sound: its mix asks the conform
  // store how long the file under the frame is, and a file nobody asked
  // about yet is conformed on that first ask. The scrubber itself sounding
  // that mix is pinned in `audio_scrubber_test.dart` (the F-341 group).
  test('a scrub over a track with no cut looks for the track\'s sound — '
      'through the scrub the storyboard\'s ruler drives', () async {
    final asked = <String>[];
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async {
        asked.add(request.sourcePath);
        return const ConformResult(
          outcome: ConformOutcome.undecodable,
          error: 'test stub',
        );
      },
      log: (_) {},
    );
    final s = withNoCut(store: store);
    addTearDown(s.dispose);
    await pumpEventQueue();
    expect(asked, isEmpty, reason: 'fixture: nothing has asked for it yet');

    s.frameScrub.scrubGlobalFrame(11);
    await pumpEventQueue();

    expect(s.playheadCursors.trackFrameNow(), 11);
    expect(
      asked,
      ['/take.wav'],
      reason: 'frame 11 is the sound\'s, on the track\'s own row',
    );
  });

  testWidgets('CONTROL: with a cut, the run is the same movie — the cut and '
      'its trailing frames, the sound past the cut heard there', (
    tester,
  ) async {
    final s = session(cut: cut(8), trailingFrames: 48);
    addTearDown(s.dispose);
    final playback = s.playbackRig.playback;

    pressStoryboardPlay(s);
    final frames = playback.totalFrames;
    final scheduled = buildAudioPlaybackSchedule(
      window: playback.window,
      project: s.repository.requireProject(),
      rate: s.projectSettings.projectFrameRate,
      durationSecondsFor: (_) => 100,
    );
    await standDown(tester, s);

    expect(frames, 56, reason: 'the cut\'s 8 and the 48 past it');
    expect(scheduled.single.startFrame, 10, reason: 'past the cut\'s end');
  });
}
