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
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  Project project() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    // fps 10: one frame per 100ms keeps the test math readable.
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

  CanvasPlaybackController controller({
    void Function(PlaybackPosition)? onStopped,
    void Function(PlaybackScope scope, int frames)? onWarm,
  }) {
    return CanvasPlaybackController(
      resolveProject: project,
      resolveActiveCutId: () => const CutId('cut-a'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      onStopped: onStopped,
      onPlaylistWarmRequested: onWarm == null
          ? null
          : (List<StoryboardTimelineLayoutEntry> playlist, scope, _) =>
                onWarm(scope, playlistTotalFrames(playlist)),
    );
  }

  // The first tick after Ticker.start establishes the elapsed epoch, so
  // every scenario pumps once right after play/resume before advancing time.

  testWidgets('active cut playback loops with wrap-around', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut);
    expect(c.isActive, isTrue);
    expect(c.position!.localFrameIndex, 0);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(c.position!.localFrameIndex, 2);

    // 4-frame cut at 10fps: cumulative 600ms → frame 6 % 4 = 2.
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.position!.localFrameIndex, 2);
    expect(c.isPlaying, isTrue);

    c.stop();
    c.detachTicker();
  });

  testWidgets('once mode stops at the last frame and reports it', (
    tester,
  ) async {
    final stopped = <PlaybackPosition>[];
    final c = controller(onStopped: stopped.add);
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);
    c.loopMode = PlaybackLoopMode.once;

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(c.isActive, isFalse);
    expect(stopped, hasLength(1));
    expect(stopped.single.localFrameIndex, 3);
    expect(stopped.single.cutId, const CutId('cut-a'));
    c.detachTicker();
  });

  testWidgets('long frame gaps drop frames instead of stretching time', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    // One huge gap straight to 950ms → frame 9, skipping 1..8.
    await tester.pump(const Duration(milliseconds: 950));
    expect(c.position!.globalFrameIndex, 9);

    c.stop();
    c.detachTicker();
  });

  testWidgets('all-cuts playback crosses cut boundaries', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(c.position!.cutId, const CutId('cut-b'));
    expect(c.position!.localFrameIndex, 0);

    c.stop();
    c.detachTicker();
  });

  testWidgets('pause preserves position and resume continues from it', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    c.pause();
    final pausedAt = c.position!.globalFrameIndex;
    expect(pausedAt, 2);
    expect(c.isActive, isTrue);
    expect(c.isPlaying, isFalse);

    await tester.pump(const Duration(milliseconds: 300));
    expect(c.position!.globalFrameIndex, pausedAt);

    c.resume();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.globalFrameIndex, (pausedAt + 1) % 4);

    c.stop();
    c.detachTicker();
  });

  testWidgets('play requests playlist warming', (tester) async {
    final warmCalls = <(PlaybackScope, int)>[];
    final c = controller(
      onWarm: (scope, frames) => warmCalls.add((scope, frames)),
    );
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.allCuts);

    expect(warmCalls, [(PlaybackScope.allCuts, 10)]);

    c.stop();
    c.detachTicker();
  });

  testWidgets(
    'localFrameIndexListenable ticks per frame without session rebuilds',
    (tester) async {
      final c = controller();
      c.attachTicker(const TestVSync());
      addTearDown(c.dispose);
      final seen = <int?>[];
      c.localFrameIndexListenable.addListener(
        () => seen.add(c.localFrameIndexListenable.value),
      );

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      c.stop();
      c.detachTicker();

      expect(seen, [0, 1, 2, null]);
    },
  );

  testWidgets('seekToLocalFrame jumps the clock and keeps playing', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 1);

    c.seekToLocalFrame(3);
    expect(c.position!.localFrameIndex, 3);
    expect(c.isPlaying, isTrue);

    // The elapsed epoch rebases on the seek target.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.position!.localFrameIndex, 0, reason: '4-frame cut wraps 3→0');

    c.stop();
    c.detachTicker();
  });

  testWidgets('seek while paused moves the shown frame without playing', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    c.pause();

    c.seekToLocalFrame(2);
    expect(c.position!.localFrameIndex, 2);
    expect(c.isPlaying, isFalse);

    await tester.pump(const Duration(milliseconds: 300));
    expect(c.position!.localFrameIndex, 2);

    c.stop();
    c.detachTicker();
  });

  testWidgets('seekToGlobalFrame crosses cut boundaries and clamps', (
    tester,
  ) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    c.pause();

    // cut-a covers frames 0-3, cut-b 4-9.
    c.seekToGlobalFrame(7);
    expect(c.position!.cutId, const CutId('cut-b'));
    expect(c.position!.localFrameIndex, 3);
    expect(c.globalFrameIndexListenable.value, 7);

    c.seekToGlobalFrame(99);
    expect(c.position!.globalFrameIndex, 9);

    c.stop();
    c.detachTicker();
  });

  testWidgets(
    'global listenable fires on same-local cross-cut seeks and nulls on stop',
    (tester) async {
      final c = controller();
      c.attachTicker(const TestVSync());
      addTearDown(c.dispose);
      final globalFrames = <int?>[];
      c.globalFrameIndexListenable.addListener(
        () => globalFrames.add(c.globalFrameIndexListenable.value),
      );

      c.play(scope: PlaybackScope.allCuts);
      await tester.pump();
      c.pause();

      // Local frame 2 of cut-a → local frame 2 of cut-b: the local
      // listenable stays silent (same value), the global one must not.
      c.seekToGlobalFrame(2);
      c.seekToGlobalFrame(6);
      expect(c.position!.localFrameIndex, 2);
      expect(globalFrames, containsAllInOrder([2, 6]));

      c.stop();
      expect(c.globalFrameIndexListenable.value, isNull);
      c.detachTicker();
    },
  );

  testWidgets('dropped frames reset on every loop pass', (tester) async {
    final c = controller();
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(c.droppedFrames, 0);

    // Gap from raw frame 1 to 3 inside the first pass: one frame dropped.
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.droppedFrames, 1);

    // Crossing into the next loop pass clears the counter.
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.droppedFrames, 0);

    c.stop();
    c.detachTicker();
  });

  testWidgets('stop syncs the last position through onStopped', (tester) async {
    final stopped = <PlaybackPosition>[];
    final c = controller(onStopped: stopped.add);
    c.attachTicker(const TestVSync());
    addTearDown(c.dispose);

    c.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    c.stop();

    expect(stopped, hasLength(1));
    expect(stopped.single.cutId, const CutId('cut-b'));
    expect(stopped.single.localFrameIndex, 1);
    c.detachTicker();
  });
}
