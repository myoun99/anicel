import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

void main() {
  group('TimelineGridMetrics', () {
    test('defaults match current LayerTimelineGrid behavior', () {
      const metrics = TimelineGridMetrics.defaults;

      expect(metrics.minimumVisibleFrameCells, 24);
      // 312 → 340 → 372: the wider layer-name column (UI-R3 #8, UI-R4 #9).
      // 372 → 434 (R27 #6): the blend-mode column joined the label.
      expect(metrics.layerControlsWidth, 434);
      // 24×28 — the R-toolbar slim round (CSP/TVPaint density).
      expect(metrics.frameCellWidth, 24);
      expect(metrics.layerRowHeight, 28);
      // 14 → 16 (rail-window round): the lane stopped being a leftover
      // gap between the rail and the cells and became a real column.
      expect(metrics.verticalScrollbarWidth, 16);
    });

    test('copyWith rescales only the frame cell extent', () {
      final zoomed = TimelineGridMetrics.defaults.copyWith(frameCellWidth: 24);

      expect(zoomed.frameCellWidth, 24);
      expect(
        zoomed.layerRowHeight,
        TimelineGridMetrics.defaults.layerRowHeight,
      );
      expect(
        zoomed.layerControlsWidth,
        TimelineGridMetrics.defaults.layerControlsWidth,
      );
    });

    test('copyWith can restate the NATURAL rail extent', () {
      // For hosts whose rail costs a different width (the storyboard's
      // has no blend column). Never for the splitter: the window size is
      // a listenable precisely so it stays out of this memo key.
      final narrower = TimelineGridMetrics.defaults.copyWith(
        layerControlsWidth: 372,
      );

      expect(narrower.layerControlsWidth, 372);
      expect(
        narrower.frameCellWidth,
        TimelineGridMetrics.defaults.frameCellWidth,
      );
    });

    test('the stride ladder is the paper timesheet\'s, anchored at frame 1 '
        '(user rule: all → 3f → 6f → 12f → 24f…)', () {
      expect(timelineFrameStrideLadder, [1, 3, 6, 12, 24, 48, 96]);
    });

    // I-22: which rung stands is no longer a threshold on the cell here —
    // each mark asks the ladder for the rung that holds its own extent.
    test('a mark climbs to the densest rung whose span holds it', () {
      expect(timelineStrideHolding(3, 8), 1);
      expect(timelineStrideHolding(8, 8), 1, reason: 'a span that just holds');
      expect(timelineStrideHolding(8.5, 8), 3);
      expect(timelineStrideHolding(30, 8), 6);
      expect(timelineStrideHolding(3, 2.4), 3);
      expect(timelineStrideHolding(1000, 1), 96, reason: 'the top rung');
    });

    test('custom metrics can be created', () {
      const metrics = TimelineGridMetrics(
        minimumVisibleFrameCells: 12,
        layerControlsWidth: 180,
        frameCellWidth: 32,
        layerRowHeight: 44,
        verticalScrollbarWidth: 12,
      );

      expect(metrics.minimumVisibleFrameCells, 12);
      expect(metrics.layerControlsWidth, 180);
      expect(metrics.frameCellWidth, 32);
      expect(metrics.layerRowHeight, 44);
      expect(metrics.verticalScrollbarWidth, 12);
    });
  });
}
