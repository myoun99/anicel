import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// 🚨I-22 ③: THE STANDING RING RIDES ITS OWN LAYER.
///
/// The storyboard's strips sit in ONE RepaintBoundary so that the playhead
/// moving over them re-rasterizes none of them (R12-⑥). The ring around the
/// cell you stand on follows that same playhead — and it was mounted INSIDE
/// the boundary, so every playhead move repainted every strip: at ten
/// minutes, every edge grip of the film and the plate grounds under them,
/// on every playback frame (measured at 0.16px, profile build: the edit
/// chrome's paint 508ms of a 2,169ms tick sample). It rides a boundary of
/// its own now, as the timeline's playhead does — and since F-212 the ring
/// paints nothing, but the standing cell still moves with the playhead.
void main() {
  const frames = 24;

  Project project() => Project(
    id: const ProjectId('standing'),
    name: 'Standing',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (var i = 0; i < 4; i += 1)
            Cut(
              id: CutId('cut-$i'),
              name: 'cut-$i',
              duration: frames,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('cut-$i-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
      ),
    ],
  );

  testWidgets('a playhead move inside a cut moves the ring and repaints no '
      'strip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final strips =
        tester
                .renderObject(
                  find.byKey(
                    const ValueKey<String>('storyboard-timeline-scroll-content'),
                  ),
                )
                .parent!
            as RenderRepaintBoundary;
    final ring = find.byKey(const ValueKey<String>('storyboard-standing-cell'));
    expect(ring, findsOneWidget, reason: 'premise: the rail stands somewhere');

    final perFrame = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;
    final ruler = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-ruler')),
    );
    final gesture = await tester.startGesture(
      Offset(ruler.left + 2 * perFrame + 2, ruler.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final ringAtTwo = tester.getRect(ring);
    expect(strips.debugNeedsPaint, isFalse, reason: 'premise: painted');

    // Frame 2 → 12: the playhead stays inside cut-0. The frame runs up to its
    // layout, where the ring's move lands — and stops before the paint, so
    // what is waiting to repaint can be read.
    await gesture.moveBy(Offset(10 * perFrame, 0));
    await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
    expect(
      strips.debugNeedsPaint,
      isFalse,
      reason: 'the ring moved on its own layer — the strips wait for nothing',
    );
    await tester.pump();
    expect(
      tester.getRect(ring).left,
      greaterThan(ringAtTwo.left),
      reason: 'premise: the ring followed the playhead',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
