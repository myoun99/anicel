import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_range_resolver.dart';

/// The selected exposure range: the covered run containing the selected
/// frame, bounded by drawing starts on both sides (glued blocks resolve
/// separately) and by coverage boundaries.
void main() {
  // a[0,3) with a mark at 1, then X at 3-4, then b[5,7).
  TimelineCellExposureState stateAt(int frameIndex) {
    return switch (frameIndex) {
      0 => TimelineCellExposureState.drawingStart,
      1 => TimelineCellExposureState.markHeld,
      2 => TimelineCellExposureState.held,
      5 => TimelineCellExposureState.drawingStart,
      6 => TimelineCellExposureState.held,
      _ => TimelineCellExposureState.uncovered,
    };
  }

  TimelineExposureRange resolve(int selectedFrameIndex) {
    return resolveTimelineExposureRange(
      selectedFrameIndex: selectedFrameIndex,
      minFrameIndex: 0,
      maxFrameIndexExclusive: 24,
      exposureStateAt: stateAt,
    );
  }

  test('selecting a drawing start resolves its whole covered run', () {
    final range = resolve(0);

    expect(range.kind, TimelineExposureRangeKind.drawing);
    expect(range.startFrameIndex, 0);
    expect(range.endFrameIndexExclusive, 3);
    expect(range.isStartFrame, isTrue);
  });

  test('selecting a held or marked cell resolves back to the block start', () {
    expect(resolve(2).startFrameIndex, 0);
    expect(resolve(1).startFrameIndex, 0);
    expect(resolve(1).endFrameIndexExclusive, 3);
  });

  test('uncovered cells resolve no range', () {
    expect(resolve(3).isBlock, isFalse);
    expect(resolve(10).isBlock, isFalse);
  });

  test('range ends at the coverage boundary', () {
    final range = resolve(6);

    expect(range.startFrameIndex, 5);
    expect(range.endFrameIndexExclusive, 7);
    expect(range.isEndFrame, isTrue);
  });

  test('glued blocks resolve separately on both sides of the boundary', () {
    TimelineCellExposureState glued(int frameIndex) {
      return switch (frameIndex) {
        0 || 2 => TimelineCellExposureState.drawingStart,
        1 || 3 => TimelineCellExposureState.held,
        _ => TimelineCellExposureState.uncovered,
      };
    }

    final first = resolveTimelineExposureRange(
      selectedFrameIndex: 1,
      minFrameIndex: 0,
      maxFrameIndexExclusive: 24,
      exposureStateAt: glued,
    );
    final second = resolveTimelineExposureRange(
      selectedFrameIndex: 3,
      minFrameIndex: 0,
      maxFrameIndexExclusive: 24,
      exposureStateAt: glued,
    );

    expect(first.startFrameIndex, 0);
    expect(first.endFrameIndexExclusive, 2);
    expect(second.startFrameIndex, 2);
    expect(second.endFrameIndexExclusive, 4);
  });

  test('out-of-window selections resolve no range', () {
    final range = resolveTimelineExposureRange(
      selectedFrameIndex: 30,
      minFrameIndex: 0,
      maxFrameIndexExclusive: 24,
      exposureStateAt: stateAt,
    );

    expect(range.isBlock, isFalse);
  });
}
