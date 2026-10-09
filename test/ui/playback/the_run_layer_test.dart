import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/look_test_binding.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';
import 'package:anicel/src/ui/playback/playback_run_layer.dart';

/// THE RUN'S OWN LAYER ([PlaybackRunLayer]): the clock's ticker, the press
/// that stops it and the bar — over every run, whatever draws its picture
/// (playback-plays-the-screen-material). ↩️These were pinned through the
/// composite view, the picture a run played on until the camera view moved
/// onto the canvas (10-10); the picture here is a stand-in that changes as
/// the run's frame does, and nothing else.
void main() {
  // Under the law the app draws by: a frame that was asked for only to
  // look, and changed nothing, is not drawn.
  final binding = LookTestBinding.ensureInitialized();

  const canvasSize = CanvasSize(width: 8, height: 8);

  CanvasPlaybackController controller() => CanvasPlaybackController(
    resolveProject: () => Project(
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
              name: 'Cut',
              duration: 2,
              canvasSize: canvasSize,
              layers: const [],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
    resolveActiveCutId: () => const CutId('cut'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  );

  Future<void> pumpLayer(
    WidgetTester tester,
    CanvasPlaybackController run, {
    ValueNotifier<PrerenderProgress>? progress,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlaybackRunLayer(
          controller: run,
          prerenderProgress: progress ?? ValueNotifier(PrerenderProgress.none),
          // The picture: the run's frame, and only that.
          child: ValueListenableBuilder<int?>(
            valueListenable: run.globalFrameIndexListenable,
            builder: (context, frame, _) => ColoredBox(
              color: (frame ?? 0).isEven ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('tapping the picture stops the run', (tester) async {
    final run = controller();
    run.play(scope: PlaybackScope.activeCut);
    await pumpLayer(tester, run);
    expect(run.isActive, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('canvas-playback-view')));
    await tester.pump();

    expect(run.isActive, isFalse);
  });

  /// ⛔T28 — this was 'pause then resume keeps ticking through the view
  /// vsync'. Pause is gone, but the hazard it caught is not: the ticker is
  /// recreated on every entry into playback, and a single-ticker provider
  /// throws the second time. Stop-then-play is that same round trip.
  testWidgets('stop then play keeps ticking through the layer\'s vsync', (
    tester,
  ) async {
    final run = controller();
    run.play(scope: PlaybackScope.activeCut);
    await pumpLayer(tester, run);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(run.position!.localFrameIndex, 1);

    run.stop();
    await tester.pump();
    run.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(run.isPlaying, isTrue);
    expect(run.position!.localFrameIndex, 1);
    expect(tester.takeException(), isNull);

    run.stop();
    await tester.pump();
  });

  /// 유저 2026-10-08: 「3 화면을 프레임만큼만 다시그리도록」. Nothing in the
  /// layer asks for a frame of its own while the run goes by, so what is
  /// drawn is what changed.
  testWidgets('🚨under the layer, the screen is drawn as often as the frame '
      'changes — it is looked at on every screen frame', (tester) async {
    final run = controller();
    run.play(scope: PlaybackScope.activeCut);
    await pumpLayer(tester, run);
    await tester.pump();
    final drawn = binding.drawnFrames;
    var changes = 0;
    var frame = run.position!.localFrameIndex;
    // A second of a 60Hz screen; a frame of the run is 100ms.
    for (var screen = 0; screen < 60; screen += 1) {
      await tester.pump(const Duration(microseconds: 16667));
      final now = run.position!.localFrameIndex;
      if (now != frame) {
        changes += 1;
        frame = now;
      }
    }

    expect(changes, 10, reason: '⛔premise: ten frames went by');
    expect(
      binding.drawnFrames - drawn,
      changes,
      reason: 'sixty screen frames, and the ten that changed the picture '
          'were drawn',
    );

    run.stop();
    await tester.pump();
  });

  /// 유저 답 F-296-Q5 (2026-10-08): 「자리를 늘 두는 막대로 바꾼다」. ↩️It
  /// was a strip with the words 「caching N/M」 that came while pictures were
  /// being made and went when they were — 없다가 생기는 UI.
  testWidgets('the bar at the foot is always there, says how much of what '
      'the run wants is made, and says it without words', (tester) async {
    final run = controller();
    final progress = ValueNotifier(
      const PrerenderProgress(cached: 1, total: 4),
    );
    addTearDown(progress.dispose);
    const barKey = ValueKey<String>('canvas-playback-progress');
    double shown() =>
        tester.widget<LinearProgressIndicator>(find.byKey(barKey)).value!;

    run.play(scope: PlaybackScope.activeCut);
    await pumpLayer(tester, run, progress: progress);

    expect(shown(), 0.25);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('canvas-playback-view')),
        matching: find.byType(Text),
      ),
      findsNothing,
      reason: '설명 문구 금지 — and the old words were English only',
    );

    progress.value = const PrerenderProgress(cached: 4, total: 4);
    await tester.pump();
    expect(find.byKey(barKey), findsOneWidget, reason: 'its seat is kept');
    expect(shown(), 1);

    progress.value = PrerenderProgress.none;
    await tester.pump();
    expect(shown(), 1, reason: 'nothing asked for is nothing left to make');

    run.stop();
    await tester.pump();
  });
}
