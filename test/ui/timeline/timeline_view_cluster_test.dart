// THE VIEW CLUSTER: THE ZOOM IS A NUMBER TO DRAG (F-463) — the canvas zoom's
// readout, saying the zoom in percent with every digit it has, a percent a
// pixel of drag, its pencil to type one — each landed on the zoom's 0.1%
// steps inside its range; and its fit beside it.
//
// No test named this widget (audit 2026-09-03) although both the timeline
// and the storyboard tabs mount it. These pins drive it alone.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

void main() {
  const reference = TimelineZoomLimits.referencePixelsPerFrame;

  /// The cluster at [pixelsPerFrame], fed back what it emits, as a host
  /// does — and every zoom it emitted.
  Future<({ValueNotifier<double> zoom, List<double> emitted})> pump(
    WidgetTester tester, {
    double pixelsPerFrame = reference,
    bool turns = true,
  }) async {
    final zoom = ValueNotifier<double>(pixelsPerFrame);
    addTearDown(zoom.dispose);
    final emitted = <double>[];
    void changed(double value) {
      emitted.add(value);
      zoom.value = value;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: zoom,
                builder: (context, pixelsPerFrame, _) => TimelineViewCluster(
                  projectFrameRate: ProjectFrameRate.fps24,
                  pixelsPerFrame: pixelsPerFrame,
                  onPixelsPerFrameChanged: turns ? changed : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return (zoom: zoom, emitted: emitted);
  }

  final readout = find.byKey(const ValueKey<String>('timeline-zoom-readout'));
  String said(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: readout, matching: find.byType(Text)))
      .data!;

  Future<void> drag(WidgetTester tester, double dx) async {
    await tester.drag(readout, Offset(dx, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  testWidgets('the readout says the zoom in percent, every digit it has', (
    tester,
  ) async {
    await pump(tester);
    expect(said(tester), '100.0%');
    await pump(tester, pixelsPerFrame: 12);
    expect(said(tester), '62.5%');
  });

  testWidgets('a drag of ten pixels moves the zoom ten percent, onto a step', (
    tester,
  ) async {
    final run = await pump(tester);
    await drag(tester, 10);
    expect(run.zoom.value, closeTo(reference * 1.1, 1e-9));
    expect(said(tester), '110.0%');
    await drag(tester, -30);
    expect(run.zoom.value, closeTo(reference * 0.8, 1e-9));
    expect(
      run.emitted.every(
        (zoom) =>
            zoom ==
            TimelineZoomLimits.clamped(zoom, framesPerSecond: 24),
      ),
      isTrue,
      reason: 'every zoom it emits is on a step: ${run.emitted}',
    );
  });

  testWidgets('at the top bound a drag further moves nothing', (tester) async {
    final run = await pump(
      tester,
      pixelsPerFrame: TimelineZoomLimits.maxPixelsPerFrame,
    );
    await drag(tester, 10);
    expect(run.emitted, isEmpty);
    expect(said(tester), '200.0%');
  });

  testWidgets('a drag past the widest zoom stops at it', (tester) async {
    final run = await pump(tester, pixelsPerFrame: reference * 0.05);
    await drag(tester, -40);
    expect(
      run.zoom.value,
      TimelineZoomLimits.minPixelsPerFrameAt(24),
      reason: 'held inside the range',
    );
  });

  testWidgets('the pencil types a percent, landed on a step', (tester) async {
    final run = await pump(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-readout-edit')),
    );
    await tester.pump();
    final field = find.byKey(
      const ValueKey<String>('timeline-zoom-readout-input'),
    );
    await tester.enterText(field, '55.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(run.zoom.value, closeTo(reference * 0.555, 1e-9));
    expect(said(tester), '55.5%');
  });

  testWidgets('with no zoom handed in the readout does not turn', (
    tester,
  ) async {
    final run = await pump(tester, turns: false);
    await drag(tester, 10);
    expect(run.zoom.value, reference);
    expect(said(tester), '100.0%');
  });

  testWidgets('🗣️F-463: no − and no + beside it — the fit is beside the '
      'readout', (tester) async {
    await pump(tester);
    for (final gone in [
      'timeline-zoom-in-button',
      'timeline-zoom-out-button',
    ]) {
      expect(find.byKey(ValueKey<String>(gone)), findsNothing, reason: gone);
    }
    final fit = find.byKey(const ValueKey<String>('timeline-zoom-fit-button'));
    expect(
      tester.getRect(fit).left,
      greaterThanOrEqualTo(tester.getRect(readout).right),
    );
  });
}
