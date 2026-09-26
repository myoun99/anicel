import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart'
    show TimelineRunEdgeSide;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart'
    show
        TimelineRowRunAddTarget,
        TimelineRowRunTagTarget,
        timelineRowEditChromeModel;
import 'package:anicel/src/ui/timeline/timeline_run_end_handles.dart';

/// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q3, 「삼각형과 같은 법」): a
/// run's [+] and N/H/R buttons keep their size while the run holds them and
/// take ONE CELL where it does not — the block edge triangle's law, asked
/// through the same resolution. At I-22's ten-minute floor the 7px cluster
/// covered 56 frames, and short runs laid their buttons over one another
/// and over the cells a press was meant for.
void main() {
  /// One glued run of [length] frames opening at frame 400.
  Layer runOf(int length) => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {
      400: TimelineExposure.drawing(const FrameId('f1'), length: length),
    },
  );

  /// The run's buttons at [cell] per frame: the [+] and the tag of each
  /// edge, by the side they stand on.
  List<({TimelineRunEdgeSide side, Rect box})> buttonsOf(
    Layer layer, {
    required double cell,
  }) => [
    for (final target in timelineRowEditChromeModel(
      gripBlocks: const [],
      gripIdScope: 'q3',
      layer: layer,
      geometry: TimelineFrameGeometry(
        frameCellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 2000,
        leadingFrameSpacerWidth: 0,
        trailingFrameSpacerWidth: 0,
      ),
      crossAxisExtent: 28,
      axis: Axis.horizontal,
      includeRunEdges: true,
    ).targets)
      if (target is TimelineRowRunAddTarget)
        (side: target.side, box: target.rect)
      else if (target is TimelineRowRunTagTarget)
        (side: target.side, box: target.rect),
  ];

  void expectBeside(
    List<({TimelineRunEdgeSide side, Rect box})> buttons, {
    required double cell,
    required int length,
    required double width,
  }) {
    expect(buttons, hasLength(4), reason: 'the premise: both edges, [+]+tag');
    for (final (:side, :box) in buttons) {
      expect(box.width, closeTo(width, 1e-9), reason: '$side');
      if (side == TimelineRunEdgeSide.end) {
        expect(box.left, closeTo((400 + length) * cell, 1e-9));
      } else {
        expect(box.right, closeTo(400 * cell, 1e-9));
      }
    }
  }

  test('at the ten-minute floor a run too short to hold its buttons gives '
      'them ONE CELL, beside its edges', () {
    const cell = 1 / 8;
    // Ten frames are a pixel and a quarter; the buttons are seven.
    expectBeside(
      buttonsOf(runOf(10), cell: cell),
      cell: cell,
      length: 10,
      width: cell,
    );
  });

  test('a run that holds them keeps their size at the same zoom', () {
    const cell = 1 / 8;
    // Eighty frames are ten pixels.
    expectBeside(
      buttonsOf(runOf(80), cell: cell),
      cell: cell,
      length: 80,
      width: timelineRunClusterMainExtent(cell),
    );
  });

  test('at 100% nothing moved: half a cell, beside the edge', () {
    expectBeside(
      buttonsOf(runOf(2), cell: 24),
      cell: 24,
      length: 2,
      width: 12,
    );
  });

  test('a glyph keeps the share of its size its box kept', () {
    const cell = 1 / 8;
    final full = timelineRunClusterMainExtent(cell);
    expect(
      timelineRunClusterGlyphFit(
        Rect.fromLTWH(0, 0, full, 14),
        axis: Axis.horizontal,
        frameCellExtent: cell,
      ),
      1,
    );
    expect(
      timelineRunClusterGlyphFit(
        const Rect.fromLTWH(0, 0, cell, 14),
        axis: Axis.horizontal,
        frameCellExtent: cell,
      ),
      closeTo(cell / full, 1e-12),
    );
    expect(
      timelineRunClusterGlyphFit(
        const Rect.fromLTWH(0, 0, 14, cell),
        axis: Axis.vertical,
        frameCellExtent: cell,
      ),
      closeTo(cell / full, 1e-12),
      reason: 'measured along the frame axis, turned with it',
    );
  });
}
