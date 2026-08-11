import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';

import 'timeline/timeline_cell_probe.dart';
import 'timeline/timeline_ruler_probe.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_playhead.dart';

/// Classic 48×52 geometry for this file's pixel oracles (the slim 24×28
/// default is pinned in timeline_grid_metrics_test).
const _testMetrics = TimelineGridMetrics(
  frameCellWidth: 48,
  layerRowHeight: 52,
);

/// A vertical scroll gesture anchored inside the FRAME GRID.
///
/// The rail is a sticky overlay OUTSIDE the vertical scrollable, so a
/// gesture landing on it scrolls nothing. That never mattered while the
/// rail was narrower than the scrollable's centre; R27 #6 widened it past
/// that point, so these tests say where they press instead of relying on
/// a centre that happens to miss the rail.
Future<void> _dragFrameGridVertically(WidgetTester tester, double dy) async {
  final area = find.byKey(const ValueKey<String>('timeline-frame-grid-area'));
  await tester.dragFrom(
    tester.getTopLeft(area) + const Offset(20, 20),
    Offset(0, dy),
  );
  await tester.pumpAndSettle();
}

final Matcher _isInsideTestRoot = isA<Rect>()
    .having((rect) => rect.left, 'left', greaterThanOrEqualTo(0))
    .having((rect) => rect.top, 'top', greaterThanOrEqualTo(0))
    .having((rect) => rect.right, 'right', lessThanOrEqualTo(800))
    .having((rect) => rect.bottom, 'bottom', lessThanOrEqualTo(600));

Future<void> _scrollFrameGridUntilKeyVisible(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  // Cell keys are painter-probed now (UI-R9 #12b): visibility = the
  // painter window contains the frame AND its global rect fits the root.
  final cell = parseTimelineCellKey(key.value);
  final viewport = find.byKey(
    const ValueKey<String>('timeline-frame-scroll-viewport'),
  );
  final testRootSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final testRootRect = Offset.zero & testRootSize;

  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (timelineCellInWindow(tester, cell.layerId, cell.frameIndex)) {
      final targetRect = timelineCellGlobalRect(
        tester,
        cell.layerId,
        cell.frameIndex,
      );
      if (testRootRect.contains(targetRect.topLeft) &&
          testRootRect.contains(targetRect.bottomRight)) {
        return;
      }
    }

    // Scroll gestures WALL at the built extent (UI-R12 #16) — step past
    // it the contract's way: the ruler edge-pan's overshoot jump, which
    // materializes the frames the view needs.
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: viewport, matching: find.byType(Scrollable)),
        )
        .position;
    position.jumpTo(position.maxScrollExtent + 240);
    await tester.pump();
  }

  fail('Expected $key to be rendered inside the test root after scrolling.');
}

