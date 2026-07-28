import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import 'timeline_cell_probe.dart';

/// THE frame-axis window (zoom round): the row's laid-out box stops being
/// `frames * cellWidth` so a zoom step re-lays-out one box per row instead of
/// everything inside it — and the row still draws and answers pointers at the
/// same place on screen.
///
/// The screen positions here are asserted against an INDEPENDENT formula
/// (content x minus the scroll offset), not against the painter's own
/// coordinates: a window that shifted painting and hit-testing together but
/// away from the truth would satisfy the painter's own probe.
void main() {
  group('geometry math', () {
    const base = TimelineFrameGeometry(
      frameCellExtent: 24,
      frameStartIndex: 0,
      frameEndIndexExclusive: 200,
    );

    test('without a window nothing moves', () {
      expect(base.isWindowed, isFalse);
      expect(base.mainExtent, 200 * 24);
      expect(base.contentMainExtent, 200 * 24);
      expect(base.edgeAt(10), 240);
    });

    test('a window shifts row-local coordinates and keeps the content size',
        () {
      final windowed = base.windowed(originPx: 960, extentPx: 3448);
      expect(windowed.isWindowed, isTrue);
      // What the box LAYS OUT at: the constant window.
      expect(windowed.mainExtent, 3448);
      // What the box REPORTS as its size: the content, unchanged.
      expect(windowed.contentMainExtent, base.contentMainExtent);
      // Row-local coordinates are window-local now.
      expect(windowed.edgeAt(40), base.edgeAt(40) - 960);
      expect(windowed.leadingFrameSpacerWidth, -960);
    });

    test('the window extent is independent of the cell width', () {
      final zoomedIn = base.windowed(originPx: 960, extentPx: 3448);
      final zoomedOut = const TimelineFrameGeometry(
        frameCellExtent: 48,
        frameStartIndex: 0,
        frameEndIndexExclusive: 200,
      ).windowed(originPx: 960, extentPx: 3448);
      expect(zoomedIn.mainExtent, zoomedOut.mainExtent,
          reason: 'a zoom step must not move what the row is laid out at');
      expect(zoomedIn.contentMainExtent == zoomedOut.contentMainExtent, isFalse,
          reason: 'sanity: the CONTENT did move');
    });
  });

  Future<EditorSessionManager> pumpTimeline(
    WidgetTester tester,
    ValueNotifier<double> zoom,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    // A cut long enough that the content runs well past the viewport.
    for (var frame = 0; frame < 300; frame += 4) {
      session.selectFrameIndex(frame);
      if (session.canCreateDrawingAtCurrentFrame) {
        session.createDrawingAtCurrentFrame();
      }
    }
    session.selectFrameIndex(0);

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
    return session;
  }

  RenderBox rowChildBoxFor(WidgetTester tester, String layerId) {
    // The row's cell strip: its render object is inside the frame-axis box,
    // so its size IS what the box lays the row out at.
    final finder = find.byKey(ValueKey<String>('timeline-row-cells-$layerId'));
    return tester.renderObject<RenderBox>(finder);
  }

  testWidgets('a zoom step leaves the drawing row\'s laid-out box alone while '
      'the content grows under it', (tester) async {
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);
    final session = await pumpTimeline(tester, zoom);
    final layerId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id
        .value;

    final before = rowChildBoxFor(tester, layerId).size;
    expect(before.width, greaterThan(0));

    zoom.value = 48;
    await tester.pumpAndSettle();

    expect(
      rowChildBoxFor(tester, layerId).size,
      before,
      reason: 'the window is a pixel extent — doubling the cell width must '
          'not relayout the row subtree',
    );
    // Sanity: the zoom really did land.
    expect(
      timelineRowCellsPainterFor(tester, layerId).frameCellExtent,
      48,
    );
  });

  testWidgets('cells paint and answer pointers where the content says, after '
      'a scroll', (tester) async {
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);
    final session = await pumpTimeline(tester, zoom);
    final layerId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id
        .value;
    final viewport = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-viewport'),
    );
    final viewportRect = tester.getRect(viewport);

    // Scroll well past the window's first bucket. Driven through the
    // position rather than a drag: a finger pan over the cells belongs to
    // the range-select gesture under the timeline's input policy, and what
    // is under test here is the coordinate system at a scrolled offset.
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: viewport, matching: find.byType(Scrollable)),
        )
        .position;
    position.jumpTo(1500);
    await tester.pumpAndSettle();
    final scrolled = position.pixels;
    expect(scrolled, greaterThan(200), reason: 'sanity: the view scrolled');

    // The INDEPENDENT truth: frame F sits at content x = F * cellWidth, and
    // the viewport shows content x at screen x - left + offset.
    const cellWidth = 24.0;
    final frameUnderPointer =
        ((scrolled + viewportRect.width / 2) / cellWidth).floor();
    final expectedLeft =
        viewportRect.left + frameUnderPointer * cellWidth - scrolled;

    final painted = timelineCellGlobalRect(tester, layerId, frameUnderPointer);
    expect(
      painted.left,
      moreOrLessEquals(expectedLeft, epsilon: 0.5),
      reason: 'the windowed row must paint the cell where the content says',
    );

    // And the pointer agrees: tapping that cell selects that frame.
    session.selectFrameIndex(0);
    await tester.pump();
    await tester.tapAt(painted.center);
    await tester.pumpAndSettle();
    expect(session.currentFrameIndex, frameUnderPointer);
  });

  testWidgets('a cell far outside the window is not clickable, and scrolling '
      'to it makes it so', (tester) async {
    final zoom = ValueNotifier<double>(24);
    addTearDown(zoom.dispose);
    final session = await pumpTimeline(tester, zoom);
    final layerId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id
        .value;

    // Frame 250 is 6000px into the content: outside the window AND off
    // screen, so the row's box does not reach it. That is the deal the
    // window makes, and it is only ever true off screen.
    final far = timelineCellGlobalRect(tester, layerId, 250);
    expect(
      far.left,
      greaterThan(tester.getRect(find.byType(MaterialApp)).right),
      reason: 'sanity: frame 250 is off screen at this scroll offset',
    );

    final viewport = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-viewport'),
    );
    tester
        .state<ScrollableState>(
          find.descendant(of: viewport, matching: find.byType(Scrollable)),
        )
        .position
        .jumpTo(5200);
    await tester.pumpAndSettle();

    final now = timelineCellGlobalRect(tester, layerId, 250);
    expect(
      tester.getRect(viewport).contains(now.center),
      isTrue,
      reason: 'sanity: frame 250 is on screen now',
    );
    session.selectFrameIndex(0);
    await tester.pump();
    await tester.tapAt(now.center);
    await tester.pumpAndSettle();
    expect(
      session.currentFrameIndex,
      250,
      reason: 'the window followed the scroll, so the cell answers pointers',
    );
  });
}
