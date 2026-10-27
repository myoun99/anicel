import 'package:flutter/foundation.dart' show describeIdentity;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// The transport of the one cut above, mounted.
  Future<CanvasPlaybackController> pumpTransport(WidgetTester tester) async {
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
    return controller;
  }

  Row transportRow(WidgetTester tester) => tester.widget<Row>(
    find.byKey(const ValueKey<String>('playback-transport-activeCut')),
  );

  testWidgets('a tick rebuilds none of the row — and a stop, which it shows, '
      'does', (tester) async {
    final controller = await pumpTransport(tester);
    Row row() => transportRow(tester);

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

  // A frame is dropped when the device misses it — exactly when there is no
  // time to spare. The count is its own box's to show (F-463 ②: over the play
  // button), not the buttons'.
  testWidgets('a dropped frame rebuilds the drop count and none of the row '
      'around it', (tester) async {
    final controller = await pumpTransport(tester);
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final playing = transportRow(tester);
    expect(controller.droppedFrames, 0, reason: 'premise: none dropped yet');

    // Three frames' time in one pump (10 fps): two were never shown.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.droppedFrames, 2, reason: 'premise: two dropped');

    expect(find.text('2 dropped'), findsOneWidget, reason: 'its box shows it');
    expect(
      identical(transportRow(tester), playing),
      isTrue,
      reason: 'and not one button was rebuilt for it',
    );
    controller.stop();
    await tester.pump();
  });

  // 🔬A count laid the row out up to the panel's tab strip — a tick's layer
  // — and re-walked the strip's semantics whole: 108 render objects at each
  // count a run dropped (the real app, debug, 10-12).
  testWidgets('a dropped frame lays out and describes the drop count alone',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await pumpTransport(tester);
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final row = tester.renderObject(
      find.byKey(const ValueKey<String>('playback-transport-activeCut')),
    );

    final laid = <String>[];
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('Laying out')) {
        laid.add(message);
      }
    };
    debugPrintLayouts = true;
    try {
      // Three frames' time in one pump (10 fps): two were never shown.
      await tester.pump(const Duration(milliseconds: 300));
    } finally {
      // Inside the body: the binding checks its switches before a tear-down
      // would run.
      debugPrintLayouts = false;
      debugPrint = saved;
    }
    expect(controller.droppedFrames, 2, reason: 'premise: two dropped');
    expect(laid, isNotEmpty, reason: 'LIVENESS: the count was laid out');
    expect(
      laid.where((line) => line.contains(describeIdentity(row))),
      isEmpty,
      reason: '↩️the count laid the row out again, and up to the strip',
    );

    // A layout marks its semantics up to the nearest boundary: the count's
    // box's.
    RenderObject boundaryOf(RenderObject node) {
      var at = node;
      while (at.parent != null) {
        final config = SemanticsConfiguration();
        // ignore: invalid_use_of_protected_member
        at.describeSemanticsConfiguration(config);
        if (config.isSemanticBoundary) {
          return at;
        }
        at = at.parent!;
      }
      return at;
    }

    var inside = false;
    for (
      RenderObject? at = boundaryOf(
        tester.renderObject(
          find.byKey(const ValueKey<String>('playback-dropped-indicator')),
        ),
      );
      at != null;
      at = at.parent
    ) {
      inside = inside || identical(at, row);
    }
    expect(inside, isTrue, reason: 'the walk stops inside the row');
    controller.stop();
    await tester.pump();
    semantics.dispose();
  });
}
