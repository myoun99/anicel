import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_visible_range.dart';

void main() {
  group('calculateVisibleIndexRange', () {
    test('empty itemCount returns empty range', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: 0,
        viewportExtent: 100,
        itemExtent: 10,
        itemCount: 0,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 0),
      );
      expect(range.isEmpty, isTrue);
      expect(range.count, 0);
    });

    test('initial viewport returns expected visible range with overscan', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: 0,
        viewportExtent: 100,
        itemExtent: 10,
        itemCount: 50,
        overscanBefore: 2,
        overscanAfter: 2,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 12),
      );
      expect(range.contains(0), isTrue);
      expect(range.contains(11), isTrue);
      expect(range.contains(12), isFalse);
    });

    test('horizontal scroll offset shifts visible frame range', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: 55,
        viewportExtent: 100,
        itemExtent: 10,
        itemCount: 50,
        overscanBefore: 1,
        overscanAfter: 2,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 4, endIndexExclusive: 18),
      );
    });

    test('overscan clamps to zero at start', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: 5,
        viewportExtent: 20,
        itemExtent: 10,
        itemCount: 10,
        overscanBefore: 10,
        overscanAfter: 0,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 3),
      );
    });

    test('overscan clamps to itemCount at end', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: 80,
        viewportExtent: 30,
        itemExtent: 10,
        itemCount: 10,
        overscanBefore: 0,
        overscanAfter: 10,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 8, endIndexExclusive: 10),
      );
    });

    test('negative scrollOffset is handled safely', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: -100,
        viewportExtent: 30,
        itemExtent: 10,
        itemCount: 10,
        overscanBefore: 1,
        overscanAfter: 1,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 0, endIndexExclusive: 4),
      );
    });

    test('itemExtent <= 0 is rejected clearly', () {
      expect(
        () => calculateVisibleIndexRange(
          scrollOffset: 0,
          viewportExtent: 100,
          itemExtent: 0,
          itemCount: 10,
        ),
        throwsArgumentError,
      );
    });

    test('very large frameCount works without generating all frames', () {
      final range = calculateVisibleIndexRange(
        scrollOffset: 500000,
        viewportExtent: 1000,
        itemExtent: 10,
        itemCount: 100000,
        overscanBefore: 3,
        overscanAfter: 4,
      );

      expect(
        range,
        const TimelineVisibleRange(startIndex: 49997, endIndexExclusive: 50104),
      );
      expect(range.count, 107);
    });
  });

  group('calculateTimelineVisibleRanges', () {
    test('two-axis calculation returns both frame and layer ranges', () {
      final ranges = calculateTimelineVisibleRanges(
        horizontalScrollOffset: 120,
        verticalScrollOffset: 48,
        viewportWidth: 240,
        viewportHeight: 72,
        frameCellWidth: 24,
        layerRowHeight: 24,
        frameCount: 100,
        layerCount: 20,
        frameOverscanBefore: 2,
        frameOverscanAfter: 3,
        layerOverscanBefore: 1,
        layerOverscanAfter: 1,
      );

      expect(
        ranges.frames,
        const TimelineVisibleRange(startIndex: 3, endIndexExclusive: 18),
      );
      expect(
        ranges.layers,
        const TimelineVisibleRange(startIndex: 1, endIndexExclusive: 6),
      );
    });
  });
}
