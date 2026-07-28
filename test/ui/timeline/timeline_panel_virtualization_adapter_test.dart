import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_panel_virtualization_adapter.dart';
import 'package:anicel/src/ui/timeline/timeline_visible_range.dart';

void main() {
  group('calculateLayerTimelineGridVirtualizationPlan', () {
    test(
      'uses minimumVisibleFrameCells when visibleFrameCount is smaller than 24',
      () {
        final plan = calculateLayerTimelineGridVirtualizationPlan(
          horizontalScrollOffset: 0,
          verticalScrollOffset: 0,
          viewportWidth: 96,
          viewportHeight: 104,
          visibleFrameCount: 5,
          layerCount: 3,
          // Explicit classic geometry: the oracle numbers below assume it
          // (the slim default is pinned in timeline_grid_metrics_test).
          metrics: const TimelineGridMetrics(
            frameCellWidth: 48,
            layerRowHeight: 52,
          ),
          frameOverscanBefore: 0,
          frameOverscanAfter: 0,
          layerOverscanBefore: 0,
          layerOverscanAfter: 0,
        );

        expect(plan.totalFrameContentWidth, 24 * 48);
        expect(
          plan.frameRange,
          const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 2),
        );
        expect(plan.trailingFrameSpacerWidth, 22 * 48);
      },
    );

    test(
      'uses actual visibleFrameCount when visibleFrameCount is larger than 24',
      () {
        final plan = calculateLayerTimelineGridVirtualizationPlan(
          horizontalScrollOffset: 0,
          verticalScrollOffset: 0,
          viewportWidth: 96,
          viewportHeight: 104,
          visibleFrameCount: 40,
          layerCount: 3,
          metrics: const TimelineGridMetrics(
            frameCellWidth: 48,
            layerRowHeight: 52,
          ),
          frameOverscanBefore: 0,
          frameOverscanAfter: 0,
          layerOverscanBefore: 0,
          layerOverscanAfter: 0,
        );

        expect(plan.totalFrameContentWidth, 40 * 48);
        expect(plan.trailingFrameSpacerWidth, 38 * 48);
      },
    );

    test('uses metrics.frameCellWidth for total width and spacers', () {
      final plan = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 120,
        verticalScrollOffset: 0,
        viewportWidth: 90,
        viewportHeight: 60,
        visibleFrameCount: 30,
        layerCount: 2,
        metrics: const TimelineGridMetrics(frameCellWidth: 30),
        frameOverscanBefore: 1,
        frameOverscanAfter: 1,
        layerOverscanBefore: 0,
        layerOverscanAfter: 0,
      );

      expect(plan.frameRange.startIndex, 3);
      expect(plan.totalFrameContentWidth, 900);
      expect(plan.leadingFrameSpacerWidth, 90);
      expect(plan.visibleFrameContentWidth, 150);
      expect(plan.trailingFrameSpacerWidth, 660);
    });

    test('uses metrics.layerRowHeight for layer heights', () {
      final plan = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 80,
        viewportWidth: 96,
        viewportHeight: 80,
        visibleFrameCount: 30,
        layerCount: 10,
        metrics: const TimelineGridMetrics(layerRowHeight: 40),
        frameOverscanBefore: 0,
        frameOverscanAfter: 0,
        layerOverscanBefore: 1,
        layerOverscanAfter: 1,
      );

      expect(
        plan.layerRange,
        const TimelineVisibleRange(startIndex: 1, endIndexExclusive: 5),
      );
      expect(plan.totalLayerContentHeight, 400);
      expect(plan.leadingLayerSpacerHeight, 40);
      expect(plan.visibleLayerContentHeight, 160);
      expect(plan.trailingLayerSpacerHeight, 200);
    });

    test('horizontal scroll offset affects frame spacer', () {
      final initial = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 0,
        viewportWidth: 96,
        viewportHeight: 104,
        visibleFrameCount: 50,
        layerCount: 3,
        frameOverscanBefore: 0,
        frameOverscanAfter: 0,
      );
      final scrolled = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 240,
        verticalScrollOffset: 0,
        viewportWidth: 96,
        viewportHeight: 104,
        visibleFrameCount: 50,
        layerCount: 3,
        frameOverscanBefore: 0,
        frameOverscanAfter: 0,
      );

      expect(initial.leadingFrameSpacerWidth, 0);
      expect(scrolled.leadingFrameSpacerWidth, 240);
    });

    test('vertical scroll offset affects layer spacer', () {
      final initial = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 0,
        viewportWidth: 96,
        viewportHeight: 104,
        visibleFrameCount: 50,
        layerCount: 20,
        layerOverscanBefore: 0,
        layerOverscanAfter: 0,
      );
      final scrolled = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 0,
        // 156 = 3 classic 52px rows — an exact row boundary.
        verticalScrollOffset: 156,
        viewportWidth: 96,
        viewportHeight: 104,
        visibleFrameCount: 50,
        layerCount: 20,
        metrics: const TimelineGridMetrics(
          frameCellWidth: 48,
          layerRowHeight: 52,
        ),
        layerOverscanBefore: 0,
        layerOverscanAfter: 0,
      );

      expect(initial.leadingLayerSpacerHeight, 0);
      expect(scrolled.leadingLayerSpacerHeight, 156);
    });

    test('adapter source does not import Flutter widgets', () {
      final source = File(
        'lib/src/ui/timeline/timeline_panel_virtualization_adapter.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('material.dart')));
      expect(source, isNot(contains('widgets.dart')));
    });

    test('100000 visibleFrameCount works by calculation only', () {
      final plan = calculateLayerTimelineGridVirtualizationPlan(
        horizontalScrollOffset: 480000,
        verticalScrollOffset: 0,
        viewportWidth: 480,
        viewportHeight: 104,
        visibleFrameCount: 100000,
        layerCount: 4,
        metrics: const TimelineGridMetrics(
          frameCellWidth: 48,
          layerRowHeight: 52,
        ),
        frameOverscanBefore: 2,
        frameOverscanAfter: 2,
      );

      expect(plan.totalFrameContentWidth, 4800000);
      expect(
        plan.frameRange,
        const TimelineVisibleRange(startIndex: 9998, endIndexExclusive: 10012),
      );
      expect(plan.visibleFrameContentWidth, 14 * 48);
    });
  });
}
