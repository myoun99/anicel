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

/// The controller half of "the picture follows the sound": with an audio
/// clock injected, every tick shows the frame the clock reports — the wall
/// clock is not consulted at all. Null readings keep the old derivation,
/// which is the whole fallback story.
final Project _project = Project(
  id: const ProjectId('clock-project'),
  name: 'Clock',
  createdAt: DateTime.utc(2026, 7, 21),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-a'),
          name: 'A',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: const [],
        ),
      ],
    ),
  ],
);

void main() {
  late CanvasPlaybackController controller;
  AudioClockStatus? clock;

  setUp(() {
    clock = null;
    controller = CanvasPlaybackController(
      resolveProject: () => _project,
      resolveActiveCutId: () => const CutId('cut-a'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    )..resolveAudioClock = () => clock;
  });

  tearDown(() => controller.dispose());

  testWidgets('the picture shows the frame the audio clock reports, however '
      'much wall time has passed', (tester) async {
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);

    clock = const AudioClockStatus(globalFrame: 2);
    // Five wall-clock seconds — the wall clock would be far past the end.
    await tester.pump(const Duration(seconds: 5));
    expect(controller.globalFrameIndexListenable.value, 2);

    clock = const AudioClockStatus(globalFrame: 7);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.globalFrameIndexListenable.value, 7);

    // Out-of-range readings clamp instead of tearing down playback.
    clock = const AudioClockStatus(globalFrame: 99);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.globalFrameIndexListenable.value, 9);
    controller.stop();
  });

  testWidgets('a clock jump forward counts dropped frames; the loop wrap '
      'resets the count for the new pass', (tester) async {
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);

    clock = const AudioClockStatus(globalFrame: 0);
    await tester.pump(const Duration(milliseconds: 16));
    clock = const AudioClockStatus(globalFrame: 4);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.droppedFrames, 3);

    // Wrap (the transport looped): a fresh pass starts clean.
    clock = const AudioClockStatus(globalFrame: 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.droppedFrames, 0);
    controller.stop();
  });

  testWidgets('an ended clock stops a play-once run on the last frame', (
    tester,
  ) async {
    controller.attachTicker(const TestVSync());
    controller.loopMode = PlaybackLoopMode.once;
    controller.play(scope: PlaybackScope.activeCut);

    clock = const AudioClockStatus(globalFrame: 9, ended: true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.isActive, isFalse, reason: 'the run should have stopped');
  });

  testWidgets('a null clock falls back to the wall-clock derivation', (
    tester,
  ) async {
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);

    clock = null;
    // One pump to give the fresh ticker its epoch, then 0.35 s at 10 fps
    // = frame 3 by wall time.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.globalFrameIndexListenable.value, 3);
    controller.stop();
  });

  test('an explicit seek reports its clamped frame through onSeeked', () {
    final seeks = <int>[];
    controller.onSeeked = seeks.add;
    controller.play(scope: PlaybackScope.activeCut);
    controller.seekToGlobalFrame(4);
    controller.seekToGlobalFrame(99);
    expect(seeks, [4, 9]);
    controller.stop();
  });
}
