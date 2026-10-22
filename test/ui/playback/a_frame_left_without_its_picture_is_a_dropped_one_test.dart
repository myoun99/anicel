import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// 유저 2026-10-15, F-365-Q2: 「컷을 넘을 때도 직전 그림을 남기고, 건너뛴 프레임
/// 수를 재생 버튼 왼쪽에 빨갛게」.
///
/// Skipping frames, the clock goes on without a picture: the film leaves its
/// last whole frame standing (`_WholeFilmFrames`), and the playhead stands
/// on a frame the screen never shows. That frame is DROPPED as surely as one
/// the playhead went over, and the count beside the play button
/// ([CanvasPlaybackController.droppedFrames]) says so — counted where the
/// playhead moves, off the question the film shows a frame by
/// ([CanvasPlaybackController.frameIsThere]). How a run that WAITS counts is
/// `a_run_waits_for_its_picture_test`'s.
void main() {
  // fps 10: one frame per 100ms. One cut of six frames.
  Project project() => Project(
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
            duration: 6,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  /// The frames whose pictures are not there.
  final missing = <int>{};
  setUp(missing.clear);

  /// A run whose clock never waits — skipping frames — asked of each frame
  /// it leaves whether its picture is there.
  CanvasPlaybackController skipping() => CanvasPlaybackController(
    resolveProject: project,
    resolveActiveCutId: () => const CutId('cut'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  )
    ..waitsOn = ((frame, {required placed}) => false)
    ..frameIsThere = ((frame) => !missing.contains(frame));

  Future<CanvasPlaybackController> played(
    WidgetTester tester, {
    int from = 0,
  }) async {
    final c = skipping()..attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.play(scope: PlaybackScope.activeCut, startGlobalFrame: from);
    // The first tick sets the clock's epoch.
    await tester.pump();
    return c;
  }

  Future<void> stop(CanvasPlaybackController c) async {
    c.stop();
    c.detachTicker();
  }

  testWidgets('🚨a frame the playhead stood on whose picture never came is '
      'dropped — counted as it leaves, a frame at a time', (tester) async {
    missing.addAll([2, 3]);
    final c = await played(tester);

    // Two looks a frame, as a screen faster than the film looks.
    final seen = <(int, int)>[];
    for (var look = 1; look <= 10; look += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add((c.position!.localFrameIndex, c.droppedFrames));
    }
    expect(
      seen,
      [
        (0, 0),
        (1, 0),
        (1, 0),
        (2, 0),
        (2, 0),
        (3, 1),
        (3, 1),
        (4, 2),
        (4, 2),
        (5, 2),
      ],
      reason: 'the clock goes on over 2 and 3 — skipping frames never waits — '
          'and each is counted once, when the playhead has left it unshown',
    );
    await stop(c);
  });

  testWidgets('a picture that comes while its frame stands was shown: not '
      'dropped', (tester) async {
    missing.add(2);
    final c = await played(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 2, reason: '⛔premise');

    // The picture lands, and the run is told as the rig tells it.
    missing.remove(2);
    c.lookAgain();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 3);
    expect(c.droppedFrames, 0);
    await stop(c);
  });

  testWidgets('a late tick counts the frames it went over AND the one it '
      'left without its picture', (tester) async {
    missing.add(1);
    final c = await played(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 1, reason: '⛔premise');

    // One gap straight to 400ms: the clock says frame 4.
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.position!.localFrameIndex, 4);
    expect(c.droppedFrames, 3, reason: '1 unshown, 2 and 3 gone over');
    await stop(c);
  });

  testWidgets('the lap\'s last frame left unshown is the old pass\'s: the new '
      'one starts from nothing', (tester) async {
    missing.add(5);
    final c = await played(tester, from: 4);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 5, reason: '⛔premise');

    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 0);
    expect(c.droppedFrames, 0);
    await stop(c);
  });

  testWidgets('with nobody to ask whether a frame is there, every frame the '
      'playhead stands on is shown', (tester) async {
    missing.add(2);
    final c = await played(tester);
    c.frameIsThere = null;
    for (var frame = 1; frame <= 3; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.position!.localFrameIndex, 3, reason: '⛔premise');
    expect(c.droppedFrames, 0);
    await stop(c);
  });
}