void main() {
  testWidgets(
    'vertical scrollbar does not read unsettled scroll metrics on first pump',
    (tester) async {
      final layers = List<Layer>.generate(
        12,
        (index) => _layer(id: 'layer-${index + 1}', name: 'Layer ${index + 1}'),
      );

      await tester.pumpWidget(_grid(layers: layers, playbackFrameCount: 40));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('timeline-vertical-scrollbar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-vertical-scrollbar-thumb')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'sticky frame ruler lays out full content width without overflow',
    (tester) async {
      // The rail widened to 372 (R3 #8 → R4 #9) then 434 (R27 #6, the
      // blend column); keep the frame viewport NARROW but non-degenerate
      // so the ruler layout is still exercised.
      await tester.binding.setSurfaceSize(const Size(514, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_grid(playbackFrameCount: 96));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('timeline-frame-ruler')),
        findsOneWidget,
      );
      expect(timelineRulerPaintFinder(), findsOneWidget);
    },
  );

  testWidgets('renders fixed layer controls rail and frame scroll structure', (
    tester,
  ) async {
    await tester.pumpWidget(_grid());

    final stickyHeader = find.byKey(
      const ValueKey<String>('timeline-sticky-header-row'),
    );
    final rail = find.byKey(
      const ValueKey<String>('timeline-layer-controls-rail'),
    );
    final scrollbarArea = find.byKey(
      const ValueKey<String>('timeline-scrollbar-area'),
    );
    final horizontalScrollbar = find.byKey(
      const ValueKey<String>('timeline-horizontal-scrollbar'),
    );
    final scrollbarViewport = find.byKey(
      const ValueKey<String>('timeline-horizontal-scrollbar-viewport'),
    );
    final viewport = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-viewport'),
    );
    final content = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-content'),
    );
    final frameRuler = find.byKey(
      const ValueKey<String>('timeline-frame-ruler'),
    );
    final frameHeaderRow = timelineRulerPaintFinder();
    final frameGridArea = find.byKey(
      const ValueKey<String>('timeline-frame-grid-area'),
    );
    final bottomScrollbarRail = find.byKey(
      const ValueKey<String>('timeline-bottom-scrollbar-rail'),
    );
    // The rail's own bar took the left spacer's place on the bottom line
    // (rail-window round): the rail is scrollable now, so the strip under
    // it is a scrollbar rather than a blank.
    final railScrollbar = find.byKey(
      const ValueKey<String>('timeline-rail-scrollbar'),
    );
    final railSplitter = find.byKey(
      const ValueKey<String>('timeline-rail-splitter'),
    );
    final horizontalScrollbarTrack = find.byKey(
      const ValueKey<String>('timeline-horizontal-scrollbar-track'),
    );
    final horizontalScrollbarThumb = find.byKey(
      const ValueKey<String>('timeline-horizontal-scrollbar-thumb'),
    );
    final verticalScrollbar = find.byKey(
      const ValueKey<String>('timeline-vertical-scrollbar'),
    );
    final verticalScrollbarTrack = find.byKey(
      const ValueKey<String>('timeline-vertical-scrollbar-track'),
    );
    final verticalScrollbarThumb = find.byKey(
      const ValueKey<String>('timeline-vertical-scrollbar-thumb'),
    );
    final verticalScrollbarBottomSpacer = find.byKey(
      const ValueKey<String>('timeline-vertical-scrollbar-bottom-spacer'),
    );
    final verticalScrollViewport = find.byKey(
      const ValueKey<String>('timeline-vertical-scroll-viewport'),
    );

    expect(stickyHeader, findsOneWidget);
    expect(rail, findsOneWidget);
    expect(scrollbarArea, findsOneWidget);
    expect(horizontalScrollbar, findsOneWidget);
    expect(scrollbarViewport, findsOneWidget);
    expect(viewport, findsOneWidget);
    expect(content, findsOneWidget);
    expect(frameRuler, findsOneWidget);
    expect(frameHeaderRow, findsOneWidget);
    expect(frameGridArea, findsOneWidget);
    expect(bottomScrollbarRail, findsOneWidget);
    expect(railScrollbar, findsOneWidget);
    expect(railSplitter, findsOneWidget);
    expect(horizontalScrollbarTrack, findsOneWidget);
    expect(horizontalScrollbarThumb, findsOneWidget);
    expect(verticalScrollbar, findsOneWidget);
    expect(verticalScrollbarTrack, findsOneWidget);
    expect(verticalScrollbarThumb, findsOneWidget);
    expect(verticalScrollbarBottomSpacer, findsOneWidget);
    expect(verticalScrollViewport, findsOneWidget);
    expect(find.text('Layer 1'), findsOneWidget);
    expect(find.text('Layer 2'), findsOneWidget);
    expect(
      find.descendant(
        of: stickyHeader,
        matching: find.byKey(const ValueKey<String>('legend-layer')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rail,
        matching: find.byKey(const ValueKey<String>('legend-layer')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: viewport,
        matching: find.byKey(const ValueKey<String>('legend-layer')),
      ),
      findsNothing,
    );
    expect(find.descendant(of: viewport, matching: rail), findsNothing);
    expect(
      find.descendant(of: scrollbarViewport, matching: viewport),
      findsOneWidget,
    );
    expect(
      find.descendant(of: verticalScrollViewport, matching: rail),
      findsOneWidget,
    );
    expect(
      find.descendant(of: verticalScrollViewport, matching: frameGridArea),
      findsOneWidget,
    );
    expect(
      find.descendant(of: horizontalScrollbar, matching: bottomScrollbarRail),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomScrollbarRail,
        matching: horizontalScrollbarTrack,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomScrollbarRail,
        matching: horizontalScrollbarThumb,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: railScrollbar, matching: horizontalScrollbarTrack),
      findsNothing,
    );
    expect(
      find.descendant(of: railScrollbar, matching: horizontalScrollbarThumb),
      findsNothing,
    );
    expect(
      find.descendant(of: frameGridArea, matching: content),
      findsOneWidget,
    );
    expect(find.descendant(of: content, matching: frameRuler), findsNothing);
    expect(
      find.descendant(of: frameRuler, matching: frameHeaderRow),
      findsOneWidget,
    );
    expect(
      find.descendant(of: content, matching: bottomScrollbarRail),
      findsNothing,
    );
    expect(
      tester.getTopLeft(bottomScrollbarRail).dy,
      greaterThan(tester.getTopLeft(frameGridArea).dy),
    );

    // The rail-window arrangement, left to right:
    //   [16 layer-axis bar][rail window][5 splitter][frame cells]
    // — with the bar on the grid's EDGE, where it stopped occupying the
    // one gap a splitter could live in.
    final gridLeft = tester.getRect(scrollbarArea).left;
    final railRect = tester.getRect(rail);
    final frameGridAreaRect = tester.getRect(frameGridArea);
    final railScrollbarRect = tester.getRect(railScrollbar);
    final splitterRect = tester.getRect(railSplitter);
    final bottomRailRect = tester.getRect(bottomScrollbarRail);
    final horizontalScrollbarRect = tester.getRect(horizontalScrollbar);
    final verticalScrollbarRect = tester.getRect(verticalScrollbar);
    final verticalBottomSpacerRect = tester.getRect(
      verticalScrollbarBottomSpacer,
    );

    expect(verticalScrollbarRect.left, moreOrLessEquals(gridLeft));
    expect(verticalScrollbarRect.width, moreOrLessEquals(16));
    expect(verticalBottomSpacerRect.left, moreOrLessEquals(gridLeft));
    expect(verticalBottomSpacerRect.width, moreOrLessEquals(16));
    // Untouched, the rail window is the rail's NATURAL width — nothing is
    // cut until the user drags the splitter.
    expect(railRect.left, moreOrLessEquals(gridLeft + 16));
    expect(railRect.width, moreOrLessEquals(434));
    expect(splitterRect.left, moreOrLessEquals(railRect.right));
    expect(splitterRect.width, moreOrLessEquals(5));
    expect(frameGridAreaRect.left, moreOrLessEquals(splitterRect.right));
    // The rail's own bar sits under the rail and stops at the splitter.
    expect(railScrollbarRect.left, moreOrLessEquals(railRect.left));
    expect(railScrollbarRect.width, moreOrLessEquals(railRect.width));
    expect(bottomRailRect.left, moreOrLessEquals(frameGridAreaRect.left));
    expect(bottomRailRect.width, moreOrLessEquals(frameGridAreaRect.width));
    expect(
      horizontalScrollbarRect.left,
      greaterThanOrEqualTo(railScrollbarRect.right),
    );
    expect(horizontalScrollbarRect.left, moreOrLessEquals(bottomRailRect.left));
    expect(
      horizontalScrollbarRect.width,
      moreOrLessEquals(bottomRailRect.width),
    );
    expect(
      tester.getRect(horizontalScrollbarTrack).width,
      moreOrLessEquals(bottomRailRect.width),
    );

    expect(timelineHeaderInWindow(tester, 0), isTrue);
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-visibility-layer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-opacity-layer-1')),
      findsOneWidget,
    );
  });

  testWidgets('the splitter cuts the legend and the rows at the same edge', (
    tester,
  ) async {
    // The user's rule: "the legend and the rows are one body". A narrowed
    // window must therefore end at ONE x — R6a shipped the failure this
    // pins against, clipping the legend while scaling the header down.
    final rail = LayerRailExtent();
    addTearDown(rail.dispose);
    await tester.pumpWidget(_grid(railExtent: rail));

    final railBody = find.byKey(
      const ValueKey<String>('timeline-layer-controls-rail'),
    );
    final legend = find.byKey(const ValueKey<String>('legend-layer'));
    final frameGridArea = find.byKey(
      const ValueKey<String>('timeline-frame-grid-area'),
    );
    final gridLeft = tester
        .getRect(find.byKey(const ValueKey<String>('timeline-scrollbar-area')))
        .left;
    final wideFrameArea = tester.getRect(frameGridArea).width;

    rail.resizeBy(-234, naturalExtent: 434);
    await tester.pump();

    // The window is 200 wide; the rail INSIDE it never moved or shrank.
    expect(tester.getSize(railBody).width, moreOrLessEquals(434));
    final windowRight = gridLeft + 16 + 200;
    expect(
      tester.getRect(find.byType(LayerRailWindow).first).right,
      moreOrLessEquals(windowRight),
    );
    // Both windows — the legend's and the rows' — end at that same x.
    for (final window in tester.widgetList<LayerRailWindow>(
      find.byType(LayerRailWindow),
    )) {
      expect(
        tester.getRect(find.byWidget(window)).right,
        moreOrLessEquals(windowRight),
        reason: 'every rail window is cut at the same edge',
      );
    }
    // The legend is still laid out whole (cut, not repacked).
    expect(tester.getRect(legend).left, greaterThanOrEqualTo(gridLeft));
    // And the frame cells took the width the rail gave up.
    expect(
      tester.getRect(frameGridArea).width,
      moreOrLessEquals(wideFrameArea + 234),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey<String>('timeline-rail-splitter')))
          .left,
      moreOrLessEquals(windowRight),
    );
  });

  testWidgets('keeps header and add-layer cell sticky during vertical scroll', (
    tester,
  ) async {
    final manyLayers = List<Layer>.generate(
      30,
      (index) => _layer(id: 'layer-${index + 1}', name: 'Layer ${index + 1}'),
    );

    await tester.pumpWidget(_grid(layers: manyLayers, playbackFrameCount: 48));

    final addLayer = find.byKey(const ValueKey<String>('legend-layer'));
    final firstLayerRow = find.byKey(
      const ValueKey<String>('timeline-layer-row-layer-1'),
    );
    final firstFrameRow = find.byKey(
      const ValueKey<String>('timeline-frame-row-area-layer-1'),
    );

    final initialAddLayerTop = tester.getTopLeft(addLayer).dy;
    final initialFrameHeaderTop = timelineHeaderGlobalRect(tester, 0).top;
    final initialLayerRowTop = tester.getTopLeft(firstLayerRow).dy;
    final initialFrameRowTop = tester.getTopLeft(firstFrameRow).dy;

    // Layer-1's row must stay inside the virtualization window's overscan
    // for the position assertions below, so scroll less than two rows.
    await _dragFrameGridVertically(tester, -100);

    expect(
      tester.getTopLeft(addLayer).dy,
      moreOrLessEquals(initialAddLayerTop),
    );
    expect(
      timelineHeaderGlobalRect(tester, 0).top,
      moreOrLessEquals(initialFrameHeaderTop),
    );
    expect(tester.getTopLeft(firstLayerRow).dy, lessThan(initialLayerRowTop));
    expect(tester.getTopLeft(firstFrameRow).dy, lessThan(initialFrameRowTop));
    expect(
      (tester.getTopLeft(firstLayerRow).dy -
              tester.getTopLeft(firstFrameRow).dy)
          .abs(),
      lessThan(0.1),
    );
  });

  testWidgets(
    'a SUB-CELL frame scroll rebuilds no cells; a cell crossing re-windows '
    '(UI-R9 #12a: pixels are free, buckets re-window)',
    (tester) async {
      await tester.pumpWidget(_grid(playbackFrameCount: 48));

      ScrollPosition framePosition() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-frame-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            ),
          )
          .position;

      // Painted rows (UI-R9 #12b → UI-R15): row identity = the row's
      // CustomPaint widget instance (cells are paint, not widgets).
      Widget rowPaint() => tester.widget(
        find.byKey(const ValueKey<String>('timeline-row-cells-layer-1')),
      );

      framePosition().jumpTo(2);
      await tester.pump();

      final beforeSubCell = rowPaint();
      framePosition().jumpTo(10); // Sub-cell: 48px cells, same bucket.
      await tester.pump();
      expect(
        identical(rowPaint(), beforeSubCell),
        isTrue,
        reason: 'sub-cell pixels rebuild nothing',
      );

      framePosition().jumpTo(4 * 48.0); // Crosses cell boundaries.
      await tester.pump();
      // PRO-TIMELINE contract (UI-R15): a cell crossing rebuilds NOTHING
      // either — the painter windows itself off the live offset, so the
      // widget instance survives every scroll and only the PAINT window
      // follows the offset.
      expect(
        identical(rowPaint(), beforeSubCell),
        isTrue,
        reason: 'crossings are repaint-only now — no rebuild at all',
      );
      expect(
        timelineCellInWindow(tester, 'layer-1', 4),
        isTrue,
        reason: 'the paint window followed the offset',
      );
      expect(
        timelineCellInWindow(tester, 'layer-1', 0),
        isFalse,
        reason:
            'scrolled-out cells left the paint window (48px cells, '
            'offset 192, overscan 2)',
      );
    },
  );

  testWidgets(
    'the endless frame extent walls in-range scrolls, grows on the ruler '
    'pan OVERSHOOT, and SHRINKS back home (UI-R12 #16 contract)',
    (tester) async {
      await tester.pumpWidget(_grid(playbackFrameCount: 12));

      double railContentWidth() => tester
          .widget<TimelineHorizontalScrollbarRail>(
            find.byKey(const ValueKey<String>('timeline-horizontal-scrollbar')),
          )
          .contentWidth;

      ScrollPosition framePosition() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-frame-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            ),
          )
          .position;

      final baseWidth = railContentWidth();
      // IN-RANGE scrolling (what the scrollbar and wheel can reach) never
      // grows the axis: the built cells are the wall.
      for (var hop = 0; hop < 4; hop += 1) {
        framePosition().jumpTo(framePosition().maxScrollExtent);
        await tester.pump();
      }
      expect(
        railContentWidth(),
        baseWidth,
        reason: 'scroll cannot extend the axis (UI-R12 #16)',
      );

      // The ruler edge-pan OVERSHOOTS the built extent (the one growth
      // path) — the growth listener materializes what the view needs.
      for (var hop = 0; hop < 3; hop += 1) {
        framePosition().jumpTo(framePosition().maxScrollExtent + 200);
        await tester.pump();
      }
      final grownWidth = railContentWidth();
      expect(grownWidth, greaterThan(baseWidth));

      // Scrolling home releases the materialized tail (discrete jump =
      // immediate shrink; the hysteresis only holds sub-viewport
      // releases): past-content cells vanish once out of view.
      framePosition().jumpTo(0);
      await tester.pump();
      expect(railContentWidth(), lessThan(grownWidth));
    },
  );

  testWidgets(
    'shrinking the row content under a deep scroll re-anchors to the top '
    '(UI-R9 #9: lane collapse used to leave a stale offset inflating the '
    'leading spacer — sections rendered pushed down)',
    (tester) async {
      final manyLayers = List<Layer>.generate(
        30,
        (index) => _layer(id: 'layer-${index + 1}', name: 'Layer ${index + 1}'),
      );
      await tester.pumpWidget(
        _grid(layers: manyLayers, playbackFrameCount: 48),
      );

      final firstLayerRow = find.byKey(
        const ValueKey<String>('timeline-layer-row-layer-1'),
      );
      final initialTop = tester.getTopLeft(firstLayerRow).dy;

      // Scroll deep into the tall content...
      await _dragFrameGridVertically(tester, -900);
      expect(firstLayerRow, findsNothing, reason: 'scrolled out of window');

      // ...then the content SHRINKS (the lane-collapse shape: fewer rows
      // under an unchanged pixel offset).
      await tester.pumpWidget(
        _grid(layers: manyLayers.take(3).toList(), playbackFrameCount: 48),
      );
      await tester.pumpAndSettle();

      expect(firstLayerRow, findsOneWidget);
      expect(
        tester.getTopLeft(firstLayerRow).dy,
        moreOrLessEquals(initialTop),
        reason: 'the window re-anchors to the top, no inflated spacer',
      );
    },
  );

  testWidgets(
    'keeps layer controls and frame rows vertically aligned for many layers',
    (tester) async {
      final manyLayers = List<Layer>.generate(
        30,
        (index) => _layer(id: 'layer-${index + 1}', name: 'Layer ${index + 1}'),
      );

      await tester.pumpWidget(
        _grid(layers: manyLayers, playbackFrameCount: 48),
      );

      final layerRow = find.byKey(
        const ValueKey<String>('timeline-layer-row-layer-24'),
      );
      final frameRow = find.byKey(
        const ValueKey<String>('timeline-frame-row-area-layer-24'),
      );

      // The layer axis is virtualized: scroll until layer-24's rows enter
      // the window (rail and grid share the same slice). Driven through
      // the position rather than a gesture — the assertion is about the
      // SLICE the rail and grid agree on, and a fling would sail past it.
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey<String>('timeline-vertical-scroll-viewport'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(23 * 52.0);
      await tester.pumpAndSettle();

      expect(layerRow, findsOneWidget);
      expect(frameRow, findsOneWidget);
      expect(
        (tester.getTopLeft(layerRow).dy - tester.getTopLeft(frameRow).dy).abs(),
        lessThan(0.1),
      );

      final frameGridArea = find.byKey(
        const ValueKey<String>('timeline-frame-grid-area'),
      );
      final dragStart = tester.getTopLeft(frameGridArea) + const Offset(20, 20);

      await tester.dragFrom(dragStart, const Offset(0, -520));
      await tester.pumpAndSettle();

      expect(layerRow, findsOneWidget);
      expect(frameRow, findsOneWidget);
      expect(
        (tester.getTopLeft(layerRow).dy - tester.getTopLeft(frameRow).dy).abs(),
        lessThan(0.1),
      );
    },
  );

  testWidgets('horizontal scrolling keeps layer controls rail mounted', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(playbackFrameCount: 48));

    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-controls-rail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('legend-layer')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-layer-1')),
      findsOneWidget,
    );
  });

  testWidgets('virtualizes large frame counts with spacer geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(playbackFrameCount: 100000));

    // Painted rows AND the painted ruler (UI-R9 #12b → UI-R13 #1): both
    // are ONE CustomPaint whose window carries the virtualization facts
    // the old spacer/cell keys pinned.
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-layer-1')),
      findsOneWidget,
    );
    expect(timelineHeaderInWindow(tester, 0), isTrue);
    expect(timelineCellInWindow(tester, 'layer-1', 0), isTrue);
    expect(timelineHeaderInWindow(tester, 99999), isFalse);
    expect(timelineCellInWindow(tester, 'layer-1', 99999), isFalse);

    // UI-R15: the PAINT windows (offset-derived) stay tiny however large
    // the document — the widget bounds are the full extent by design.
    final headerWindow = timelineRulerPainter(tester).visibleHeaderWindow();
    final cellWindow = timelineRowCellsPainterFor(
      tester,
      'layer-1',
    ).visibleFrameWindow();

    expect(
      headerWindow.endIndexExclusive - headerWindow.startIndex,
      lessThan(100),
    );
    expect(cellWindow.endIndexExclusive - cellWindow.startIndex, lessThan(100));
  });

  testWidgets('horizontal scroll changes virtualized frame range', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(playbackFrameCount: 100000));

    expect(timelineHeaderInWindow(tester, 100), isFalse);
    expect(timelineCellInWindow(tester, 'layer-1', 100), isFalse);

    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-4800, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-controls-rail')),
      findsOneWidget,
    );
    expect(timelineHeaderInWindow(tester, 100), isTrue);
    expect(timelineCellInWindow(tester, 'layer-1', 100), isTrue);
    expect(timelineHeaderInWindow(tester, 0), isFalse);
  });

  testWidgets('minimum visible frame cells still extends small frame counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        playbackFrameCount: 3,
        layers: [_layer(id: 'layer-1', name: 'Layer 1')],
      ),
    );

    expect(timelineHeaderInWindow(tester, 3), isTrue);
    expect(timelineCellInWindow(tester, 'layer-1', 3), isTrue);
  });

  testWidgets(
    'work-area frame header tap selects visible outside-playback frame',
    (tester) async {
      final selectedFrameIndices = <int>[];

      await tester.pumpWidget(
        _grid(
          playbackFrameCount: 3,
          layers: [_layer(id: 'layer-1', name: 'Layer 1')],
          onSelectFrame: selectedFrameIndices.add,
        ),
      );

      await tester.tapAt(timelineHeaderGlobalRect(tester, 3).center);

      expect(selectedFrameIndices, isNotEmpty);
      expect(selectedFrameIndices.last, 3);
    },
  );

  testWidgets('renders layer kind icons before layer names', (tester) async {
    await tester.pumpWidget(
      _grid(
        layers: [
          _layer(id: 'layer-1', name: 'Layer 1'),
          _layer(id: 'layer-2', name: 'Layer 2', kind: LayerKind.storyboard),
        ],
      ),
    );

    final animationIcon = tester.widget<Icon>(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-1')),
    );
    final storyboardIcon = tester.widget<Icon>(
      find.byKey(const ValueKey<String>('timeline-layer-kind-icon-layer-2')),
    );
    expect(animationIcon.icon, Icons.filter_frames);
    expect(storyboardIcon.icon, Icons.auto_stories_outlined);
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
    expect(find.bySemanticsLabel('Storyboard layer'), findsOneWidget);
    // The kind icon lives in its OWN type button now (UI-R24 #7) — a
    // control separate from the name area.
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('timeline-layer-type-button-layer-1'),
        ),
        matching: find.byKey(
          const ValueKey<String>('timeline-layer-kind-icon-layer-1'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-layer-name-layer-1')),
        matching: find.byKey(
          const ValueKey<String>('timeline-layer-kind-icon-layer-1'),
        ),
      ),
      findsNothing,
      reason: 'the name area no longer carries the icon',
    );
    expect(find.text('Layer 1'), findsOneWidget);
    expect(find.text('Layer 2'), findsOneWidget);
  });

  testWidgets('the legend LAYER heading is plain now (R4 #3): tapping it '
      'opens nothing', (tester) async {
    await tester.pumpWidget(_grid());
    await tester.tap(
      find.byKey(const ValueKey<String>('legend-layer')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('legend-layer-add')),
      findsNothing,
    );
  });

  testWidgets('visibility button calls callback', (tester) async {
    LayerId? toggledLayerId;

    await tester.pumpWidget(
      _grid(onToggleLayerVisibility: (layerId) => toggledLayerId = layerId),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-visibility-layer-2')),
    );

    expect(toggledLayerId, const LayerId('layer-2'));
  });

  testWidgets('opacity control calls callback', (tester) async {
    LayerId? changedLayerId;
    double? changedOpacity;

    await tester.pumpWidget(
      _grid(
        onLayerOpacityChanged: (layerId, opacity) {
          changedLayerId = layerId;
          changedOpacity = opacity;
        },
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-layer-opacity-layer-1')),
      const Offset(-30, 0),
    );

    expect(changedLayerId, const LayerId('layer-1'));
    expect(changedOpacity, isNotNull);
  });

  testWidgets('renders frame headers and cells', (tester) async {
    await tester.pumpWidget(_grid());

    expect(timelineHeaderInWindow(tester, 0), isTrue);
    expect(timelineCellInWindow(tester, 'layer-1', 0), isTrue);
    expect(timelineCellInWindow(tester, 'layer-2', 0), isTrue);
  });

  testWidgets('tapping frame ruler header selects zero-based frame index', (
    tester,
  ) async {
    int? selectedFrameIndex;

    await tester.pumpWidget(
      _grid(onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex),
    );

    await tester.tapAt(timelineHeaderGlobalRect(tester, 3).center);

    expect(selectedFrameIndex, 3);
  });

  testWidgets('the resting extent IS the cut: no runway headers exist past '
      'it, however far scrolling reaches (UI-R12 #16)', (tester) async {
    // Same frame-viewport width as when the rail was 220px wide, so the
    // scroll offsets below keep exercising the same frame windows.
    await tester.binding.setSurfaceSize(const Size(944, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_grid(playbackFrameCount: 24, width: 944));

    expect(timelineHeaderInWindow(tester, 0), isTrue);

    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-520, 0),
    );
    await tester.pumpAndSettle();
    expect(
      timelineHeaderInWindow(tester, 23),
      isTrue,
      reason: 'the cut\'s last cell',
    );
    expect(
      timelineHeaderInWindow(tester, 24),
      isFalse,
      reason:
          'past-cut cells exist only while visible/materialized '
          '(UI-R12 #16) — scrolling never creates them',
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-1200, 0),
    );
    await tester.pumpAndSettle();
    expect(
      timelineHeaderInWindow(tester, 47),
      isFalse,
      reason: 'the scroll walls at the built extent',
    );
  });

  testWidgets('renders cut end boundary after playback frames', (tester) async {
    await tester.pumpWidget(_grid(playbackFrameCount: 24));

    final boundary = find.byKey(
      const ValueKey<String>('timeline-cut-end-boundary'),
    );
    final rulerBoundary = find.byKey(
      const ValueKey<String>('timeline-cut-end-boundary-ruler'),
    );
    expect(boundary, findsOneWidget);
    expect(rulerBoundary, findsOneWidget);

    final contentLeft = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('timeline-frame-scroll-content')),
        )
        .dx;
    final boundaryLeft = tester.getTopLeft(boundary).dx;
    expect(boundaryLeft - contentLeft, 24 * 48);
    expect(tester.getTopLeft(rulerBoundary).dx, boundaryLeft);
  });

  testWidgets('keeps ruler/body aligned after viewport widens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_grid(width: 500, playbackFrameCount: 12));
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-2400, 0),
    );
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(const Size(4600, 320));
    await tester.pumpWidget(_grid(width: 4600, playbackFrameCount: 12));
    await tester.pump();
    await tester.pump();

    // The endless frame axis grew a runway past the scrolled offset, so
    // widening no longer clamps the offset back — return to the origin
    // and check ruler/body alignment through the relayout.
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(2400, 0),
    );
    await tester.pumpAndSettle();

    final frameGridArea = find.byKey(
      const ValueKey<String>('timeline-frame-grid-area'),
    );

    expect(timelineHeaderInWindow(tester, 10), isTrue);
    expect(timelineCellInWindow(tester, 'layer-1', 10), isTrue);
    final cellRect = timelineCellGlobalRect(tester, 'layer-1', 10);
    expect(
      cellRect.left,
      moreOrLessEquals(timelineHeaderGlobalRect(tester, 10).left, epsilon: 1),
    );
    expect(cellRect.left, lessThan(tester.getTopRight(frameGridArea).dx));
  });

  testWidgets(
    'selected exposure outline follows body cells after viewport widens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _grid(
          width: 500,
          currentFrameIndex: 10,
          playbackFrameCount: 12,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              10 => TimelineCellExposureState.drawingStart,
              11 || 12 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-2400, 0),
      );
      await tester.pumpAndSettle();

      await tester.binding.setSurfaceSize(const Size(4600, 320));
      await tester.pumpWidget(
        _grid(
          width: 4600,
          currentFrameIndex: 10,
          playbackFrameCount: 12,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              10 => TimelineCellExposureState.drawingStart,
              11 || 12 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      // Endless axis: the scrolled offset survives the widening; scroll
      // back so the outlined cells are on screen.
      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(2400, 0),
      );
      await tester.pumpAndSettle();

      final outline = find.byKey(
        const ValueKey<String>(
          'timeline-selected-exposure-range-outline-layer-1',
        ),
      );

      expect(outline, findsOneWidget);
      expect(timelineCellInWindow(tester, 'layer-1', 10), isTrue);
      expect(timelineCellInWindow(tester, 'layer-1', 12), isTrue);
      expect(
        tester.getTopLeft(outline).dx,
        moreOrLessEquals(
          timelineCellGlobalRect(tester, 'layer-1', 10).left,
          epsilon: 1,
        ),
      );
      expect(
        tester.getTopRight(outline).dx,
        moreOrLessEquals(
          timelineCellGlobalRect(tester, 'layer-1', 12).right,
          epsilon: 1,
        ),
      );
    },
  );

  testWidgets(
    'keeps ruler and body cut boundaries aligned after horizontal scroll',
    (tester) async {
      await tester.pumpWidget(_grid(playbackFrameCount: 24));

      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-900, 0),
      );
      await tester.pumpAndSettle();

      final bodyBoundary = find.byKey(
        const ValueKey<String>('timeline-cut-end-boundary'),
      );
      final rulerBoundary = find.byKey(
        const ValueKey<String>('timeline-cut-end-boundary-ruler'),
      );
      expect(bodyBoundary, findsOneWidget);
      expect(rulerBoundary, findsOneWidget);
      expect(
        tester.getTopLeft(rulerBoundary).dx,
        moreOrLessEquals(tester.getTopLeft(bodyBoundary).dx),
      );
    },
  );

  testWidgets(
    'authored data outside playback is visible inside visible range',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          playbackFrameCount: 24,
          exposureStateForLayer: (_, frameIndex) => frameIndex == 45
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.uncovered,
          frameNameForLayer: (_, frameIndex) => frameIndex == 45 ? 'A45' : null,
        ),
      );

      const cellKey = ValueKey<String>('timeline-cell-layer-1-45');
      await _scrollFrameGridUntilKeyVisible(tester, cellKey);

      expect(timelineCellInWindow(tester, 'layer-1', 45), isTrue);
      expect(timelineCellModel(tester, 'layer-1', 45).glyph, 'A45');
    },
  );

  testWidgets(
    'authored data outside visible range is hidden until visible range includes it',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          playbackFrameCount: 5,
          exposureStateForLayer: (_, frameIndex) => frameIndex == 45
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.uncovered,
          frameNameForLayer: (_, frameIndex) => frameIndex == 45 ? 'A45' : null,
        ),
      );

      // At rest the window covers the first ~9 cells only — frame 45 sits
      // outside it (the -2400 scroll-away is gone: scrolls WALL at the
      // built extent now, UI-R12 #16, so far-off cells hide by simply not
      // being in the window).
      expect(timelineCellInWindow(tester, 'layer-1', 45), isFalse);
      expect(find.text('A45'), findsNothing);

      await tester.pumpWidget(
        _grid(
          playbackFrameCount: 24,
          exposureStateForLayer: (_, frameIndex) => frameIndex == 45
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.uncovered,
          frameNameForLayer: (_, frameIndex) => frameIndex == 45 ? 'A45' : null,
        ),
      );
      const cellKey = ValueKey<String>('timeline-cell-layer-1-45');
      await _scrollFrameGridUntilKeyVisible(tester, cellKey);

      expect(timelineCellInWindow(tester, 'layer-1', 45), isTrue);
      expect(timelineCellModel(tester, 'layer-1', 45).glyph, 'A45');
    },
  );

  testWidgets(
    'outside-playback visible cell and header taps select their real frames',
    (tester) async {
      final selectedFrameIndices = <int>[];

      await tester.pumpWidget(
        _grid(onSelectFrame: selectedFrameIndices.add, playbackFrameCount: 24),
      );

      // Past-cut cells materialize through the ruler pan's overshoot
      // (UI-R12 #16: scroll gestures wall at the built extent) — step the
      // extent out until the target cells land INSIDE the test root.
      ScrollPosition framePosition() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-frame-scroll-viewport'),
              ),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      Future<void> materializeBy(double overshoot) async {
        framePosition().jumpTo(framePosition().maxScrollExtent + overshoot);
        await tester.pumpAndSettle();
      }

      await materializeBy(200);

      expect(timelineCellInWindow(tester, 'layer-1', 24), isTrue);
      expect(timelineCellGlobalRect(tester, 'layer-1', 24), _isInsideTestRoot);
      await tapTimelineCell(tester, 'layer-1', 24);

      await materializeBy(400);
      await materializeBy(400);

      expect(timelineHeaderInWindow(tester, 40), isTrue);
      final headerRect = timelineHeaderGlobalRect(tester, 40);
      expect(headerRect, _isInsideTestRoot);
      await tester.tapAt(headerRect.center);

      expect(selectedFrameIndices, isNotEmpty);
      expect(selectedFrameIndices, contains(24));
      expect(selectedFrameIndices.last, 40);
    },
  );

  testWidgets('clicking different ruler positions selects different frames', (
    tester,
  ) async {
    final selectedFrameIndices = <int>[];

    // 372 rail (R4 #9) + classic 48px cells: the default 800px surface no
    // longer reaches frame 9's ruler slot.
    await tester.binding.setSurfaceSize(const Size(1080, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _grid(onSelectFrame: selectedFrameIndices.add, playbackFrameCount: 20),
    );

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    final scrubAreaTopLeft = tester.getTopLeft(scrubArea);

    await tester.tapAt(scrubAreaTopLeft + const Offset(12, 20));
    await tester.tapAt(scrubAreaTopLeft + const Offset(48 * 4 + 12, 20));
    await tester.tapAt(scrubAreaTopLeft + const Offset(48 * 9 + 12, 20));

    expect(selectedFrameIndices, containsAllInOrder(<int>[0, 4, 9]));
    expect(selectedFrameIndices.toSet(), containsAll(<int>{0, 4, 9}));
  });

  testWidgets('ruler tap updates stateful current frame selection', (
    tester,
  ) async {
    var currentFrameIndex = 0;

    // Wide surface: see 'clicking different ruler positions…' above.
    await tester.binding.setSurfaceSize(const Size(1080, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return _grid(
            currentFrameIndex: currentFrameIndex,
            playbackFrameCount: 20,
            onSelectFrame: (frameIndex) {
              setState(() => currentFrameIndex = frameIndex);
            },
          );
        },
      ),
    );

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    await tester.tapAt(
      tester.getTopLeft(scrubArea) + const Offset(48 * 9 + 12, 20),
    );
    await tester.pump();

    expect(currentFrameIndex, 9);
    // The current header reads by TINT only — no red-border machinery. The
    // tint is painted by the ruler's cursor OVERLAY: the static strip is
    // cursor-independent now, so a seek never re-records its labels.
    expect(timelineRulerTintedFrame(tester), 9);
  });

  testWidgets('dragging frame ruler scrub area scrubs changed frames', (
    tester,
  ) async {
    final selectedFrameIndices = <int>[];

    await tester.pumpWidget(
      _grid(onSelectFrame: selectedFrameIndices.add, playbackFrameCount: 20),
    );

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    final start = tester.getTopLeft(scrubArea) + const Offset(48 + 8, 20);
    final gesture = await tester.startGesture(start);

    await gesture.moveBy(const Offset(48 * 4, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedFrameIndices, containsAllInOrder(<int>[1, 5]));
    expect(selectedFrameIndices.last, 5);
  });

  testWidgets('frame ruler scrub respects horizontal scroll offset', (
    tester,
  ) async {
    final selectedFrameIndices = <int>[];

    await tester.pumpWidget(
      _grid(
        onSelectFrame: selectedFrameIndices.add,
        playbackFrameCount: 100000,
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-4800, 0),
    );
    await tester.pumpAndSettle();

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    await tester.tapAt(tester.getTopLeft(scrubArea) + const Offset(10, 20));

    expect(selectedFrameIndices.last, greaterThanOrEqualTo(99));
  });

  testWidgets('frame ruler scrub clamps selected frame to visible range', (
    tester,
  ) async {
    final selectedFrameIndices = <int>[];

    await tester.pumpWidget(
      _grid(onSelectFrame: selectedFrameIndices.add, playbackFrameCount: 3),
    );

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    final scrubAreaRect = tester.getRect(scrubArea);

    await tester.tapAt(scrubAreaRect.centerRight - const Offset(1, 0));

    expect(selectedFrameIndices.last, greaterThanOrEqualTo(3));
    expect(selectedFrameIndices.last, lessThan(27));
  });

  testWidgets('selecting a cell selects layer and frame', (tester) async {
    LayerId? selectedLayerId;
    int? selectedFrameIndex;

    await tester.pumpWidget(
      _grid(
        onSelectLayer: (layerId) => selectedLayerId = layerId,
        onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
      ),
    );

    await tapTimelineCell(tester, 'layer-1', 3);

    expect(selectedLayerId, const LayerId('layer-1'));
    expect(selectedFrameIndex, 3);
  });

  testWidgets('selects layer from row controls', (tester) async {
    LayerId? selectedLayerId;

    await tester.pumpWidget(
      _grid(onSelectLayer: (layerId) => selectedLayerId = layerId),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-name-layer-2')),
    );

    expect(selectedLayerId, const LayerId('layer-2'));
  });

  testWidgets('selects layer from layer row label area', (tester) async {
    LayerId? selectedLayerId;

    await tester.pumpWidget(
      _grid(onSelectLayer: (layerId) => selectedLayerId = layerId),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-name-layer-2')),
    );

    expect(selectedLayerId, const LayerId('layer-2'));
  });

  testWidgets('shows drawing marker', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(timelineCellModel(tester, 'layer-2', 2).glyph, '○');
    expect(timelineCellModel(tester, 'layer-2', 3).glyph, isNot('○'));
  });

  testWidgets('shows held exposure marker', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.held
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(
      timelineCellModel(tester, 'layer-2', 2).semanticsLabel,
      'held exposure',
    );
  });

  testWidgets('only the first cell of an empty run shows the timesheet X', (
    tester,
  ) async {
    await tester.pumpWidget(_grid());

    expect(timelineCellModel(tester, 'layer-2', 0).glyph, 'X');
    expect(timelineCellModel(tester, 'layer-2', 2).glyph, '');
  });

  testWidgets('shows inbetween mark inside a hold', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(timelineCellModel(tester, 'layer-2', 2).glyph, '●');
    expect(
      timelineCellModel(tester, 'layer-2', 2).semanticsLabel,
      'inbetween mark',
    );
  });

  testWidgets('shows inbetween mark on an empty cell', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.markUncovered
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(timelineCellModel(tester, 'layer-2', 2).glyph, '●');
    expect(
      timelineCellModel(tester, 'layer-2', 2).semanticsLabel,
      'inbetween mark',
    );
  });

  testWidgets('empty cells show no drawing markers', (tester) async {
    await tester.pumpWidget(_grid());

    expect(timelineCellModel(tester, 'layer-1', 2).glyph, isNot('○'));
    expect(timelineCellModel(tester, 'layer-1', 2).semanticsLabel, isNull);
  });

  testWidgets('playhead appears for visible current frame', (tester) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 3));

    expect(
      find.byKey(const ValueKey<String>('timeline-playhead')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-playhead-column')),
      findsOneWidget,
    );
  });

  testWidgets('playhead does not appear for non-visible current frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(currentFrameIndex: 5000, playbackFrameCount: 100000),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-playhead')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-playhead-column')),
      findsNothing,
    );
  });

  testWidgets('playhead follows horizontal scroll range', (tester) async {
    await tester.pumpWidget(
      _grid(currentFrameIndex: 100, playbackFrameCount: 100000),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-playhead')),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-4800, 0),
    );
    await tester.pumpAndSettle();

    expect(timelineHeaderInWindow(tester, 100), isTrue);
    expect(
      find.byKey(const ValueKey<String>('timeline-playhead')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-playhead-column')),
      findsOneWidget,
    );
  });

  testWidgets('playhead column keeps full frame width with one layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 3,
        layers: [_layer(id: 'layer-1', name: 'Layer 1')],
      ),
    );

    final column = find.byKey(
      const ValueKey<String>('timeline-playhead-column'),
    );

    expect(column, findsOneWidget);
    // The playhead tint spans exactly the rows' content extent (rows are
    // no longer uniformly tall once a section collapses to its slim strip).
    expect(tester.getSize(column), const Size(48, 52));

    final container = tester.widget<Container>(column);
    expect(container.color, timelinePlayheadColor.withValues(alpha: 0.18));
    expect(container.decoration, isNull);
  });

  testWidgets('playhead does not affect frame header tap', (tester) async {
    int? selectedFrameIndex;

    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 3,
        onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
      ),
    );

    await tester.tapAt(timelineHeaderGlobalRect(tester, 3).center);

    expect(selectedFrameIndex, 3);
  });

  testWidgets('playhead does not affect frame cell selection', (tester) async {
    LayerId? selectedLayerId;
    int? selectedFrameIndex;

    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 3,
        onSelectLayer: (layerId) => selectedLayerId = layerId,
        onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
      ),
    );

    await tapTimelineCell(tester, 'layer-1', 3);

    expect(selectedLayerId, const LayerId('layer-1'));
    expect(selectedFrameIndex, 3);
  });

  testWidgets('current frame header uses plain text', (tester) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 3));

    expect(
      timelineHeaderModel(tester, 3).label,
      '4',
      reason: 'the plain one-based number, no playhead glyph',
    );
  });

  testWidgets('current frame header keeps tint without red outline', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 3));

    // Selection reads by the TINT alone — there is no selected-border path
    // anywhere. The tint rides the ruler's cursor overlay.
    expect(timelineRulerTintedFrame(tester), 3);
  });

  testWidgets('named drawing start displays name and mark has priority', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? 'A1'
            : null,
      ),
    );

    expect(timelineCellModel(tester, 'layer-2', 2).glyph, 'A1');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? 'A1'
            : null,
      ),
    );

    expect(timelineCellModel(tester, 'layer-2', 2).glyph, '●');
  });

  testWidgets('marks only the active current cell as selected', (tester) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 2));

    // The selection ring lives on the cursor layer (cells are
    // cursor-independent by design) and sits exactly over the active
    // layer's current cell.
    final ring = find.byKey(const ValueKey<String>('timeline-selected-cell'));
    expect(ring, findsOneWidget);
    expect(
      tester.getTopLeft(ring),
      timelineCellGlobalRect(tester, 'layer-1', 2).topLeft,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );
    expect(timelineCellInWindow(tester, 'layer-1', 2), isTrue);
    expect(timelineCellInWindow(tester, 'layer-2', 2), isTrue);
  });

  testWidgets('selected cell preserves symbol display priority', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
      ),
    );
    expect(timelineCellModel(tester, 'layer-1', 0).glyph, '○');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.uncovered
            : TimelineCellExposureState.uncovered,
      ),
    );
    expect(timelineCellModel(tester, 'layer-1', 0).glyph, 'X');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? 'A1'
            : null,
      ),
    );
    expect(timelineCellModel(tester, 'layer-1', 0).glyph, 'A1');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? 'A1'
            : null,
      ),
    );
    expect(timelineCellModel(tester, 'layer-1', 0).glyph, '●');
  });

  testWidgets('drawing exposure cells keep divider-safe block radius rules', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (_, frameIndex) => switch (frameIndex) {
          0 => TimelineCellExposureState.drawingStart,
          1 || 2 => TimelineCellExposureState.held,
          _ => TimelineCellExposureState.uncovered,
        },
      ),
    );

    final startDecoration = _cellDecoration(tester, 'timeline-cell-layer-1-0');
    final middleDecoration = _cellDecoration(tester, 'timeline-cell-layer-1-1');
    final endDecoration = _cellDecoration(tester, 'timeline-cell-layer-1-2');

    expect(
      startDecoration.borderRadius,
      const BorderRadius.horizontal(left: Radius.circular(6)),
    );
    expect(middleDecoration.borderRadius, BorderRadius.zero);
    expect(
      endDecoration.borderRadius,
      const BorderRadius.horizontal(right: Radius.circular(6)),
    );
    expect(startDecoration.border, isA<Border>());
    expect(middleDecoration.border, isA<Border>());
    expect(endDecoration.border, isA<Border>());
  });

  testWidgets('block cells keep divider-safe radius rules', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (_, frameIndex) => switch (frameIndex) {
          4 => TimelineCellExposureState.drawingStart,
          5 || 6 => TimelineCellExposureState.held,
          _ => TimelineCellExposureState.uncovered,
        },
      ),
    );

    expect(
      _cellDecoration(tester, 'timeline-cell-layer-1-4').borderRadius,
      const BorderRadius.horizontal(left: Radius.circular(6)),
    );
    expect(
      _cellDecoration(tester, 'timeline-cell-layer-1-5').borderRadius,
      BorderRadius.zero,
    );
    expect(
      _cellDecoration(tester, 'timeline-cell-layer-1-6').borderRadius,
      const BorderRadius.horizontal(right: Radius.circular(6)),
    );
    final startBorder =
        _cellDecoration(tester, 'timeline-cell-layer-1-4').border as Border;
    expect(startBorder.top.color, startBorder.right.color);
    expect(startBorder.top.color, startBorder.bottom.color);
    expect(startBorder.top.color, startBorder.left.color);
  });

  testWidgets(
    'selecting drawingStart highlights the active drawing exposure range',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 0,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              0 => TimelineCellExposureState.drawingStart,
              1 || 2 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      _expectSelectedExposureRangeCells(tester, 'layer-1', const [0, 1, 2]);
      _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-3');
    },
  );

  testWidgets(
    'selecting heldExposure resolves back to the active drawing start range',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 2,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              0 => TimelineCellExposureState.drawingStart,
              1 || 2 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      _expectSelectedExposureRangeCells(tester, 'layer-1', const [0, 1, 2]);
    },
  );

  testWidgets('selecting a block start highlights its exposure range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 4,
        exposureStateForLayer: (layer, frameIndex) {
          if (layer.id != const LayerId('layer-1')) {
            return TimelineCellExposureState.uncovered;
          }
          return switch (frameIndex) {
            4 => TimelineCellExposureState.drawingStart,
            5 || 6 => TimelineCellExposureState.held,
            _ => TimelineCellExposureState.uncovered,
          };
        },
      ),
    );

    _expectSelectedExposureRangeCells(tester, 'layer-1', const [4, 5, 6]);
    _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-3');
  });

  testWidgets('selecting a held cell resolves back to its block range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 6,
        exposureStateForLayer: (layer, frameIndex) {
          if (layer.id != const LayerId('layer-1')) {
            return TimelineCellExposureState.uncovered;
          }
          return switch (frameIndex) {
            4 => TimelineCellExposureState.drawingStart,
            5 || 6 => TimelineCellExposureState.held,
            _ => TimelineCellExposureState.uncovered,
          };
        },
      ),
    );

    _expectSelectedExposureRangeCells(tester, 'layer-1', const [4, 5, 6]);
  });

  testWidgets('empty selected cells do not highlight an exposure range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 3,
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
      ),
    );

    _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-0');
    expect(
      find.byKey(
        const ValueKey<String>(
          'timeline-selected-exposure-range-outline-layer-1',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('inactive layers do not show selected exposure range highlight', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        currentFrameIndex: 2,
        exposureStateForLayer: (layer, frameIndex) {
          if (layer.id == const LayerId('layer-2')) {
            return switch (frameIndex) {
              1 => TimelineCellExposureState.drawingStart,
              2 || 3 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          }
          return TimelineCellExposureState.uncovered;
        },
      ),
    );

    _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-2-1');
    _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-2-2');
    _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-2-3');
    expect(
      find.byKey(
        const ValueKey<String>(
          'timeline-selected-exposure-range-outline-layer-2',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'outside-playback visible authored range can show selected highlight',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 45,
          playbackFrameCount: 24,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              45 => TimelineCellExposureState.drawingStart,
              46 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      await _scrollFrameGridUntilKeyVisible(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-45'),
      );

      _expectSelectedExposureRangeCells(tester, 'layer-1', const [45, 46]);
    },
  );

  testWidgets(
    'selected outline can continue beyond playback duration to visible range',
    (tester) async {
      // The retired safety tail (UI-R10 #23) means past-the-cut cells come
      // from the endless axis; the fixture pins them via the minimum
      // visible cells instead.
      const metrics = TimelineGridMetrics(
        frameCellWidth: 48,
        layerRowHeight: 52,
        minimumVisibleFrameCells: 48,
      );
      final frameRange = TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: 24,
        minimumVisibleFrameCells: metrics.minimumVisibleFrameCells,
      );
      final frameContentWidth =
          frameRange.visibleFrameCount * metrics.frameCellWidth;
      final testWidth = frameContentWidth + 600;

      await tester.binding.setSurfaceSize(Size(testWidth, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _grid(
          width: testWidth,
          metrics: metrics,
          currentFrameIndex: 26,
          playbackFrameCount: 24,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              26 => TimelineCellExposureState.drawingStart,
              >= 27 && <= 47 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      _expectSelectedExposureRangeOutline(tester, 'layer-1', [
        for (var frameIndex = 26; frameIndex <= 47; frameIndex += 1) frameIndex,
      ]);
    },
  );

  testWidgets(
    'selected held outline uses displayed range rather than selected frame fallback',
    (tester) async {
      const metrics = TimelineGridMetrics(
        frameCellWidth: 48,
        layerRowHeight: 52,
        minimumVisibleFrameCells: 48,
      );
      final frameRange = TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: 24,
        minimumVisibleFrameCells: metrics.minimumVisibleFrameCells,
      );
      final frameContentWidth =
          frameRange.visibleFrameCount * metrics.frameCellWidth;
      final testWidth = frameContentWidth + 600;

      await tester.binding.setSurfaceSize(Size(testWidth, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _grid(
          width: testWidth,
          metrics: metrics,
          currentFrameIndex: 26,
          playbackFrameCount: 24,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              2 => TimelineCellExposureState.drawingStart,
              >= 3 && <= 47 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      _expectSelectedExposureRangeOutline(tester, 'layer-1', [
        for (var frameIndex = 2; frameIndex <= 47; frameIndex += 1) frameIndex,
      ]);
    },
  );

  testWidgets(
    'selected drawing exposure outline survives horizontal virtualization',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 6,
          playbackFrameCount: 100,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              6 => TimelineCellExposureState.drawingStart,
              >= 7 && <= 20 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-960, 0),
      );
      await tester.pumpAndSettle();

      expect(timelineCellInWindow(tester, 'layer-1', 6), isFalse);
      // UI-R15: the outline clamps to the OFFSET-derived paint window
      // (the cursor layer follows the viewport by itself) — read the
      // window off the painter probe instead of pinning bucket numbers.
      final window = timelineRowCellsPainterFor(
        tester,
        'layer-1',
      ).visibleFrameWindow();
      _expectSelectedExposureRangeOutline(tester, 'layer-1', [
        for (
          var frame = math.max(6, window.startIndex);
          frame <= math.min(20, window.endIndexExclusive - 1);
          frame += 1
        )
          frame,
      ]);
    },
  );

  testWidgets(
    'selected held exposure outlines survive horizontal virtualization',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 16,
          playbackFrameCount: 100,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              12 => TimelineCellExposureState.drawingStart,
              >= 13 && <= 24 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-1200, 0),
      );
      await tester.pumpAndSettle();

      expect(timelineCellInWindow(tester, 'layer-1', 16), isFalse);
      // UI-R15: the outline clamps to the offset-derived paint window.
      final window = timelineRowCellsPainterFor(
        tester,
        'layer-1',
      ).visibleFrameWindow();
      List<int> clamped() => [
        for (
          var frame = math.max(12, window.startIndex);
          frame <= math.min(24, window.endIndexExclusive - 1);
          frame += 1
        )
          frame,
      ];
      _expectSelectedExposureRangeOutline(tester, 'layer-1', clamped());

      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 16,
          playbackFrameCount: 100,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              12 => TimelineCellExposureState.drawingStart,
              >= 13 && <= 24 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      await tester.pump();

      expect(timelineCellInWindow(tester, 'layer-1', 16), isFalse);
      _expectSelectedExposureRangeOutline(tester, 'layer-1', clamped());
    },
  );

  testWidgets(
    'selected exposure outline is hidden when range has no visible intersection',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 6,
          playbackFrameCount: 100,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              6 => TimelineCellExposureState.drawingStart,
              >= 7 && <= 10 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-1440, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>(
            'timeline-selected-exposure-range-outline-layer-1',
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('authored outside-playback selected range remains outlined', (
    tester,
  ) async {
    // Same frame-viewport width as when the rail was 220px wide, so cells
    // 28-32 stay materialized together once 28 scrolls into view.
    await tester.binding.setSurfaceSize(const Size(944, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _grid(
        width: 944,
        currentFrameIndex: 28,
        playbackFrameCount: 24,
        exposureStateForLayer: (layer, frameIndex) {
          if (layer.id != const LayerId('layer-1')) {
            return TimelineCellExposureState.uncovered;
          }
          return switch (frameIndex) {
            28 => TimelineCellExposureState.drawingStart,
            >= 29 && <= 32 => TimelineCellExposureState.held,
            _ => TimelineCellExposureState.uncovered,
          };
        },
      ),
    );

    await _scrollFrameGridUntilKeyVisible(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-28'),
    );

    _expectSelectedExposureRangeOutline(tester, 'layer-1', const [
      28,
      29,
      30,
      31,
      32,
    ]);
  });

  testWidgets('body frame content width stays aligned with ruler width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _grid(
        width: 1600,
        playbackFrameCount: 12,
        currentFrameIndex: 2,
        exposureStateForLayer: (layer, frameIndex) {
          if (layer.id != const LayerId('layer-1')) {
            return TimelineCellExposureState.uncovered;
          }
          return switch (frameIndex) {
            2 => TimelineCellExposureState.drawingStart,
            3 || 4 => TimelineCellExposureState.held,
            _ => TimelineCellExposureState.uncovered,
          };
        },
      ),
    );

    final expectedFrameRange = TimelineFrameRange.fromPlaybackDuration(
      playbackFrameCount: 12,
      minimumVisibleFrameCells: _testMetrics.minimumVisibleFrameCells,
    );

    // UI-R12 #16: the viewport papers itself — with the 1600px surface
    // wider than the base cells, the rendered extent is the FILL count.
    final fillFrames = endlessViewportFillFrames(
      viewportExtent:
          1600 -
          _testMetrics.layerControlsWidth -
          _testMetrics.verticalScrollbarWidth,
      frameCellExtent: _testMetrics.frameCellWidth,
    );
    final expectedContentWidth =
        math.max(expectedFrameRange.visibleFrameCount, fillFrames) *
        _testMetrics.frameCellWidth;
    final content = find.byKey(
      const ValueKey<String>('timeline-frame-scroll-content'),
    );

    expect(tester.getSize(content).width, closeTo(expectedContentWidth, 1.0));
    expect(
      timelineCellGlobalRect(tester, 'layer-1', 0).left,
      closeTo(timelineHeaderGlobalRect(tester, 0).left, 1.0),
    );
    _expectSelectedExposureRangeOutline(tester, 'layer-1', const [2, 3, 4]);
  });

  testWidgets(
    'selecting frame 10 drawingStart does not highlight previous drawing block',
    (tester) async {
      // Wide surface: frames 10..11 must render inside the virtualization
      // window next to the 372 rail (R4 #9).
      await tester.binding.setSurfaceSize(const Size(1080, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _grid(
          currentFrameIndex: 10,
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              6 => TimelineCellExposureState.drawingStart,
              7 || 8 || 9 => TimelineCellExposureState.held,
              10 => TimelineCellExposureState.drawingStart,
              11 => TimelineCellExposureState.held,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-6');
      _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-7');
      _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-8');
      _expectNoSelectedExposureRangeBorder(tester, 'timeline-cell-layer-1-9');
      _expectSelectedExposureRangeCells(tester, 'layer-1', const [10, 11]);
    },
  );

  testWidgets(
    'previous block end before a new drawingStart gets right radius',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          exposureStateForLayer: (layer, frameIndex) {
            if (layer.id != const LayerId('layer-1')) {
              return TimelineCellExposureState.uncovered;
            }
            return switch (frameIndex) {
              6 => TimelineCellExposureState.drawingStart,
              7 || 8 || 9 => TimelineCellExposureState.held,
              10 => TimelineCellExposureState.drawingStart,
              _ => TimelineCellExposureState.uncovered,
            };
          },
        ),
      );

      expect(
        _cellDecoration(tester, 'timeline-cell-layer-1-9').borderRadius,
        const BorderRadius.horizontal(right: Radius.circular(6)),
      );
      expect(
        _cellDecoration(tester, 'timeline-cell-layer-1-10').borderRadius,
        const BorderRadius.all(Radius.circular(6)),
      );
    },
  );

  testWidgets(
    'visible authored data outside playback still renders as a block',
    (tester) async {
      await tester.pumpWidget(
        _grid(
          playbackFrameCount: 24,
          exposureStateForLayer: (_, frameIndex) => switch (frameIndex) {
            45 => TimelineCellExposureState.drawingStart,
            46 => TimelineCellExposureState.held,
            _ => TimelineCellExposureState.uncovered,
          },
        ),
      );

      await _scrollFrameGridUntilKeyVisible(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-45'),
      );

      expect(
        _cellDecoration(tester, 'timeline-cell-layer-1-45').borderRadius,
        const BorderRadius.horizontal(left: Radius.circular(6)),
      );
      expect(
        _cellDecoration(tester, 'timeline-cell-layer-1-46').borderRadius,
        const BorderRadius.horizontal(right: Radius.circular(6)),
      );
    },
  );

  testWidgets('the ACTIVE-row wash is a row underlay, not cell paint '
      '(UI-R21 #2): exactly the active row carries it', (tester) async {
    await tester.pumpWidget(_grid());
    bool rowHasWash(String layerId) {
      final context = tester.element(find.byType(LayerTimelineGrid));
      final wash = timelineActiveRowWashColor(Theme.of(context).colorScheme);
      return tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byKey(
                ValueKey<String>('timeline-frame-row-area-$layerId'),
              ),
              matching: find.byType(ColoredBox),
            ),
          )
          .any((box) => box.color == wash);
    }

    // _grid pins layer-1 active.
    expect(rowHasWash('layer-1'), isTrue);
    expect(rowHasWash('layer-2'), isFalse);
  });

  test('cell style keeps covered cells paper-white; empty cells paint '
      'NOTHING (the row underlay owns the paper, UI-R21 #2)', () {
    const colorScheme = ColorScheme.light();

    final drawingStart = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.drawingStart,
      selected: false,
    );
    final heldDrawing = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.held,
      selected: false,
    );
    final markHeld = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.markHeld,
      selected: false,
    );
    final uncovered = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.uncovered,
      selected: false,
    );
    final selectedDrawing = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.held,
      selected: true,
    );

    expect(heldDrawing.background, timelineDrawingHeldColor);
    expect(drawingStart.background, timelineDrawingStartColor);
    expect(drawingStart.background, heldDrawing.background);
    // UI-R20 #7: the block head's dark silhouette is GONE — the start
    // seam sits on the same faint grid ink as the held seams.
    expect(drawingStart.border, heldDrawing.border);
    expect(markHeld.background, heldDrawing.background);
    // UI-R21 #2: empties are TRANSPARENT — the substrate carries no
    // per-row state, so switching the active layer re-rasters nothing.
    expect(uncovered.background, Colors.transparent);
    expect(uncovered.border, Colors.transparent);
    expect(selectedDrawing.border, timelineSelectedFrameBorderColor);
    expect(selectedDrawing.background, isNot(heldDrawing.background));
  });
}

