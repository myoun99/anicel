@Tags(['benchmark'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_orientation.dart';
import 'package:quick_animaker_v2/src/ui/timeline_tab_host.dart';

/// THE frame-axis baseline, and the guard for the round that follows.
///
/// A row's box is `renderedFrameCount * cellWidth`, so anything that moves
/// either term re-lays-out every visible row: a ZOOM step moves the cell
/// width, and GROWING the cut moves the frame count. Two complaints, one
/// root — and the fix is to stop tying the row's box to the content.
///
/// SCROLL is measured alongside for a reason. It is cheap TODAY precisely
/// because of the thing that makes the other two expensive: the rows ride
/// inside the scrolled content, so a scroll is a layer translation rather
/// than a repaint. A viewport-sized row inverts that unless the translation
/// is preserved, and then the round would have traded a fast scroll for a
/// fast zoom. Reading all three in ONE run is what makes that visible.
///
/// Read the RATIOS, not the absolutes (verify-discipline): this is a debug
/// build and other work shares the machine.
///
/// Baseline recorded 2026-07-25, 24 layers x 200 frames:
///   zoom 112.19ms | grow 88.43ms | scroll 8.05ms/step
///
/// Growth is measured PAST the cut end on purpose. Filling a gap inside the
/// cut costs 1.9ms because the geometry does not move, and growth is free
/// too while the cut is still shorter than the viewport — the render extent
/// floors at what fills the screen. Only a cut longer than the window pays.
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
