@Tags(['benchmark'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// THE frame-axis baseline, and the guard for the round that follows.
///
/// ZOOM is geometry-bound. A row's box WAS `renderedFrameCount * cellWidth`,
/// so moving the cell width re-laid-out every visible row and everything
/// inside it — ~25 render objects a row at 24 layers. The frame-axis WINDOW
/// (TimelineFrameGeometry.windowed) lays each painted row out at a constant
/// pixel extent instead and paints/hit-tests it at the scrolled origin, so
/// the step now moves one box per row: measured 731 -> 267 layouts, which is
/// deterministic and therefore the number to trust when the machine is busy.
///
/// GROW is NOT. It reads like a geometry cost and is not one: creating a
/// drawing INSIDE the cut, where the render extent does not move at all,
/// costs the same as creating past the cut end (measured 43.5 vs 39.4ms,
/// 48.9 vs 41.2ms — the inside case is if anything dearer). What both pay
/// for is the SESSION NOTIFY rebuilding the panel's chrome. An earlier
/// "1.9ms inside the cut" reading came from a harness with no session
/// subscription, so it never included the rebuild at all.
///
/// SCROLL is measured alongside for a reason. It is cheap TODAY precisely
/// because of the thing that makes zoom expensive: the rows ride inside the
/// scrolled content, so a scroll is a layer translation rather than a
/// repaint. A viewport-sized row inverts that unless the translation is
/// preserved, and then the round would have traded a fast scroll for a fast
/// zoom. Reading all three in ONE run is what makes that visible.
///
/// Read the RATIOS, not the absolutes (verify-discipline): this is a debug
/// build and other work shares the machine — the first baseline recorded
/// here (zoom 112 / grow 88) was measured with a parallel test run on the
/// same box and reads ~50% high against a quiet one.
///
/// Recorded 2026-07-25 on a quiet machine, 24 layers x 200 frames, master
/// vs the chrome-gating round, alternating runs:
///   before  zoom 71.9 / 71.1ms | grow 47.3 / 50.4ms | scroll 6.9 / 6.5ms
///   after   zoom 71.1 / 73.7ms | grow 36.3 / 37.2ms | scroll 6.1 / 6.3ms
/// Widget rebuilds per notify, which are deterministic: 1201 -> 774.
///
/// The frame-axis window round followed, measured against a detached master
/// worktree while another session had the machine (so read the ratios, and
/// the layout counts above all):
///   zoom   best-of-six 108.9ms -> 69.4ms; layouts per step 731 -> 267
///   grow   55 layouts -> 55; it was never a layout cost
///   scroll 76 layouts over 8 steps -> 76; the window rides the same bucket
///          the painters do, so a crossing costs one box per row and the
///          frames between crossings cost nothing
///
/// Growth is measured past the cut end because that is where the geometry
/// DOES move, so the two costs can still be told apart: growth is free while
/// the cut is shorter than the viewport (the render extent floors at what
/// fills the screen), and only a cut longer than the window moves it.
void main() {
  testWidgets('frame axis: zoom / grow / scroll', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = EditorSessionManager(initialProject: createDefaultProject());
    for (var i = 0; i < 24; i += 1) {
      session.addLayer();
    }
    // A cut LONGER than the viewport (66 cells at 24px on 1600px): below
    // that, growth is absorbed by the viewport-fill floor and costs nothing.
    for (final layer in session.layers.toList()) {
      session.selectLayer(layer.id);
      for (var frame = 0; frame < 200; frame += 4) {
        session.selectFrameIndex(frame);
        if (session.canCreateDrawingAtCurrentFrame) {
          session.createDrawingAtCurrentFrame();
        }
      }
    }
    session.selectLayer(session.layers.first.id);
    session.selectFrameIndex(0);

    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: zoom.value,
              pixelsPerFrameListenable: zoom,
              onPixelsPerFrameChanged: (value) => zoom.value = value,
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Warmup, discarded — the first size measured otherwise wears the whole
    // tree's JIT.
    for (var i = 0; i < 3; i += 1) {
      zoom.value = 24 + i.toDouble();
      await tester.pump();
    }
    zoom.value = 24;
    await tester.pumpAndSettle();

    const rounds = 6;

    final zoomWatch = Stopwatch();
    for (var round = 0; round < rounds; round += 1) {
      zoom.value = 24 + (round + 1) * 2;
      zoomWatch.start();
      await tester.pump();
      zoomWatch.stop();
    }
    zoom.value = 24;
    await tester.pumpAndSettle();

    // GROW: create past the cut end, so the frame geometry moves.
    final growWatch = Stopwatch();
    for (var round = 0; round < rounds; round += 1) {
      session.selectFrameIndex(400 + round);
      growWatch.start();
      session.createDrawingAtCurrentFrame();
      await tester.pump();
      growWatch.stop();
    }

    // SCROLL: a drag along the frame axis, one pump per step — the thing
    // that is cheap TODAY and must not become expensive.
    final scrollWatch = Stopwatch();
    final viewport = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-viewport'),
    );
    var scrollSteps = 0;
    if (viewport.evaluate().isNotEmpty) {
      final start = tester.getCenter(viewport);
      final gesture = await tester.startGesture(start);
      await tester.pump();
      for (var round = 0; round < rounds * 4; round += 1) {
        await gesture.moveBy(const Offset(-13, 0));
        scrollWatch.start();
        await tester.pump();
        scrollWatch.stop();
        scrollSteps += 1;
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    String per(Stopwatch watch, int n) =>
        (watch.elapsedMicroseconds / (n * 1000)).toStringAsFixed(2);
    // ignore: avoid_print
    print(
      'FRAME AXIS @24L x 200f: zoom ${per(zoomWatch, rounds)}ms '
      '| grow ${per(growWatch, rounds)}ms '
      '| scroll ${scrollSteps == 0 ? "viewport not found" : "${per(scrollWatch, scrollSteps)}ms/step"}',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    await tester.pumpAndSettle();
    expect(rounds, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
