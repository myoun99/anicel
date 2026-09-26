import 'package:flutter/gestures.dart'
    show DoubleTapGestureRecognizer, GestureTapDownCallback, PointerDownEvent;
import 'package:flutter/widgets.dart';

import '../../models/layer_id.dart';
import '../input/value_control_pointers.dart' show controlOwnsTap;

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
///
/// ★ONE GATE FOR EVERY DOUBLE CLICK ON THE FRAME PANELS — a cell's and a row
/// LABEL's (I-48, 유저 2026-09-26: 「동작 발동은 프레임블록이랑 똑같이 …
/// 시간간격같은거 프레임블록 로직 그대로 재사용/법통일, 이런 더블클릭 로직은
/// 공용화할것」). What it keeps is WHAT the first press landed on, as its
/// surface keeps it: a cell as (row, lane, frame), compared by equality; a
/// label as its row, with what a double click begun there does
/// ([TimelineLabelDoubleClick]). Two presses on one target in the
/// recognizer's window are a double click, whatever the target is.
class TimelineDoubleTapGate {
  TimelineDoubleTapGate._();

  static Object? _press;

  /// Records a tap-down — what a press landed on, as its surface keeps it.
  static void recordTapDown(Object press) => _press = press;

  /// What the PREVIOUS tap landed on — the first tap of the double tap
  /// ending now, for its surface to compare with where this one landed.
  ///
  /// Timing is deliberately NOT re-checked here: the double-tap recognizer
  /// already enforces its 300ms window, and a wall-clock guard would go
  /// flaky under load (a widget test's fake-clock pump can take seconds of
  /// real time). This gate answers "where", never "when". Consumes the
  /// record.
  static Object? takeFirstPress() {
    final press = _press;
    reset();
    return press;
  }

  /// Whether a double tap ending on [target] may activate it — true only
  /// when the PREVIOUS tap hit the same target. Consumes the record either
  /// way.
  static bool acceptsActivation(Object target) => takeFirstPress() == target;

  /// Forgets any recorded tap: the last press landed on nothing a double
  /// tap aims at ([ControlYieldingDoubleTapGestureRecognizer]).
  static void reset() => _press = null;
}

/// A cell as the gate compares it — of the lane [lane] when the row is a
/// property lane, whose cells are its owner's frames too: a layer's cell and
/// its lane's cell at one frame are two cells.
({LayerId layer, String? lane, int frame}) _cell(
  LayerId layer,
  int frame,
  String? lane,
) => (layer: layer, lane: lane, frame: frame);

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
      TimelineDoubleTapGate.recordTapDown(_cell(layerId, frameIndex, laneId));
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
        TimelineDoubleTapGate.acceptsActivation(
          _cell(layerId, frameIndex, laneId),
        )) {
      onActivate(frameIndex);
    }
  };
}

/// What a double click on a row's LABEL does — the rename (I-48) — asked of
/// the host at the PRESS that may begin one, [pressed] being that row.
///
/// 🚨At the press and not at the second one: the first click is a settled
/// tap, and a settled tap clears the selection (T10, 「클릭하고 떼면 뭐든
/// 비우게」) — so by the second press the rows a double click inside the
/// selection was aimed at are no longer selected. The user's rule is about
/// where the label was pressed (「여러레이어 선택한채로 해당 레이어
/// 발동했을때 선택범위 안이면 다른레이어도 변경, 아니면 해당레이어만」), so the
/// host answers it while the selection still says.
typedef TimelineLabelDoubleClick = VoidCallback Function(LayerId pressed);

/// A row LABEL's press as the gate keeps it: the row it landed on — two
/// presses anywhere on one row's label are a double click on it (「해당
/// 레이어 안에서 두번의 클릭이 이루어지면」) — and what a double click begun
/// by it does.
final class _LabelPress {
  const _LabelPress(this.row, this.doubleClick);

  final LayerId row;
  final VoidCallback doubleClick;
}

/// The RECORD half for a row label — the same gate the cells arm.
void Function(Offset localPosition) timelineLabelDoubleTapRecord(
  LayerId layerId,
  TimelineLabelDoubleClick doubleClick,
) => (_) => TimelineDoubleTapGate.recordTapDown(
  _LabelPress(layerId, doubleClick(layerId)),
);

/// The ACTIVATION half for a row label: runs what the FIRST press armed,
/// when both taps landed on [layerId]'s label.
GestureTapDownCallback timelineLabelDoubleTapActivation(LayerId layerId) =>
    (_) {
      final first = TimelineDoubleTapGate.takeFirstPress();
      if (first is _LabelPress && first.row == layerId) {
        first.doubleClick();
      }
    };

/// A row label's double click, mounted around the label — the one widget
/// every surface that shows a layer's label mounts (the timeline rail, the
/// x-sheet's header, the storyboard's rows), both halves in it.
///
/// The frame block's recognizer — its window, its slop, its moment (the
/// second press DOWN) — yielding the label's controls
/// ([ControlYieldingDoubleTapGestureRecognizer]). Every press it counts is
/// RECORDED after the double tap that press may complete has fired: the
/// order the cells' two halves keep, the first press read before the
/// second one's record replaces it. And the record runs before the label's
/// own pick, which listens outside it, so the host reads the selection as
/// the press found it.
Widget timelineLabelDoubleTapDetector({
  required LayerId layerId,
  required TimelineLabelDoubleClick doubleClick,
  required Widget child,
}) => RawGestureDetector(
  gestures: <Type, GestureRecognizerFactory>{
    ControlYieldingDoubleTapGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<
          ControlYieldingDoubleTapGestureRecognizer
        >(ControlYieldingDoubleTapGestureRecognizer.new, (recognizer) {
          recognizer.onDoubleTapDown = timelineLabelDoubleTapActivation(
            layerId,
          );
          recognizer.onDoubleTap = () {};
          recognizer.onPress = timelineLabelDoubleTapRecord(
            layerId,
            doubleClick,
          );
        }),
  },
  child: child,
);

/// The frame block's double-tap recognizer, for a surface that holds
/// CONTROLS — a row label and its buttons.
///
/// 「A press that lands on a CONTROL belongs to that control」
/// ([controlOwnsTap] — the law the eager pan and the row's own pick already
/// ask): such a press is no tap of a double click, first or second. And it
/// FORGETS the gate's record, because the last press landed on a control,
/// which no double click aims at. The cell surfaces mount no control inside
/// their detector, so the plain recognizer is this one there; on a label it
/// is the difference between a double click and a stray one — a label
/// clicked once and then an eye clicked twice made a rename, the eye's
/// presses recording nothing for their double tap to be compared against
/// but the label.
class ControlYieldingDoubleTapGestureRecognizer
    extends DoubleTapGestureRecognizer {
  ControlYieldingDoubleTapGestureRecognizer({super.debugOwner});

  /// Every press this recognizer counts, AFTER the double tap it may
  /// complete has fired — a label's record half
  /// ([timelineLabelDoubleTapDetector]).
  void Function(Offset localPosition)? onPress;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      !controlOwnsTap(event.pointer) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    onPress?.call(event.localPosition);
  }

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    if (controlOwnsTap(event.pointer)) {
      TimelineDoubleTapGate.reset();
    }
    super.handleNonAllowedPointer(event);
  }
}
