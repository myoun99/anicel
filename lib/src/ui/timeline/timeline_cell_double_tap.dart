import 'package:flutter/gestures.dart' show GestureTapDownCallback;
import 'package:flutter/widgets.dart' show Offset;

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
  static int? _frameIndex;

  /// Records a tap-down on ([layerId], [frameIndex]).
  static void recordTapDown(LayerId layerId, int frameIndex) {
    _layerId = layerId;
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
  static bool acceptsActivation(LayerId layerId, int frameIndex) {
    final sameCell = _layerId == layerId && _frameIndex == frameIndex;
    _layerId = null;
    _frameIndex = null;
    return sameCell;
  }

  /// Test seam: forgets any recorded tap.
  static void reset() {
    _layerId = null;
    _frameIndex = null;
  }
}

/// The RECORD half of the frame-block activation law, as the one closure
/// every cell surface mounts on its press region's `onPressDown`.
///
/// [frameAt] answers which cell a local position is — null for positions
/// that are no cell at all (outside the visible window, a zero-width
/// zoom). The dense timeline rows and the storyboard's sparse strips both
/// build their handler HERE, so "which press arms the gate" cannot fork
/// per surface again (절대명령 2026-08-17: reuse the frame-block law, never
/// invent a sibling of it).
void Function(Offset localPosition) timelineCellDoubleTapRecord({
  required LayerId layerId,
  required int? Function(Offset localPosition) frameAt,
}) {
  return (localPosition) {
    final frameIndex = frameAt(localPosition);
    if (frameIndex != null) {
      TimelineCellDoubleTapGate.recordTapDown(layerId, frameIndex);
    }
  };
}

/// The ACTIVATION half: an `onDoubleTapDown` that fires [onActivate] only
/// when the gate agrees BOTH taps hit the same cell (R26 #37 — two taps on
/// different frames of one block are two seeks, never an editor).
///
/// [frameAt] must be the SAME resolver the record half uses, or the two
/// halves describe two different grids and the gate compares apples to
/// pears.
GestureTapDownCallback timelineCellDoubleTapActivation({
  required LayerId layerId,
  required int? Function(Offset localPosition) frameAt,
  required void Function(int frameIndex) onActivate,
}) {
  return (details) {
    final frameIndex = frameAt(details.localPosition);
    if (frameIndex != null &&
        TimelineCellDoubleTapGate.acceptsActivation(layerId, frameIndex)) {
      onActivate(frameIndex);
    }
  };
}
