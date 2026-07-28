import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/selected_exposure_display_range_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_range_resolver.dart';

void main() {
  group('resolveSelectedExposureDisplayRange', () {
    test('inactive returns no visible intersection', () {
      final displayRange = resolveSelectedExposureDisplayRange(
        active: false,
        currentFrameIndex: 10,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
        exposureStateAt: (_) => TimelineCellExposureState.drawingStart,
      );

      expect(displayRange.resolvedRange.kind, TimelineExposureRangeKind.none);
      expect(displayRange.hasVisibleIntersection, isFalse);
      expect(displayRange.visibleStartFrameIndex, 0);
      expect(displayRange.visibleEndFrameIndexExclusive, 0);
    });

    test('drawing start resolves forward through visible display range', () {
      final displayRange = _resolve(
        currentFrameIndex: 10,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
        states: {
          10: TimelineCellExposureState.drawingStart,
          for (var frameIndex = 11; frameIndex < 48; frameIndex += 1)
            frameIndex: TimelineCellExposureState.held,
        },
      );

      _expectRange(displayRange, start: 10, endExclusive: 48);
      _expectVisibleIntersection(displayRange, start: 10, endExclusive: 48);
    });

    test(
      'held exposure resolves backward and forward through visible display range',
      () {
        final displayRange = _resolve(
          currentFrameIndex: 26,
          frameStartIndex: 0,
          frameEndIndexExclusive: 48,
          states: {
            2: TimelineCellExposureState.drawingStart,
            for (var frameIndex = 3; frameIndex < 48; frameIndex += 1)
              frameIndex: TimelineCellExposureState.held,
          },
        );

        _expectRange(displayRange, start: 2, endExclusive: 48);
        _expectVisibleIntersection(displayRange, start: 2, endExclusive: 48);
      },
    );

    test('selected range may continue beyond playback duration', () {
      final displayRange = _resolve(
        currentFrameIndex: 26,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
        states: {
          2: TimelineCellExposureState.drawingStart,
          for (var frameIndex = 3; frameIndex < 48; frameIndex += 1)
            frameIndex: TimelineCellExposureState.held,
        },
      );

      _expectRange(displayRange, start: 2, endExclusive: 48);
      _expectVisibleIntersection(displayRange, start: 2, endExclusive: 48);
    });

    test('visible intersection clamps to current virtualized frame window', () {
      final displayRange = _resolve(
        currentFrameIndex: 26,
        frameStartIndex: 20,
        frameEndIndexExclusive: 36,
        states: {
          2: TimelineCellExposureState.drawingStart,
          for (var frameIndex = 3; frameIndex < 48; frameIndex += 1)
            frameIndex: TimelineCellExposureState.held,
        },
      );

      _expectRange(displayRange, start: 2, endExclusive: 36);
      _expectVisibleIntersection(displayRange, start: 20, endExclusive: 36);
    });

    test('no visible intersection when resolved range is offscreen', () {
      final displayRange = _resolve(
        currentFrameIndex: 5,
        frameStartIndex: 20,
        frameEndIndexExclusive: 36,
        states: {
          2: TimelineCellExposureState.drawingStart,
          for (var frameIndex = 3; frameIndex < 10; frameIndex += 1)
            frameIndex: TimelineCellExposureState.held,
        },
      );

      _expectRange(displayRange, start: 2, endExclusive: 10);
      expect(displayRange.hasVisibleIntersection, isFalse);
    });

    test('resolver upper bound uses display frameEndIndexExclusive', () {
      final displayRange = _resolve(
        currentFrameIndex: 26,
        frameStartIndex: 0,
        frameEndIndexExclusive: 48,
        states: {
          2: TimelineCellExposureState.drawingStart,
          for (var frameIndex = 3; frameIndex < 48; frameIndex += 1)
            frameIndex: TimelineCellExposureState.held,
        },
      );

      _expectRange(displayRange, start: 2, endExclusive: 48);
      _expectVisibleIntersection(displayRange, start: 2, endExclusive: 48);
    });
  });
}

SelectedExposureDisplayRange _resolve({
  required int currentFrameIndex,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required Map<int, TimelineCellExposureState> states,
}) {
  return resolveSelectedExposureDisplayRange(
    active: true,
    currentFrameIndex: currentFrameIndex,
    frameStartIndex: frameStartIndex,
    frameEndIndexExclusive: frameEndIndexExclusive,
    exposureStateAt: (frameIndex) =>
        states[frameIndex] ?? TimelineCellExposureState.uncovered,
  );
}

void _expectRange(
  SelectedExposureDisplayRange displayRange, {
  required int start,
  required int endExclusive,
}) {
  expect(displayRange.resolvedRange.startFrameIndex, start);
  expect(displayRange.resolvedRange.endFrameIndexExclusive, endExclusive);
  expect(displayRange.resolvedRange.isBlock, isTrue);
}

void _expectVisibleIntersection(
  SelectedExposureDisplayRange displayRange, {
  required int start,
  required int endExclusive,
}) {
  expect(displayRange.hasVisibleIntersection, isTrue);
  expect(displayRange.visibleStartFrameIndex, start);
  expect(displayRange.visibleEndFrameIndexExclusive, endExclusive);
}
