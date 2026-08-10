import 'package:flutter/material.dart';
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
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';

void main() {
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
            name: 'Cut',
            layers: const [],
            duration: 4,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  CanvasPlaybackController controller() => CanvasPlaybackController(
    resolveProject: project,
    resolveActiveCutId: () => const CutId('cut'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  );

  Future<void> pumpControls(
    WidgetTester tester, {
    required CanvasPlaybackController controller,
    PlaybackScope scope = PlaybackScope.activeCut,
    int Function()? playbackStartFrame,
  }) {
    // ⛔No quality here any more: the selector moved to the settings pill on
    // the 문턱 (2026-08-10), so the transport neither takes it nor shows it.
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackTransportControls(
            controller: controller,
            scope: scope,
            playbackStartFrame: playbackStartFrame,
          ),
        ),
      ),
    );
  }

  testWidgets('play starts this scope from the provided frame', (tester) async {
    final c = controller();
    addTearDown(c.dispose);
    await pumpControls(tester, controller: c, playbackStartFrame: () => 2);

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump();

    expect(c.isActive, isTrue);
    expect(c.isPlaying, isTrue);
    expect(c.scope, PlaybackScope.activeCut);
    expect(c.position!.globalFrameIndex, 2);

    // The button now pauses.
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump();
    expect(c.isPlaying, isFalse);
    expect(c.isActive, isTrue);

    c.stop();
  });

  testWidgets('stop is enabled only while this scope is active', (
    tester,
  ) async {
    final c = controller();
    addTearDown(c.dispose);
    await pumpControls(tester, controller: c);

    IconButton stopButton() => tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('playback-stop-button')),
    );
    expect(stopButton().onPressed, isNull);

    c.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(stopButton().onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-stop-button')),
    );
    await tester.pump();
    expect(c.isActive, isFalse);
  });

  testWidgets('loop toggle flips between loop and once', (tester) async {
    final c = controller();
    addTearDown(c.dispose);
    await pumpControls(tester, controller: c);
    expect(c.loopMode, PlaybackLoopMode.loop);

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-loop-toggle')),
    );
    await tester.pump();
    expect(c.loopMode, PlaybackLoopMode.once);

    await tester.tap(
      find.byKey(const ValueKey<String>('playback-loop-toggle')),
    );
    await tester.pump();
    expect(c.loopMode, PlaybackLoopMode.loop);
  });

  testWidgets('the quality selector is NOT on the transport', (tester) async {
    // It moved to the settings pill on the 문턱 (유저 확정, 2026-08-10):
    // a setting touched once a project does not belong on the one row that
    // has to read at a glance. Guarded here rather than merely deleted,
    // because "the transport lost a control" is exactly the kind of change
    // a later round re-adds by reflex.
    final c = controller();
    addTearDown(c.dispose);
    await pumpControls(tester, controller: c);

    expect(
      find.byKey(const ValueKey<String>('playback-quality-selector')),
      findsNothing,
    );
    expect(find.text('1/2'), findsNothing);
  });

  testWidgets('a scope only controls its own playback', (tester) async {
    final c = controller();
    addTearDown(c.dispose);
    // Storyboard transport while the TIMELINE scope is playing.
    c.play(scope: PlaybackScope.activeCut);
    await pumpControls(tester, controller: c, scope: PlaybackScope.allCuts);

    // Play here starts all-cuts playback rather than pausing the other scope.
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump();
    expect(c.scope, PlaybackScope.allCuts);

    c.stop();
  });
}
