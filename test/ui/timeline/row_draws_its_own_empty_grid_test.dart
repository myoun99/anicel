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

/// 🚨D43-2 (유저 2026-08-21): 「행이 있는데 **블록이 없는 곳**에 그리드가
/// 없단거야. 근데 **fx행은 존재**한단거고」
///
/// 🎯**원인은 z-order였다.** The line overlay sits UNDER the rows, and a row
/// paints an OPAQUE full-width ground (`ColoredBox(surface)` + the active
/// wash). So the overlay is covered for the whole width of every row that
/// draws one — and shows through a LANE row, which draws none. That is the
/// report, both halves, from one fact.
///
/// ⇒ The empty cells' lines cannot come from the overlay. They are the
/// ROW's, drawn on the row's own ground, through the SAME law function the
/// block interiors already use — so one boundary reads as one line whether
/// it crosses paper or empty space.
///
/// ⛔The rejected fix is pinned in `layer_timeline_grid_test`: stretching
/// the scroll content to the viewport put a grid where no row is, which is
/// 「레이어가 없는곳에 그리드를 만들란게아니야」.
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

  /// A block over 10..13 and empty everywhere else.
  final layer = Layer(
    id: const LayerId('draw'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {10: const TimelineExposure.drawing(FrameId('f1'), length: 4)},
  );

  TimelineRowCellsPainter painterFor({Color? rowGround}) =>
      TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        framesPerSecond: 24,
        rowGround: rowGround,
      );

  test('an EMPTY cell in a row gets the law\'s line, on the row\'s ground', () {
    final painter = painterFor(rowGround: scheme.surface);

    // Frame 5: empty, a plain base boundary at this zoom.
    final line = painter.heldSeamLineFor(5)!;
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: 5,
      frameCellExtent: 24,
      framesPerSecond: 24,
      colorScheme: scheme,
    )!;
    expect(
      line.color,
      timelineGridLineInkOnGround(ink, scheme.surface),
      reason:
          'the ROW\'s ground, not the panel\'s and not the cell\'s — an '
          'empty cell paints nothing, so its own background is transparent',
    );
    expect(
      line.rect.width,
      ink.strokeWidth,
      reason: 'and the law\'s width, like every other boundary',
    );
  });

  test('the same boundary reads the SAME whether it crosses paper or empty '
      'space — one line, one layer', () {
    final painter = painterFor(rowGround: scheme.surface);
    // 11 is interior to the block, 5 is empty. Both are plain boundaries at
    // this zoom, so the only thing that may differ is the GROUND each is
    // multiplied onto — never the ink, the width or the position.
    final inBlock = painter.heldSeamLineFor(11)!;
    final onEmpty = painter.heldSeamLineFor(5)!;
    expect(inBlock.rect.width, onEmpty.rect.width);
    expect(
      inBlock.rect.left - painter.cellRectFor(11).left,
      onEmpty.rect.left - painter.cellRectFor(5).left,
      reason: 'the same offset inside its own cell — the law\'s snap',
    );
    expect(
      inBlock.color,
      isNot(onEmpty.color),
      reason:
          'fixture premise: two different papers, so two results — what '
          'must match is the RULE, and that is asserted above',
    );
  });

  test(
    'a block\'s LEADING edge is still not a seam — the run starts there',
    () {
      final painter = painterFor(rowGround: scheme.surface);
      expect(painter.heldSeamLineFor(10), isNull);
    },
  );

  test('a chromeless row keeps the raw ink — it lies over the ARTWORK and '
      'has no ground to multiply against', () {
    final painter = painterFor();
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: 5,
      frameCellExtent: 24,
      framesPerSecond: 24,
      colorScheme: scheme,
    )!;
    expect(painter.heldSeamLineFor(5)!.color, ink.color);
  });

  test('the cadence still thins empty-space lines out at small zooms — the '
      'row did not grow a second grid rule', () {
    final painter = TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 8,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: scheme,
      baseTextStyle: const TextStyle(fontSize: 11),
      framesPerSecond: 24,
      rowGround: scheme.surface,
    );
    expect(
      painter.heldSeamLineFor(5),
      isNull,
      reason: 'thinned out, exactly as the empty-space overlay thins it',
    );
    expect(
      painter.heldSeamLineFor(6),
      isNotNull,
      reason: 'and the 6f beat survives, in empty space too',
    );
  });
}
