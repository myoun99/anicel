import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// 유저 2026-10-15 (F-364-Q1 b): 「하나도 안 건너뛴다 — 소리를 그림에 다시
/// 맞춘다」 — showing every picture, a run whose app was longer than a frame
/// still shows the next picture, and its clock — the sound — is put back to
/// it, as a run that waited for a picture goes on with it.
///
/// The controller's half ([CanvasPlaybackController.showsEveryPicture]):
/// which mode shows every picture is `playback_picture_wait_test`'s, and how
/// far the playhead goes `playhead_way_test`'s. Where the sound is put back
/// is the seek a transport hears ([CanvasPlaybackController.onSeeked]).
void main() {
  // fps 10: one frame per 100ms keeps the test math readable.
  final project = Project(
    id: const ProjectId('project'),
    name: 'Project',
    frameRate: const ProjectFrameRate.integer(10),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: const CutId('cut'),
            name: 'cut',
            layers: const [],
            duration: 10,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  /// The frames whose pictures are not there yet.
  final missing = <int>{};

  /// The frames the run's clock was put back to.
  final putBack = <int>[];

  /// What the device says, where a test hands the run one.
  ClockReading? device;

  setUp(() {
    missing.clear();
    putBack.clear();
    device = null;
  });

  CanvasPlaybackController controller({
    void Function(PlaybackPosition)? onStopped,
  }) => CanvasPlaybackController(
    resolveProject: () => project,
    resolveActiveCutId: () => const CutId('cut'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
    onStopped: onStopped,
  )
    ..resolveAudioClock = (({frameTime}) => device)
    ..waitsOn = ((frame, {required placed}) => missing.contains(frame))
    ..frameIsThere = ((frame) => !missing.contains(frame))
    ..showsEveryPicture = (() => true)
    ..onSeeked = putBack.add;

  int? shown(CanvasPlaybackController c) =>
      c.globalFrameIndexListenable.value;

  testWidgets('🚨a run behind the device goes on onto the NEXT frame, drops '
      'none, and puts the device back to it', (tester) async {
    final c = controller()..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.play(scope: PlaybackScope.activeCut);
    device = const ClockReading(globalFrame: 0);
    await tester.pump(const Duration(milliseconds: 16));

    device = const ClockReading(globalFrame: 4);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), 1, reason: 'the pictures 1, 2, 3 are there, and shown');
    expect(c.droppedFrames, 0);
    expect(putBack, [1], reason: 'the sound put back to the picture');

    // The device, put back to frame 1, goes on from there.
    device = const ClockReading(globalFrame: 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), 2);
    expect(putBack, [1], reason: 'on time: nothing to put back');
    c.stop();
  });

  testWidgets('🚨a run behind its own clock puts it back too: the wall clock '
      'counts afresh from the frame it went on onto', (tester) async {
    final c = controller()..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.play(scope: PlaybackScope.activeCut);
    // The first tick after a start is the clock's epoch.
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 350));
    expect(shown(c), 1, reason: 'the clock says 3; the picture after 0 is 1');
    expect(putBack, [1]);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(shown(c), 1, reason: 'a whole frame, counted from where it went on');
    await tester.pump(const Duration(milliseconds: 20));
    expect(shown(c), 2);
    expect(putBack, [1], reason: 'counted afresh, the clock is on time');
    c.stop();
  });

  testWidgets('the next picture not there yet is waited for as ever — the run '
      'stands on the last it showed, and nothing is put back', (tester) async {
    final c = controller()..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.play(scope: PlaybackScope.activeCut);
    device = const ClockReading(globalFrame: 0);
    await tester.pump(const Duration(milliseconds: 16));
    missing.add(1);

    device = const ClockReading(globalFrame: 4);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), 0);
    expect(c.isWaiting, isTrue);
    expect(putBack, isEmpty);
    c.stop();
  });

  testWidgets('🚨a run that plays once and runs out while behind goes on to '
      'show the frames still to show, and stops on the last', (tester) async {
    PlaybackPosition? stoppedAt;
    final c = controller(onStopped: (at) => stoppedAt = at)
      ..loopMode = PlaybackLoopMode.once
      ..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.play(scope: PlaybackScope.activeCut, startGlobalFrame: 7);
    device = const ClockReading(globalFrame: 7);
    await tester.pump(const Duration(milliseconds: 16));

    device = const ClockReading(globalFrame: 9, ended: true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.isPlaying, isTrue, reason: 'frames 8 and 9 are still to show');
    expect(shown(c), 8);
    expect(putBack, [8]);

    await tester.pump(const Duration(milliseconds: 16));
    expect(c.isActive, isFalse, reason: 'it has shown the last');
    expect(stoppedAt?.globalFrameIndex, 9);
  });

  testWidgets('🚨a run whose sound is heard frames ahead of its picture at '
      'every start is not put back at every look: the first look after a '
      'start is the start, not lateness', (tester) async {
    // Wherever the device is put, it is heard three frames on by the time
    // a picture is shown: a frame is shown refreshes after its tick, and a
    // user's correction is on top.
    const lead = 3;
    final c = controller()
      ..onSeeked = ((frame) {
        putBack.add(frame);
        device = ClockReading(globalFrame: frame + lead);
      })
      ..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    device = const ClockReading(globalFrame: lead);
    c.play(scope: PlaybackScope.activeCut);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), lead, reason: 'its first heard frame, as ever');
    expect(putBack, isEmpty);

    // The app was long: the clock is two frames past the picture.
    device = const ClockReading(globalFrame: lead + 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), lead + 1);
    expect(putBack, [lead + 1]);

    await tester.pump(const Duration(milliseconds: 16));
    expect(
      putBack,
      [lead + 1],
      reason: 'put back, it is heard ahead again at once — and would be at '
          'every look',
    );
    expect(shown(c), lead + 1 + lead);

    device = const ClockReading(globalFrame: lead + 1 + lead + 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), lead + 1 + lead + 1, reason: 'and it plays on');
    expect(putBack, [lead + 1]);
    c.stop();
  });

  testWidgets('a run that keeps time drops the frames it is late for, and '
      'puts nothing back', (tester) async {
    final c = controller()
      ..showsEveryPicture = null
      ..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.play(scope: PlaybackScope.activeCut);
    device = const ClockReading(globalFrame: 0);
    await tester.pump(const Duration(milliseconds: 16));

    device = const ClockReading(globalFrame: 4);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown(c), 4);
    expect(c.droppedFrames, 3);
    expect(putBack, isEmpty);
    c.stop();
  });
}