BoxDecoration _cellDecoration(WidgetTester tester, String key) {
  // Drawing-row cells are PAINTED now (UI-R9 #12b): the decoration reads
  // resolve through the painter probe instead of a widget tree.
  final cell = parseTimelineCellKey(key);
  return timelineCellDecoration(tester, cell.layerId, cell.frameIndex);
}

void _expectSelectedExposureRangeCells(
  WidgetTester tester,
  String layerId,
  List<int> frameIndices,
) {
  _expectSelectedExposureRangeOutline(tester, layerId, frameIndices);

  for (final frameIndex in frameIndices) {
    final key = 'timeline-cell-$layerId-$frameIndex';
    final decoration = _cellDecoration(tester, key);
    final border = decoration.border! as Border;

    expect(border.top.width, 1.0);
    expect(border.right.width, 1.0);
    expect(border.bottom.width, 1.0);
    expect(border.left.width, 1.0);
  }
}

void _expectNoSelectedExposureRangeBorder(WidgetTester tester, String key) {
  final decoration = _cellDecoration(tester, key);
  final border = decoration.border! as Border;

  expect(border.top.width, 1.0);
  expect(border.right.width, 1.0);
  expect(border.bottom.width, 1.0);
  expect(border.left.width, 1.0);
}

void _expectSelectedExposureRangeOutline(
  WidgetTester tester,
  String layerId,
  List<int> frameIndices,
) {
  final outlineFinder = find.byKey(
    ValueKey<String>('timeline-selected-exposure-range-outline-$layerId'),
  );
  expect(outlineFinder, findsOneWidget);

  final positioned = tester.widget<Positioned>(outlineFinder);
  final expectedWidth = frameIndices.length * _testMetrics.frameCellWidth;
  expect(positioned.width, expectedWidth);

  final firstCellRect = timelineCellGlobalRect(
    tester,
    layerId,
    frameIndices.first,
  );
  final outlineRect = tester.getRect(outlineFinder);
  expect(outlineRect.left, closeTo(firstCellRect.left, 1.0));
  expect(outlineRect.width, closeTo(expectedWidth, 1.0));

  final decoratedBox = tester.widget<DecoratedBox>(
    find.descendant(of: outlineFinder, matching: find.byType(DecoratedBox)),
  );
  final decoration = decoratedBox.decoration as BoxDecoration;
  final border = decoration.border! as Border;
  expect(decoration.color, Colors.transparent);
  expect(border.top.color, timelineSelectedFrameBorderColor);
  expect(border.top.width, 2);
  expect(decoration.borderRadius, const BorderRadius.all(Radius.circular(6)));
  expect(
    find.descendant(of: outlineFinder, matching: find.byType(CustomPaint)),
    findsNothing,
  );
}

