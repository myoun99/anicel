import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// D32/D38 (2026-08-18): the per-cell block BORDER is gone — the interior
/// seams are the grid-line LAW consulted inside blocks: one line per
/// interior boundary, the law's cadence and strengths, ink multiplied onto
/// the block's own paper. Same question, same answer, inside and out.
void main() {
  final scheme = buildAppTheme().colorScheme;

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Layer blockLayer(Map<int, TimelineExposure> timeline) => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: timeline,
  );

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    double frameCellExtent = 24,
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: frameCellExtent,
      frameEndIndexExclusive: 40,
    ),
    crossAxisExtent: 28,
    exposureStateForLayer: stateFor,
    colorScheme: scheme,
    baseTextStyle: const TextStyle(fontSize: 11),
    framesPerSecond: 24,
  );

  test('the border is gone and the interior seam is the law\'s line', () {
    final painter = painterFor(
      blockLayer({0: const TimelineExposure.drawing(FrameId('f1'), length: 4)}),
    );

    expect(
      painter.resolvedCellStyleFor(0).border,
      Colors.transparent,
      reason: 'D32: the full-rect border double-stroked every seam — gone',
    );
    expect(
      painter.heldSeamLineFor(0),
      isNull,
      reason: 'a run START\'s leading boundary is the block edge, not a seam',
    );

    final seam = painter.heldSeamLineFor(1)!;
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: 1,
      frameCellExtent: 24,
      framesPerSecond: 24,
      colorScheme: scheme,
    )!;
    expect(
      seam.color,
      timelineGridLineInkOnGround(
        ink,
        painter.resolvedCellStyleFor(1).background,
      ),
      reason: 'D32: the law line multiplied onto this block\'s own paper',
    );
    final cell = painter.cellRectFor(1);
    expect(
      seam.rect,
      Rect.fromLTWH(
        cell.left + timelineGridLineSnap - ink.strokeWidth / 2,
        cell.top,
        ink.strokeWidth,
        cell.height,
      ),
      reason: 'the law\'s snap and width — one line, at the boundary',
    );
    expect(
      painter.heldSeamLineFor(4),
      isNull,
      reason: 'past the run there is no block to seam',
    );
  });

  test('D38: the cadence that thins the empty-space 1f lines thins the '
      'block seams identically — and the beats survive in both', () {
    // 8px cells: the base cadence is coarser than 1 (the law test pins
    // that premise), so a plain interior boundary goes silent…
    final painter = painterFor(
      blockLayer({
        2: const TimelineExposure.drawing(FrameId('f1'), length: 8),
      }),
      frameCellExtent: 8,
    );
    expect(painter.heldSeamLineFor(3), isNull);
    // …while the 6f boundary inside the same block keeps its stronger
    // line, exactly as it does in empty space.
    final beatSeam = painter.heldSeamLineFor(6)!;
    final sixInk = timelineGridSixLineInk(scheme);
    expect(
      beatSeam.color,
      timelineGridLineInkOnGround(
        sixInk,
        painter.resolvedCellStyleFor(6).background,
      ),
    );
  });

  test('a SECOND boundary crossing a block keeps the strongest line — the '
      'grid reads as one line through paper and dark ground alike', () {
    final painter = painterFor(
      blockLayer({
        20: const TimelineExposure.drawing(FrameId('f1'), length: 10),
      }),
    );
    final seam = painter.heldSeamLineFor(24)!;
    final secondInk = timelineGridSecondLineInk();
    expect(seam.rect.width, secondInk.strokeWidth);
    expect(
      seam.color,
      timelineGridLineInkOnGround(
        secondInk,
        painter.resolvedCellStyleFor(24).background,
      ),
    );
  });

  test('ghost blocks carry no seams — they carry no block chrome at all', () {
    final painter = painterFor(
      blockLayer({
        0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
        6: const TimelineExposure.drawing(FrameId('f1'), length: 4, ghost: true),
      }),
    );
    expect(painter.heldSeamLineFor(7), isNull);
  });
}
