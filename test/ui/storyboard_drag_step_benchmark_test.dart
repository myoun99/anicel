@Tags(['benchmark'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart' show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// What ONE step of a cut-length drag costs, on each surface that shows it.
///
/// The two panels subscribe to the SAME preview channel at opposite
/// altitudes. The timeline subscribes at the leaves — the cut-end line, the
/// ruler line, the out-of-cut wash, and a per-row gate that substitutes one
/// Layer — so a step repaints those and leaves the rest of the tree alone.
/// The storyboard subscribes at the ROOT: `storyboard_panel.dart` wraps its
/// whole `_buildBody` in a ValueListenableBuilder and hands it a project
/// rebuilt by `projectWithTimelineDragPreview`, so one cut's length moving
/// re-lays the rail, the ruler, the labels, the scrollbars and every SE
/// strip.
///
/// Both hosts are driven by the same session and the same verb, so the
/// difference between the two columns is the SUBSCRIPTION ALTITUDE and
/// nothing else. That is the number the "cut-scoped preview" round exists
/// to move, and this file is its before-picture.
///
/// Read the RATIO, not the absolutes (verify-discipline): debug build,
/// shared machine. Run it alone:
///   flutter test test/ui/storyboard_drag_step_benchmark_test.dart
void main() {
  /// A film with enough cuts and rows that a panel-wide rebuild has
  /// something to rebuild — the cost the storyboard pays scales with the
  /// strip's width, so a one-cut project would hide it.
  EditorSessionManager filmFor(
    WidgetTester tester, {
    int layers = 6,
    int cuts = 11,
  }) {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    session.addLayerOfKind(LayerKind.storyboard);
    for (var i = 0; i < layers; i += 1) {
      session.addLayer();
    }
    for (var i = 0; i < cuts; i += 1) {
      session.createCut();
    }
    return session;
  }

  /// Drives [rounds] whole-frame steps of a LEAD-edge drag on the first cut
  /// and returns the average wall time per step.
  Future<double> dragStepCost(
    WidgetTester tester,
    EditorSessionManager session, {
    int rounds = 8,
  }) async {
    final cutId = session.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .first
        .id;

    // Warmup, discarded: the first step wears the tree's JIT.
    session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end);
    for (var i = 1; i <= 3; i += 1) {
      session.updateCutEdgeDrag(i);
      await tester.pump();
    }
    session.cancelCutEdgeDrag();
    await tester.pumpAndSettle();

    final watch = Stopwatch();
    session.beginCutEdgeDrag(cutId: cutId, edge: TimelineBlockEdge.end);
    for (var round = 1; round <= rounds; round += 1) {
      // The delta is CUMULATIVE, so every step is a genuinely new preview —
      // a repeated value would publish nothing and measure an empty pump.
      session.updateCutEdgeDrag(round);
      watch.start();
      await tester.pump();
      watch.stop();
    }
    session.cancelCutEdgeDrag();
    await tester.pumpAndSettle();
    return watch.elapsedMicroseconds / rounds / 1000;
  }

  /// Mounts the storyboard host on its own session and returns the average
  /// per-step cost of a cut-length drag.
  Future<double> storyboardStepCost(
    WidgetTester tester, {
    required int layers,
    required int cuts,
  }) async {
    final session = filmFor(tester, layers: layers, cuts: cuts);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return dragStepCost(tester, session);
  }

  testWidgets('one cut-length drag step: storyboard (root subscription) vs '
      'timeline (leaf subscriptions)', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // ⚠️ ONE mount per configuration, and only two of them. A first pass
    // mounted four sizes in this one test to find out whether the panel-wide
    // rebuild scales with the strip's content — and reported 1 cut costing
    // MORE than 12 (360 vs 324ms), which is not physical. Swapping trees in a
    // live tester carries the previous tree's work into the next reading, and
    // the absolutes doubled against the run before it. The RATIO below held
    // across both runs (7.04x, 6.84x) and is the number to trust.
    final storyboard = await storyboardStepCost(tester, layers: 6, cuts: 11);

    final timelineSession = filmFor(tester);
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: timelineSession,
            builder: (context, _) => TimelineTabHost(
              session: timelineSession,
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
    final timeline = await dragStepCost(tester, timelineSession);

    // ignore: avoid_print
    print(
      'DRAG STEP  storyboard ${storyboard.toStringAsFixed(2)}ms  '
      'timeline ${timeline.toStringAsFixed(2)}ms  '
      'ratio ${(storyboard / timeline).toStringAsFixed(2)}x',
    );
    expect(storyboard, greaterThan(0));
    expect(timeline, greaterThan(0));
  });
}
