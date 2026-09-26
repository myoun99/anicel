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

/// I-22 ③: A TICK REBUILDS NO TRANSPORT BUTTON.
///
/// The playback controller notifies on every frame it plays, and the
/// transport row listened to all of it — each button, its face and its
/// tooltip rebuilt at the playback rate, in the timeline's transport and the
/// storyboard's both, while not one of them reads the frame (measured on the
/// ten-minute film: the row's tooltips and faces were ~100ms of a 202-frame
/// playback sample, debug). The row now rebuilds when what it SHOWS moves.
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
            duration: 40,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  testWidgets('a tick rebuilds none of the row — and a stop, which it shows, '
      'does', (tester) async {
    final controller = CanvasPlaybackController(
      resolveProject: project,
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    )..attachTicker(const TestVSync());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackTransportControls(
            controller: controller,
            scope: PlaybackScope.activeCut,
          ),
        ),
      ),
    );
    Row row() => tester.widget<Row>(
      find.byKey(const ValueKey<String>('playback-transport-activeCut')),
    );

    final stopped = row();
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    final playing = row();
    expect(
      identical(playing, stopped),
      isFalse,
      reason: 'the play button shows the play, so the row rebuilds for it',
    );
    // A tick a frame (10 fps): three frames played, none dropped.
    final frames = <int>{};
    for (var tick = 0; tick < 3; tick += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      frames.add(controller.position!.globalFrameIndex);
    }
    expect(frames, hasLength(3), reason: 'premise: three frames played');
    expect(controller.droppedFrames, 0, reason: 'premise: none dropped');

    expect(identical(row(), playing), isTrue, reason: 'no tick rebuilt it');

    controller.stop();
    await tester.pump();
    expect(
      identical(row(), playing),
      isFalse,
      reason: 'the play button shows the stop, so the row rebuilds for it',
    );
  });
}
