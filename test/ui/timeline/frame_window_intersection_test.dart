import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import 'timeline_frame_geometry_probe.dart';

/// The row builders keep a HALF-OPEN window: a block whose end lands
/// exactly on the window's first frame is outside, one whose start lands
/// on the window's end frame is outside, and one that straddles either wall
/// is in. Every builder that walks blocks answers that question the same
/// way, and [TrackFrameRangeSelection.overlaps] is the same predicate on
/// the storyboard's axis.
void main() {
  Layer layerWith(Map<int, TimelineExposure> timeline, {LayerKind? kind}) =>
      Layer(
        id: const LayerId('layer-a'),
        name: 'A',
        kind: kind ?? LayerKind.animation,
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
          Frame(id: const FrameId('f3'), duration: 1, strokes: const []),
        ],
        timeline: timeline,
      );

  /// Blocks [0,4), [4,6) and [8,12) against the window [4,8): the first
  /// ends ON the window's start, the last starts ON its end, only the
  /// middle one is inside.
  final timeline = {
    0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
    4: const TimelineExposure.drawing(FrameId('f2'), length: 2),
    8: const TimelineExposure.drawing(FrameId('f3'), length: 4),
  };
  const windowStart = 4;
  const windowEnd = 8;

  test('the edit chrome model grips only the block inside the window', () {
    final layer = layerWith(timeline);
    final model = timelineRowEditChromeModel(
      gripBlocks: timelineLayerGripBlocks(layer),
      gripIdScope: 'layer-a',
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 48,
        frameStartIndex: windowStart,
        frameEndIndexExclusive: windowEnd,
      ).value,
      crossAxisExtent: 52,
      axis: Axis.horizontal,
      includeRunEdges: false,
    );
    final gripStarts = model.targets
        .whereType<TimelineRowGripTarget>()
        .map((t) => t.blockStartIndex)
        .toSet();
    expect(gripStarts, {4});
  });

  test('the SE label overlays cover only the block inside the window', () {
    final overlays = timelineRowSeLabelOverlays(
      layer: layerWith(timeline, kind: LayerKind.se),
      frameStartIndex: windowStart,
      frameEndIndexExclusive: windowEnd,
      axis: Axis.horizontal,
    );
    expect(overlays, hasLength(1));
  });

  test('the run labels painter prints only the block inside the window', () {
    final painter = TimelineRowRunLabelsPainter(
      baseTextStyle: const TextStyle(fontSize: 14),
      layer: layerWith(timeline),
      geometry: testFrameGeometry(
        frameCellExtent: 48,
        frameStartIndex: windowStart,
        frameEndIndexExclusive: windowEnd,
      ),
      crossAxisExtent: 52,
      showSeconds: false,
      countingBase: 24,
    );
    expect(painter.runLabels().map((l) => l.startIndex).toList(), [4]);
  });

  test('the instruction overlays mark only the span inside the window', () {
    // The same three blocks as spans, and BOTH passes — the marks and the
    // crossing markers — are asked once and read the same answer.
    final layer = layerWith(timeline).copyWith(
      kind: LayerKind.instruction,
      instructions: {
        0: const InstructionEvent(instructionId: 'pan', length: 4),
        4: const InstructionEvent(instructionId: 'pan', length: 2),
        8: const InstructionEvent(instructionId: 'pan', length: 4),
      },
    );
    final marked = timelineRowInstructionOverlays(
      layer: layer,
      frameStartIndex: windowStart,
      frameEndIndexExclusive: windowEnd,
      axis: Axis.horizontal,
      defById: CameraInstructionSet.standard.defById,
    ).whereType<TimelineFrameSpan>().map((s) => s.placement.startIndex);
    expect(marked, [4]);

    final warned = <int>[];
    timelineRowInstructionOverlays(
      layer: layer,
      frameStartIndex: windowStart,
      frameEndIndexExclusive: windowEnd,
      axis: Axis.horizontal,
      defById: CameraInstructionSet.standard.defById,
      crossingWarningTooltip: (start) {
        warned.add(start);
        return null;
      },
      crossingWarningColor: const Color(0xFFFF0000),
    );
    expect(warned, [4], reason: 'the marker pass takes the same window');
  });

  test('a track range selection overlaps the same half-open way', () {
    const selection = TrackFrameRangeSelection(
      trackId: TrackId('t'),
      anchorRow: TrackRowAddress(TrackId('t')),
      startFrame: 4,
      endFrameExclusive: 8,
    );
    expect(selection.overlaps(0, 4), isFalse, reason: 'ends ON the start');
    expect(selection.overlaps(8, 12), isFalse, reason: 'starts ON the end');
    expect(selection.overlaps(3, 5), isTrue, reason: 'straddles the start');
    expect(selection.overlaps(7, 9), isTrue, reason: 'straddles the end');
    expect(selection.overlaps(5, 6), isTrue, reason: 'inside');
    expect(selection.overlaps(0, 12), isTrue, reason: 'contains the window');
  });
}
