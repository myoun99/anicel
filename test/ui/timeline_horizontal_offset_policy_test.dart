import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_offset_policy.dart';

void main() {
  group('resolveTimelineHorizontalOffset', () {
    test('offset remains unchanged when within bounds', () {
      final resolution = resolveTimelineHorizontalOffset(
        requestedOffset: 120,
        totalContentWidth: 1000,
        viewportWidth: 400,
      );

      expect(resolution.requestedOffset, 120);
      expect(resolution.maxOffset, 600);
      expect(resolution.effectiveOffset, 120);
      expect(resolution.needsCorrection, isFalse);
    });

    test('offset clamps to zero when negative', () {
      final resolution = resolveTimelineHorizontalOffset(
        requestedOffset: -50,
        totalContentWidth: 1000,
        viewportWidth: 400,
      );

      expect(resolution.maxOffset, 600);
      expect(resolution.effectiveOffset, 0);
      expect(resolution.needsCorrection, isTrue);
    });

    test('offset clamps to max when requested is too large', () {
      final resolution = resolveTimelineHorizontalOffset(
        requestedOffset: 900,
        totalContentWidth: 1000,
        viewportWidth: 400,
      );

      expect(resolution.maxOffset, 600);
      expect(resolution.effectiveOffset, 600);
      expect(resolution.needsCorrection, isTrue);
    });

    test('offset clamps to zero when viewport is wider than content', () {
      final resolution = resolveTimelineHorizontalOffset(
        requestedOffset: 300,
        totalContentWidth: 1000,
        viewportWidth: 2000,
      );

      expect(resolution.maxOffset, 0);
      expect(resolution.effectiveOffset, 0);
      expect(resolution.needsCorrection, isTrue);
    });

    test('zero content width always resolves to zero', () {
      final resolution = resolveTimelineHorizontalOffset(
        requestedOffset: 100,
        totalContentWidth: 0,
        viewportWidth: 400,
      );

      expect(resolution.maxOffset, 0);
      expect(resolution.effectiveOffset, 0);
    });

    test('negative content or viewport values are normalized safely', () {
      final negativeContent = resolveTimelineHorizontalOffset(
        requestedOffset: 100,
        totalContentWidth: -1000,
        viewportWidth: 400,
      );
      final negativeViewport = resolveTimelineHorizontalOffset(
        requestedOffset: 100,
        totalContentWidth: 1000,
        viewportWidth: -400,
      );

      expect(negativeContent.maxOffset, 0);
      expect(negativeContent.effectiveOffset, 0);
      expect(negativeViewport.maxOffset, 1000);
      expect(negativeViewport.effectiveOffset, 100);
    });

    test('fractional offsets are preserved when valid', () {
      final resolution = resolveTimelineHorizontalOffset(
        requestedOffset: 12.5,
        totalContentWidth: 1000,
        viewportWidth: 400,
      );

      expect(resolution.maxOffset, 600);
      expect(resolution.effectiveOffset, 12.5);
      expect(resolution.needsCorrection, isFalse);
    });
  });
}
