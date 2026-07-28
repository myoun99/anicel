import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_block_visual.dart';

/// Covered runs (start + holds + marks inside the hold) form drawing block
/// visuals; uncovered cells never do, and a drawing start always begins a
/// fresh block even when glued to the previous one.
void main() {
  TimelineExposureBlockVisualSegment segment({
    TimelineCellExposureState? previous,
    required TimelineCellExposureState current,
    TimelineCellExposureState? next,
  }) {
    return calculateTimelineExposureBlockVisualSegment(
      previous: previous,
      current: current,
      next: next,
    );
  }

  test('uncovered cells are not blocks', () {
    expect(
      segment(current: TimelineCellExposureState.uncovered).isBlock,
      isFalse,
    );
    expect(
      segment(current: TimelineCellExposureState.markUncovered).isBlock,
      isFalse,
    );
  });

  test('a single-frame drawing rounds on both sides', () {
    final result = segment(
      previous: TimelineCellExposureState.uncovered,
      current: TimelineCellExposureState.drawingStart,
      next: TimelineCellExposureState.uncovered,
    );

    expect(result.kind, TimelineExposureBlockKind.drawing);
    expect(result.continuesFromPrevious, isFalse);
    expect(result.continuesToNext, isFalse);
  });

  test('held cells continue the block in both directions', () {
    final result = segment(
      previous: TimelineCellExposureState.drawingStart,
      current: TimelineCellExposureState.held,
      next: TimelineCellExposureState.held,
    );

    expect(result.kind, TimelineExposureBlockKind.drawing);
    expect(result.continuesFromPrevious, isTrue);
    expect(result.continuesToNext, isTrue);
  });

  test('marks inside a hold continue the block visual', () {
    final result = segment(
      previous: TimelineCellExposureState.held,
      current: TimelineCellExposureState.markHeld,
      next: TimelineCellExposureState.held,
    );

    expect(result.kind, TimelineExposureBlockKind.drawing);
    expect(result.continuesFromPrevious, isTrue);
    expect(result.continuesToNext, isTrue);
  });

  test('a glued next drawing start ends the current block visual', () {
    final result = segment(
      previous: TimelineCellExposureState.held,
      current: TimelineCellExposureState.held,
      next: TimelineCellExposureState.drawingStart,
    );

    expect(result.continuesToNext, isFalse);
  });

  test('a drawing start never continues from the previous block', () {
    final result = segment(
      previous: TimelineCellExposureState.held,
      current: TimelineCellExposureState.drawingStart,
      next: TimelineCellExposureState.held,
    );

    expect(result.continuesFromPrevious, isFalse);
    expect(result.continuesToNext, isTrue);
  });

  test('block ends at the coverage boundary before empty cells', () {
    final result = segment(
      previous: TimelineCellExposureState.drawingStart,
      current: TimelineCellExposureState.held,
      next: TimelineCellExposureState.uncovered,
    );

    expect(result.continuesToNext, isFalse);
  });
}
