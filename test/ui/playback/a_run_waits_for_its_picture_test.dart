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
/// 보여주기때문에 그 자리에서 멈췃다가 구워지면 이어서 재생」 — and 2026-10-15,
/// F-365-Q1: 「직전 프레임에 서서 기다린다(뷰어와 같은 법)」.
///
/// The controller's half of it: its clock stands BEFORE a frame whose
/// picture is not there ([CanvasPlaybackController.waitsOn]), on the last
/// frame it showed, and goes on onto that frame when it is
/// ([CanvasPlaybackController.lookAgain]). A run PUT on such a frame waits
/// on it. WHICH frames those are is the playback mode's to say
/// (`playback_picture_wait_test`), and what the sound does meanwhile is the
/// transports'.
void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  // fps 10: one frame per 100ms keeps the test math readable. Cut A has
  // four frames, cut B six.
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
    String playing = 'cut-a',
  }) => CanvasPlaybackController(
    resolveProject: project,
    resolveActiveCutId: () => CutId(playing),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
    onStopped: onStopped,
  )
    ..waitsOn = ((frame, {required placed}) => missing.contains(frame))
    // Asked as the rig asks it, so the counts below are of a run that also
    // counts a frame it leaves unshown — which a run that waits never does.
    ..frameIsThere = ((frame) => !missing.contains(frame));

  /// The picture came: the run is told, as the rig tells it.
  void arrive(CanvasPlaybackController c, int frame) {
    missing.remove(frame);
    c.lookAgain();
  }

  // The first tick after Ticker.start establishes the elapsed epoch, so
  // every scenario pumps once right after the clock starts before advancing
  // time.

  /// Where (cut, frame) the run stands.
  (CutId, int) at(CanvasPlaybackController c) =>
      (c.position!.cut.id, c.position!.localFrameIndex);

  testWidgets('🚨the playhead stops BEFORE the frame whose picture is not '
      'there — on the last it showed, the cut before\'s last where it is a '
      'cut\'s head — and goes on onto that frame when it is, a whole frame '
      'from then', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    // Cut B's head, the film's frame 4 — the head F-365 saw come in white.
    missing.add(4);

    c.play(scope: PlaybackScope.allCuts, startGlobalFrame: 2);
    expect(c.isWaiting, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      at(c),
      (const CutId('cut-a'), 3),
      reason: 'cut A\'s last frame — a playhead on cut B\'s head would be over '
          'a picture that is not there: its bare paper',
    );
    expect(c.isWaiting, isTrue);
    expect(c.isPlaying, isTrue, reason: 'waiting is not paused, nor stopped');

    await tester.pump(const Duration(seconds: 3));
    expect(at(c), (const CutId('cut-a'), 3), reason: 'the clock stands');

    arrive(c, 4);
    expect(c.isWaiting, isFalse);
    expect(
      at(c),
      (const CutId('cut-b'), 0),
      reason: 'it goes onto the frame it waited for the moment it comes',
    );
    expect(
      (c.globalFrameIndexListenable.value, c.localFrameIndexListenable.value),
      (4, 0),
      reason: 'and the screen, the ruler and the warmer hear it then',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      at(c),
      (const CutId('cut-b'), 0),
      reason: 'the frame is shown its whole time, counted from when it came',
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(at(c), (const CutId('cut-b'), 1));

    c.stop();
    c.detachTicker();
  });

  testWidgets('a tick that came late does not carry the playhead over a '
      'picture that was never shown — it stands on the last on the way that '
      'is there', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    // One gap straight to 350ms: the clock says frame 3.
    await tester.pump(const Duration(milliseconds: 350));

    expect(c.position!.localFrameIndex, 1, reason: 'frame 2 is on the way');
    expect(c.isWaiting, isTrue);
    c.stop();
    c.detachTicker();
  });

  testWidgets('the lap wraps onto a frame that is not there: the run waits '
      'on the lap\'s last frame, and goes on round onto the first', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(0);

    c.play(scope: PlaybackScope.activeCut, startGlobalFrame: 2);
    await tester.pump();
    // 250ms from frame 2: frame 4 of a four-frame lap is frame 0.
    await tester.pump(const Duration(milliseconds: 250));

    expect(c.position!.localFrameIndex, 3);
    expect(c.isWaiting, isTrue);

    arrive(c, 0);
    expect(c.position!.localFrameIndex, 0);
    expect(c.isWaiting, isFalse);
    c.stop();
    c.detachTicker();
  });

  testWidgets('play pressed on a frame that is not there waits on it from '
      'the first — there is nothing before it that was shown', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(1);

    c.play(scope: PlaybackScope.activeCut, startGlobalFrame: 1);
    expect(c.isActive, isTrue);
    expect(c.isWaiting, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.position!.localFrameIndex, 1);

    arrive(c, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.position!.localFrameIndex, 2);
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
    expect(c.position!.localFrameIndex, 2);
    expect(c.isWaiting, isTrue);
    expect(stopped, isEmpty);

    arrive(c, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.isActive, isFalse);
    expect(stopped.single.localFrameIndex, 3);
    c.detachTicker();
  });

  testWidgets('the device\'s clock is held before the frame as well', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);
    var heard = 0;
    c.resolveAudioClock = ({frameTime}) => ClockReading(globalFrame: heard);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    heard = 3;
    await tester.pump(const Duration(milliseconds: 16));

    expect(c.position!.localFrameIndex, 1, reason: 'frame 2 is on the way');
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
    final heard = <(bool, int)>[];
    c.addListener(() => heard.add((c.isWaiting, c.playlistFrame)));

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    heard.clear();
    await tester.pump(const Duration(milliseconds: 150));
    expect(heard, [(true, 0)]);

    c.lookAgain();
    expect(heard, [(true, 0)], reason: 'still not there');
    expect(c.isWaiting, isTrue);

    arrive(c, 1);
    expect(
      heard,
      [(true, 0), (false, 1)],
      reason: 'told once it stands on the frame that came: the device is '
          'armed again from the frame the run stands on as it hears this',
    );
    c.stop();
    c.detachTicker();
  });

  /// The count in the transport's slot says how many frames were NOT shown.
  /// ↩️Each clock counted off its own readings, so a tick that came late
  /// onto a frame that was not there counted that frame — and the ones the
  /// clock had run on to — as skipped, in the one mode that promises every
  /// picture.
  testWidgets('🚨a frame the run waits for is not a dropped one, nor the one '
      'it waits on: the count is the frames it PASSED, and going on forgets '
      'none of them', (tester) async {
    final c = controller(playing: 'cut-b');
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(3);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    // One gap straight to 450ms: the clock says frame 4.
    await tester.pump(const Duration(milliseconds: 450));
    expect(c.position!.localFrameIndex, 2, reason: '⛔premise: it waits');
    expect(c.droppedFrames, 1, reason: 'frame 1 was passed; 2, 3, 4 were not');

    arrive(c, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.position!.localFrameIndex, 4);
    expect(c.droppedFrames, 1, reason: 'nothing was dropped while it stood');

    c.stop();
    c.detachTicker();
  });

  testWidgets('on the device\'s clock too — where the device, armed again at '
      'the frame the run waited for, reads behind where it last read: that '
      'is no new pass', (tester) async {
    final c = controller(playing: 'cut-b');
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(3);
    var heard = 0;
    c.resolveAudioClock = ({frameTime}) => ClockReading(globalFrame: heard);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    heard = 4;
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.position!.localFrameIndex, 2, reason: '⛔premise: it waits');
    expect(c.droppedFrames, 1);

    // The device is armed again at the frame the run goes on onto.
    heard = 3;
    arrive(c, 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    heard = 4;
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.position!.localFrameIndex, 4);
    expect(c.droppedFrames, 1);

    c.stop();
    c.detachTicker();
  });

  testWidgets('going on round the end onto the next lap\'s first frame '
      'starts the new pass\'s count — not before: standing on the last frame, '
      'the run is still in its lap', (tester) async {
    final c = controller(playing: 'cut-b');
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut, startGlobalFrame: 1);
    await tester.pump();
    // One gap straight to 350ms: the clock says frame 4.
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.droppedFrames, 2, reason: '⛔premise: 2 and 3 were passed');

    missing.add(0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.position!.localFrameIndex, 5, reason: '⛔premise: it waits');
    expect(c.droppedFrames, 2, reason: 'standing on 5, it is still in its lap');

    arrive(c, 0);
    expect(c.position!.localFrameIndex, 0);
    expect(c.droppedFrames, 0, reason: 'a new pass, counted from nothing');
    c.stop();
    c.detachTicker();
  });

  testWidgets('a stopped run waits for nothing — and stops where it stood, '
      'not on the frame it waited for', (tester) async {
    final stopped = <PlaybackPosition>[];
    final c = controller(onStopped: stopped.add);
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    missing.add(2);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.isWaiting, isTrue, reason: '⛔premise');
    c.stop();

    expect(c.isWaiting, isFalse);
    expect(stopped.single.localFrameIndex, 1);
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

    c.seekToGlobalFrame(0);
    asked.clear();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      asked,
      [(1, false), (2, false), (3, false)],
      reason: 'the clock reached them, and stood before the one not there',
    );
    asked.clear();
    c.lookAgain();
    expect(asked, [(3, false)], reason: 'it is the frame it waits for that it '
        'asks about again, not the one it stands on');

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
