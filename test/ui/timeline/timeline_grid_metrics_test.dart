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

    test('frame label cadence follows the paper-timesheet stride ladder '
        'anchored at frame 1 (user rule: all → 3f → 6f → 12f → 24f…)', () {
      int cadenceAt(double width) =>
          TimelineGridMetrics(frameCellWidth: width).frameLabelEveryFrames;

      expect(cadenceAt(48), 1);
      expect(cadenceAt(24), 1);
      expect(cadenceAt(20), 1);
      expect(cadenceAt(19), 3);
      expect(cadenceAt(14), 3);
      expect(cadenceAt(8), 6);
      expect(cadenceAt(4), 12);
      expect(cadenceAt(2), 24);
      expect(cadenceAt(1), 48);
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
