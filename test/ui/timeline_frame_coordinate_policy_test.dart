import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart';

void main() {
  group('frameIndexFromLocalX', () {
    test('local x converts to frame index without scroll', () {
      expect(
        frameIndexFromLocalX(
          localX: 0,
          horizontalScrollOffset: 0,
          frameCellWidth: 48,
          visibleFrameCount: 10,
        ),
        0,
      );
      expect(
        frameIndexFromLocalX(
          localX: 47.9,
          horizontalScrollOffset: 0,
          frameCellWidth: 48,
          visibleFrameCount: 10,
        ),
        0,
      );
      expect(
        frameIndexFromLocalX(
          localX: 48,
          horizontalScrollOffset: 0,
          frameCellWidth: 48,
          visibleFrameCount: 10,
        ),
        1,
      );
    });

    test('local x converts to frame index with horizontal scroll', () {
      expect(
        frameIndexFromLocalX(
          localX: 0,
          horizontalScrollOffset: 96,
          frameCellWidth: 48,
          visibleFrameCount: 10,
        ),
        2,
      );
    });

    test('frame index clamps below zero', () {
      expect(
        frameIndexFromLocalX(
          localX: -100,
          horizontalScrollOffset: 0,
          frameCellWidth: 48,
          visibleFrameCount: 10,
        ),
        0,
      );
    });

    test('frame index clamps above visible count', () {
      expect(
        frameIndexFromLocalX(
          localX: 10000,
          horizontalScrollOffset: 0,
          frameCellWidth: 48,
          visibleFrameCount: 10,
        ),
        9,
      );
    });

    test('empty visible frame count returns null', () {
      expect(
        frameIndexFromLocalX(
          localX: 0,
          horizontalScrollOffset: 0,
          frameCellWidth: 48,
          visibleFrameCount: 0,
        ),
        isNull,
      );
    });

    test('invalid cell width returns null', () {
      expect(
        frameIndexFromLocalX(
          localX: 0,
          horizontalScrollOffset: 0,
          frameCellWidth: 0,
          visibleFrameCount: 10,
        ),
        isNull,
      );
    });
  });

  group('clampFrameIndex', () {
    test('clamps below zero', () {
      expect(clampFrameIndex(frameIndex: -1, visibleFrameCount: 10), 0);
    });

    test('clamps above visible count', () {
      expect(clampFrameIndex(frameIndex: 99, visibleFrameCount: 10), 9);
    });

    test('returns null for empty visible frame count', () {
      expect(clampFrameIndex(frameIndex: 0, visibleFrameCount: 0), isNull);
    });
  });

  group('frameContentX', () {
    test('converts frame index to content x position', () {
      expect(frameContentX(frameIndex: 0, frameCellWidth: 48), 0);
      expect(frameContentX(frameIndex: 5, frameCellWidth: 48), 240);
    });
  });

  group('frameVisibleX', () {
    test('converts frame index to visible x position', () {
      expect(
        frameVisibleX(
          frameIndex: 20,
          frameStartIndex: 18,
          frameCellWidth: 48,
          leadingFrameSpacerWidth: 96,
        ),
        192,
      );
    });
  });

  group('frameRangeVisibleWidth', () {
    test('converts positive frame range to visible width', () {
      expect(
        frameRangeVisibleWidth(
          startFrameIndex: 10,
          endFrameIndexExclusive: 13,
          frameCellWidth: 48,
        ),
        144,
      );
    });

    test('returns zero for empty or inverted frame ranges', () {
      expect(
        frameRangeVisibleWidth(
          startFrameIndex: 10,
          endFrameIndexExclusive: 10,
          frameCellWidth: 48,
        ),
        0,
      );
      expect(
        frameRangeVisibleWidth(
          startFrameIndex: 13,
          endFrameIndexExclusive: 10,
          frameCellWidth: 48,
        ),
        0,
      );
    });
  });
}
