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

/// 유저 2026-10-08: 「거슬리는건 재생했는데 재생바는 지나가고있는데 그림이
/// 없어서 비어있다던가」 · 「안구워진곳에 닿으면 그 자리에서 만들어서
/// 보여주기때문에 그 자리에서 멈췃다가 구워지면 이어서 재생」.
///
/// The controller's half of it: its clock stands ON a frame whose picture is
/// not there ([CanvasPlaybackController.waitsOn]) and goes on from that
/// frame when it is ([CanvasPlaybackController.lookAgain]). WHICH frames
/// those are is the playback mode's to say (`playback_picture_wait_test`),
/// and what the sound does meanwhile is the transports'.
void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  // fps 10: one frame per 100ms keeps the test math readable. The cut that
  // plays alone has four frames.
  Project project() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    frameRate: const ProjectFrameRate.integer(10),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [cut('cut-a', 4), cut('cut-b', 6)],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  /// The frames whose pictures are not there yet.
  final missing = <int>{};
  setUp(missing.clear);

  CanvasPlaybackController controller({
    void Function(PlaybackPosition)? onStopped,
  }) => CanvasPlaybackController(
    resolveProject: project,
    resolveActiveCutId: () => const CutId('cut-a'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
    onStopped: onStopped,
  )..waitsOn = (frame, {required placed}) => missing.contains(frame);

  /// The picture came: the run is told, as the rig tells it.
  void arrive(CanvasPlaybackController c, int frame) {
    missing.remove(frame);
    c.lookAgain();
  }

  // The first tick after Ticker.start establishes the elapsed epoch, so
  // every scenario pumps once right after the clock starts before advancing
  // time.

  testWidgets('🚨the playhead stops ON the frame whose picture is not there — '
      'it does not pass it — and goes on from that frame when it is', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);

    c.play(scope: PlaybackScope.activeCut);
    expect(c.isWaiting, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.position!.localFrameIndex, 2);
    expect(c.isWaiting, isTrue);
    expect(c.isPlaying, isTrue, reason: 'waiting is not paused, nor stopped');

    await tester.pump(const Duration(seconds: 3));
    expect(c.position!.localFrameIndex, 2, reason: 'the clock stands');

    arrive(c, 2);
    expect(c.isWaiting, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      c.position!.localFrameIndex,
      2,
      reason: 'the frame is shown its whole time, counted from when it came',
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(c.position!.localFrameIndex, 3);

    c.stop();
    c.detachTicker();
  });

  testWidgets('a tick that came late does not carry the playhead over a '
      'picture that was never shown', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    // One gap straight to 350ms: the clock says frame 3.
    await tester.pump(const Duration(milliseconds: 350));

    expect(c.position!.localFrameIndex, 2, reason: 'frame 2 is on the way');
    expect(c.isWaiting, isTrue);
    c.stop();
    c.detachTicker();
  });

  testWidgets('the lap wraps onto a frame that is not there, and waits on '
      'it', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(0);

    c.play(scope: PlaybackScope.activeCut, startGlobalFrame: 2);
    await tester.pump();
    // 250ms from frame 2: frame 4 of a four-frame lap is frame 0.
    await tester.pump(const Duration(milliseconds: 250));

    expect(c.position!.localFrameIndex, 0);
    expect(c.isWaiting, isTrue);
    c.stop();
    c.detachTicker();
  });

  testWidgets('play pressed on a frame that is not there waits on it from '
      'the first', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(0);

    c.play(scope: PlaybackScope.activeCut);
    expect(c.isActive, isTrue);
    expect(c.isWaiting, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.position!.localFrameIndex, 0);

    arrive(c, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.position!.localFrameIndex, 1);
    c.stop();
    c.detachTicker();
  });

  testWidgets('a run that waits and is then mounted gets no clock by being '
      'mounted', (tester) async {
    final c = controller();
    addTearDown(c.dispose);
    missing.add(0);

    c.play(scope: PlaybackScope.activeCut);
    c.attachTicker(const TestVSync());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.position!.localFrameIndex, 0);
    expect(c.isWaiting, isTrue);
    c.stop();
    c.detachTicker();
  });

  testWidgets('a seek onto a frame that is not there waits on it; onto one '
      'that is, the run goes on from it', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(3);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    c.seekToGlobalFrame(3);
    expect(c.isWaiting, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.position!.localFrameIndex, 3);

    c.seekToGlobalFrame(1);
    expect(c.isWaiting, isFalse, reason: 'frame 1 is there');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.position!.localFrameIndex, 2);
    c.stop();
    c.detachTicker();
  });

  testWidgets('played once, the run does not end before its last frame has '
      'been shown', (tester) async {
    final stopped = <PlaybackPosition>[];
    final c = controller(onStopped: stopped.add);
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.loopMode = PlaybackLoopMode.once;
    missing.add(3);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(c.isActive, isTrue, reason: 'its last picture is still to come');
    expect(c.position!.localFrameIndex, 3);
    expect(c.isWaiting, isTrue);
    expect(stopped, isEmpty);

    arrive(c, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.isActive, isFalse);
    expect(stopped.single.localFrameIndex, 3);
    c.detachTicker();
  });

  testWidgets('the device\'s clock is held to the frame as well', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);
    var heard = 0;
    c.resolveAudioClock = () => ClockReading(globalFrame: heard);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    heard = 3;
    await tester.pump(const Duration(milliseconds: 16));

    expect(c.position!.localFrameIndex, 2, reason: 'frame 2 is on the way');
    expect(c.isWaiting, isTrue);
    c.stop();
    c.detachTicker();
  });

  testWidgets('a run says when it begins to wait and when it goes on — the '
      'sound hears both through this — and looking again while the picture '
      'is still not there says nothing', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(1);
    final heard = <bool>[];
    c.addListener(() => heard.add(c.isWaiting));

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    heard.clear();
    await tester.pump(const Duration(milliseconds: 150));
    expect(heard, [true]);

    c.lookAgain();
    expect(heard, [true], reason: 'still not there');
    expect(c.isWaiting, isTrue);

    arrive(c, 1);
    expect(heard, [true, false]);
    c.stop();
    c.detachTicker();
  });

  /// The count in the transport's slot says how many frames were NOT shown.
  /// ↩️Each clock counted off its own readings, so a tick that came late
  /// onto a frame that was not there counted that frame — and the ones the
  /// clock had run on to — as skipped, in the one mode that promises every
  /// picture.
  testWidgets('🚨a frame the run waits before is not a dropped one: the '
      'count is the frames it PASSED, and going on forgets none of them', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    // One gap straight to 350ms: the clock says frame 3.
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.position!.localFrameIndex, 2, reason: '⛔premise: it waits');
    expect(c.droppedFrames, 1, reason: 'frame 1 was passed; 2 and 3 were not');

    arrive(c, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.position!.localFrameIndex, 3);
    expect(c.droppedFrames, 1, reason: 'nothing was dropped while it stood');

    c.stop();
    c.detachTicker();
  });

  testWidgets('on the device\'s clock too — where a run going on from a '
      'wait steps BACK to the frame it stood on, and that is no new pass', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);
    var heard = 0;
    c.resolveAudioClock = () => ClockReading(globalFrame: heard);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    heard = 3;
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.position!.localFrameIndex, 2, reason: '⛔premise: it waits');
    expect(c.droppedFrames, 1);

    // The device is armed again at the frame the run stands on.
    heard = 2;
    arrive(c, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    heard = 3;
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.position!.localFrameIndex, 3);
    expect(c.droppedFrames, 1);

    c.stop();
    c.detachTicker();
  });

  testWidgets('a stopped run waits for nothing', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(0);

    c.play(scope: PlaybackScope.activeCut);
    expect(c.isWaiting, isTrue);
    c.stop();

    expect(c.isWaiting, isFalse);
    c.lookAgain();
    expect(c.isActive, isFalse, reason: 'looking again starts nothing');
    c.detachTicker();
  });

  testWidgets('the owner is told how the run came to the frame: PUT there '
      '— play pressed, the ruler dragged — or reached by its clock', (
    tester,
  ) async {
    final asked = <(int, bool)>[];
    final c = controller()
      ..waitsOn = (frame, {required placed}) {
        asked.add((frame, placed));
        return missing.contains(frame);
      };
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut);
    expect(asked, [(0, true)]);

    asked.clear();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(asked, [(1, false)], reason: 'the clock reached it');

    asked.clear();
    missing.add(3);
    c.seekToGlobalFrame(3);
    expect(asked, [(3, true)], reason: 'the ruler put it there');

    asked.clear();
    c.lookAgain();
    expect(asked, [(3, false)], reason: 'looking again puts it nowhere');

    c.stop();
    c.detachTicker();
  });

  testWidgets('with nobody to ask, the clock never waits — a frame is '
      'skipped, as it always was', (tester) async {
    final c = controller()..waitsOn = null;
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.addAll([1, 2, 3]);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(c.position!.localFrameIndex, 3);
    expect(c.isWaiting, isFalse);
    c.stop();
    c.detachTicker();
  });
}
