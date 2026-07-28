import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_virtualization_plan.dart';
import 'package:anicel/src/ui/timeline/timeline_visible_range.dart';

void main() {
  group('calculateTimelineVirtualizationPlan', () {
    test('empty frameCount produces zero frame dimensions', () {
      final plan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 0,
        layerCount: 5,
      );

      expect(
        plan.frameRange,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 0),
      );
      expect(plan.totalFrameContentWidth, 0);
      expect(plan.leadingFrameSpacerWidth, 0);
      expect(plan.trailingFrameSpacerWidth, 0);
      expect(plan.visibleFrameContentWidth, 0);
    });

    test('empty layerCount produces zero layer dimensions', () {
      final plan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 10,
        layerCount: 0,
      );

      expect(
        plan.layerRange,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 0),
      );
      expect(plan.totalLayerContentHeight, 0);
      expect(plan.leadingLayerSpacerHeight, 0);
      expect(plan.trailingLayerSpacerHeight, 0);
      expect(plan.visibleLayerContentHeight, 0);
    });

    test('initial viewport calculates leading and trailing frame spacers', () {
      final plan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 50,
        layerCount: 10,
        frameOverscanBefore: 2,
        frameOverscanAfter: 2,
      );

      expect(
        plan.frameRange,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 12),
      );
      expect(plan.totalFrameContentWidth, 500);
      expect(plan.leadingFrameSpacerWidth, 0);
      expect(plan.visibleFrameContentWidth, 120);
      expect(plan.trailingFrameSpacerWidth, 380);
    });

    test('horizontal scroll offset changes leading frame spacer', () {
      final plan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 55,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 50,
        layerCount: 10,
        frameOverscanBefore: 1,
        frameOverscanAfter: 2,
      );

      expect(
        plan.frameRange,
        const TimelineVisibleRange(startIndex: 4, endIndexExclusive: 18),
      );
      expect(plan.leadingFrameSpacerWidth, 40);
      expect(plan.visibleFrameContentWidth, 140);
      expect(plan.trailingFrameSpacerWidth, 320);
    });

    test('vertical scroll offset changes leading layer spacer', () {
      final plan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 0,
        verticalScrollOffset: 72,
        viewportWidth: 100,
        viewportHeight: 72,
        frameCellWidth: 10,
        layerRowHeight: 24,
        frameCount: 50,
        layerCount: 20,
        layerOverscanBefore: 1,
        layerOverscanAfter: 1,
      );

      expect(
        plan.layerRange,
        const TimelineVisibleRange(startIndex: 2, endIndexExclusive: 7),
      );
      expect(plan.leadingLayerSpacerHeight, 48);
      expect(plan.visibleLayerContentHeight, 120);
      expect(plan.trailingLayerSpacerHeight, 312);
    });

    test('overscan affects visible frame content width', () {
      final withoutOverscan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 100,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 100,
        layerCount: 10,
        frameOverscanBefore: 0,
        frameOverscanAfter: 0,
      );
      final withOverscan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 100,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 100,
        layerCount: 10,
        frameOverscanBefore: 2,
        frameOverscanAfter: 3,
      );

      expect(withoutOverscan.visibleFrameContentWidth, 100);
      expect(withOverscan.visibleFrameContentWidth, 150);
      expect(withOverscan.leadingFrameSpacerWidth, 80);
    });

    test('plan clamps trailing spacer at the end', () {
      final plan = calculateTimelineVirtualizationPlan(
        horizontalScrollOffset: 470,
        verticalScrollOffset: 0,
        viewportWidth: 100,
        viewportHeight: 100,
        frameCellWidth: 10,
        layerRowHeight: 20,
        frameCount: 50,
        layerCount: 10,
        frameOverscanBefore: 0,
        frameOverscanAfter: 20,
      );

      expect(
        plan.frameRange,
        const TimelineVisibleRange(startIndex: 47, endIndexExclusive: 50),
      );
      expect(plan.trailingFrameSpacerWidth, 0);
      expect(plan.visibleFrameContentWidth, 30);
    });

    test('invalid frameCellWidth throws ArgumentError', () {
      expect(
        () => calculateTimelineVirtualizationPlan(
          horizontalScrollOffset: 0,
          verticalScrollOffset: 0,
          viewportWidth: 100,
          viewportHeight: 100,
          frameCellWidth: 0,
          layerRowHeight: 20,
          frameCount: 10,
          layerCount: 10,
        ),
        throwsArgumentError,
      );
    });

    test('invalid layerRowHeight throws ArgumentError', () {
      expect(
        () => calculateTimelineVirtualizationPlan(
          horizontalScrollOffset: 0,
          verticalScrollOffset: 0,
          viewportWidth: 100,
          viewportHeight: 100,
          frameCellWidth: 10,
          layerRowHeight: 0,
          frameCount: 10,
          layerCount: 10,
        ),
        throwsArgumentError,
      );
    });

    test(
      '100000 frameCount produces correct total width and visible-only range',
      () {
        final plan = calculateTimelineVirtualizationPlan(
          horizontalScrollOffset: 500000,
          verticalScrollOffset: 0,
          viewportWidth: 1000,
          viewportHeight: 100,
          frameCellWidth: 10,
          layerRowHeight: 20,
          frameCount: 100000,
          layerCount: 10,
          frameOverscanBefore: 3,
          frameOverscanAfter: 4,
        );

        expect(plan.totalFrameContentWidth, 1000000);
        expect(
          plan.frameRange,
          const TimelineVisibleRange(
            startIndex: 49997,
            endIndexExclusive: 50104,
          ),
        );
        expect(plan.visibleFrameContentWidth, 1070);
        expect(plan.leadingFrameSpacerWidth, 499970);
        expect(plan.trailingFrameSpacerWidth, 498960);
      },
    );
  });
}
