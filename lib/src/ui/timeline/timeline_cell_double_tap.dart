import 'package:flutter/gestures.dart' show GestureTapDownCallback;
import 'package:flutter/widgets.dart' show Axis, Offset;

import '../../models/layer_id.dart';

/// R26 #37: the cell editor opens only when BOTH taps land on the SAME
/// cell.
///
/// Flutter's double-tap recognizer accepts a second tap anywhere within
/// ~100 logical pixels of the first, so tapping two neighbouring frames of
/// the same block (a normal "seek along the block" gesture) opened the
/// rename dialog. The recognizer cannot tell us where the FIRST tap was —
/// so the cell rows record it here and the activation gate compares.
///
/// Process-wide single slot on purpose: only one pointer sequence is ever
/// mid-double-tap, and the state must survive the widget rebuild the first
/// tap's own selection triggers (build-local capture would be wiped).
class TimelineCellDoubleTapGate {
  TimelineCellDoubleTapGate._();

  static LayerId? _layerId;
  static String? _laneId;
  static int? _frameIndex;

  /// Records a tap-down on ([layerId], [frameIndex]) — of the lane [laneId]
  /// when the row is a property lane, whose cells are its owner's frames
  /// too: a layer's cell and its lane's cell at one frame are two cells.
  static void recordTapDown(
    LayerId layerId,
    int frameIndex, {
    String? laneId,
  }) {
    _layerId = layerId;
    _laneId = laneId;
    _frameIndex = frameIndex;
  }

  /// Whether a double tap ending on ([layerId], [frameIndex]) may open the
  /// cell editor — true only when the PREVIOUS tap hit the same cell.
  ///
  /// Timing is deliberately NOT re-checked here: the double-tap recognizer
  /// already enforces its 300ms window, and a wall-clock guard would go
  /// flaky under load (a widget test's fake-clock pump can take seconds of
  /// real time). This gate answers "where", never "when". Consumes the
  /// record either way.
  static bool acceptsActivation(
    LayerId layerId,
    int frameIndex, {
    String? laneId,
  }) {
    final sameCell =
        _layerId == layerId && _laneId == laneId && _frameIndex == frameIndex;
    reset();
    return sameCell;
  }

  /// Test seam: forgets any recorded tap.
  static void reset() {
    _layerId = null;
    _laneId = null;
    _frameIndex = null;
  }
}

/// A surface's cells as the double tap reads them: which cell a local
/// position is ([frameAt] — null for positions that are no cell at all:
/// outside the visible window, a zero-width zoom), and the frame axis they
/// lie along with a cell's extent on it, read at the tap since a zoom may
/// have moved it since the build. ONE value, so the two halves of the gate
/// cannot be handed two different grids.
typedef TimelineDoubleTapCells = ({
  int? Function(Offset localPosition) frameAt,
  Axis axis,
  double Function() cellExtent,
});

/// [localPosition] as a double tap aims it: where a cell is narrower than a
/// pixel, the middle of the pixel it falls in, so two taps in one pixel are
/// one cell whichever of its frames each landed on.
///
/// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q2, 「1px 보다 좁은 칸은 같은
/// 픽셀이면 같은 칸」): at I-22's ten-minute floor a pixel is eight frames,
/// and a pen or a finger that moved one pixel between the taps landed on
/// another cell — the editors opened only for a mouse held still. From a
/// pixel a cell up, nothing changes.
Offset timelineDoubleTapAim(
  Offset localPosition,
  TimelineDoubleTapCells cells,
) {
  if (cells.cellExtent() >= 1) {
    return localPosition;
  }
  return cells.axis == Axis.horizontal
      ? Offset(localPosition.dx.floorToDouble() + 0.5, localPosition.dy)
      : Offset(localPosition.dx, localPosition.dy.floorToDouble() + 0.5);
}

/// The cell a double tap at [localPosition] names ([timelineDoubleTapAim]).
int? _cellAimedAt(Offset localPosition, TimelineDoubleTapCells cells) =>
    cells.frameAt(timelineDoubleTapAim(localPosition, cells));

/// The RECORD half of the frame-block activation law, as the one closure
/// every cell surface mounts on its press region's `onPressDown`.
///
/// The dense timeline rows and the storyboard's sparse strips both build
/// their handler HERE, so "which press arms the gate" cannot fork per
/// surface again (절대명령 2026-08-17: reuse the frame-block law, never
/// invent a sibling of it). The LANE bands mount it too, naming their lane
/// (유저 2026-09-11: 「트랜스폼행에서 더블클릭으로 편집창 안열리는것등 이런거
/// 싹 법 하나로 통일」).
void Function(Offset localPosition) timelineCellDoubleTapRecord({
  required LayerId layerId,
  String? laneId,
  required TimelineDoubleTapCells cells,
}) {
  return (localPosition) {
    final frameIndex = _cellAimedAt(localPosition, cells);
    if (frameIndex != null) {
      TimelineCellDoubleTapGate.recordTapDown(
        layerId,
        frameIndex,
        laneId: laneId,
      );
    }
  };
}

/// The ACTIVATION half: an `onDoubleTapDown` that fires [onActivate] only
/// when the gate agrees BOTH taps hit the same cell (R26 #37 — two taps on
/// different frames of one block are two seeks, never an editor).
///
/// [cells] must be the SAME the record half uses, or the two halves
/// describe two different grids and the gate compares apples to pears.
GestureTapDownCallback timelineCellDoubleTapActivation({
  required LayerId layerId,
  String? laneId,
  required TimelineDoubleTapCells cells,
  required void Function(int frameIndex) onActivate,
}) {
  return (details) {
    final frameIndex = _cellAimedAt(details.localPosition, cells);
    if (frameIndex != null &&
        TimelineCellDoubleTapGate.acceptsActivation(
          layerId,
          frameIndex,
          laneId: laneId,
        )) {
      onActivate(frameIndex);
    }
  };
}