Widget _grid({
  int currentFrameIndex = 0,
  int playbackFrameCount = 12,
  double width = 900,
  TimelineGridMetrics metrics = _testMetrics,
  LayerRailExtent? railExtent,
  List<Layer>? layers,
  TimelineCellExposureState Function(Layer layer, int frameIndex)?
  exposureStateForLayer,
  ValueChanged<LayerId>? onSelectLayer,
  ValueChanged<int>? onSelectFrame,
  VoidCallback? onAddLayer,
  ValueChanged<LayerId>? onToggleLayerVisibility,
  void Function(LayerId layerId, double opacity)? onLayerOpacityChanged,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: 260,
        child: LayerTimelineGrid(
          layers: layers ?? _layers,
          activeLayerId: const LayerId('layer-1'),
          frameCursor: ValueNotifier<int>(currentFrameIndex),
          // Classic geometry: this file's pixel oracles (taps, scroll
          // offsets, virtualization windows) assume 48×52 cells; the slim
          // default is pinned in timeline_grid_metrics_test.
          metrics: metrics,
          railExtent: railExtent,
          playbackFrameCount: playbackFrameCount,
          exposureStateForLayer:
              exposureStateForLayer ??
              (_, _) => TimelineCellExposureState.uncovered,
          frameNameForLayer: frameNameForLayer,
          onSelectLayer: onSelectLayer ?? (_) {},
          onSelectFrame: onSelectFrame ?? (_) {},
          onAddLayer: onAddLayer ?? () {},
          onToggleLayerVisibility: onToggleLayerVisibility ?? (_) {},
          onLayerOpacityChanged: onLayerOpacityChanged ?? (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
        ),
      ),
    ),
  );
}

final _layers = [
  _layer(id: 'layer-1', name: 'Layer 1'),
  _layer(id: 'layer-2', name: 'Layer 2', opacity: 0.5),
];

Layer _layer({
  required String id,
  required String name,
  double opacity = 1,
  LayerKind kind = LayerKind.animation,
}) {
  final layerNumber = id.split('-').last;

  return Layer(
    id: LayerId(id),
    name: name,
    kind: kind,
    opacity: opacity,
    frames: [
      Frame(id: FrameId('frame-$layerNumber'), duration: 1, strokes: const []),
    ],
  );
}
