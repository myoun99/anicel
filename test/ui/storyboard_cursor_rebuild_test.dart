import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';
import 'storyboard_cut_block_probe.dart';

/// W4 perf pass: the storyboard playhead rides its own listenable (the
/// cursor-layer pattern) — a cursor/playback tick moves the playhead
/// overlay and repaints the ruler, while the strips, blocks and rails
/// keep their exact widget instances (no per-tick panel rebuild).
void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );

  final project = Project(
    id: const ProjectId('cursor-rebuild-project'),
    name: 'Cursor Rebuild',
    createdAt: DateTime.utc(2026, 7, 11),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [cut('cut-a', 12), cut('cut-b', 12)],
      ),
    ],
  );

  testWidgets('a playhead tick moves ONLY the overlay — cut blocks keep '
      'their widget instances', (tester) async {
    const pixelsPerFrame = 8.0;
    final playhead = ValueNotifier<int?>(0);
    addTearDown(playhead.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: project,
            activeCutId: const CutId('cut-a'),
            onCutSelected: (_) {},
            playheadFrame: playhead,
            pixelsPerFrame: pixelsPerFrame,
          ),
        ),
      ),
    );

    final overlay = find.byKey(const ValueKey<String>('storyboard-playhead'));
    expect(overlay, findsOneWidget);

    // The blocks are one PAINTER now, so "did the row rebuild" is asked of
    // the painter's identity rather than of a widget per cut.
    final painterBefore = cutBlocksPainter(tester);
    final overlayXBefore = tester.getTopLeft(overlay).dx;

    playhead.value = 5;
    await tester.pump();

    // The overlay followed the tick...
    expect(tester.getTopLeft(overlay).dx - overlayXBefore, 5 * pixelsPerFrame);
    // ...and the row was NOT rebuilt (the panel build never ran again).
    expect(identical(cutBlocksPainter(tester), painterBefore), isTrue);
  });

  testWidgets('a null playhead value hides the overlay without a panel '
      'rebuild', (tester) async {
    final playhead = ValueNotifier<int?>(3);
    addTearDown(playhead.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: project,
            activeCutId: const CutId('cut-a'),
            onCutSelected: (_) {},
            playheadFrame: playhead,
          ),
        ),
      ),
    );

    final overlay = find.byKey(const ValueKey<String>('storyboard-playhead'));
    expect(overlay, findsOneWidget);
    final painterBefore = cutBlocksPainter(tester);

    playhead.value = null;
    await tester.pump();

    expect(overlay, findsNothing);
    expect(identical(cutBlocksPainter(tester), painterBefore), isTrue);
  });
}
