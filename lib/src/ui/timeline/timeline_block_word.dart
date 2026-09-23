import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../text/word_condensation.dart';
import 'axis_turn.dart' show extentAlong;
import 'timeline_cell_style.dart';

/// Where a word sits in a block that is laid out as WIDGETS: the block is
/// the box the word is given, split evenly into [cells] along [axis], and
/// the word belongs to cell [cellIndex].
typedef TimelineBlockWordCells = ({
  Axis axis,
  int cells,
  int cellIndex,
  TimelineBlockWordGrowth growth,
  double acrossAlignment,
});

/// A block's WORD as a widget — the painters' law
/// ([timelineBlockWordLayout]) for the words a row builds out of widgets: a
/// lane key's name, an SE name, an instruction's writing.
///
/// 🚨One law for painted and built words alike (유저 2026-09-24: 「법같은거
/// 최대한 통일하면서. 컷블록의 텍스트든 se텍스트든 뭐든」). ↩️These words had
/// three rules of their own: a key's name shrank with the zoom, was CLIPPED
/// to its cell and hid below 14px cells; an SE name shrank WHOLE into its
/// chip (`FittedBox`); an instruction's writing ran past its span onto the
/// neighbours' cells. None of the three was the user's — all of them were
/// mine (`git log -S`: 2026-08-11 · 2026-07-09).
///
/// Its box is the word's ROOM — the size its parent gives it. The child is
/// laid out with no limit, so it keeps its type; it is then placed by F-96
/// on its cell inside the room and narrowed, each axis on its own, only as
/// far as the room demands. It never paints outside its box.
class TimelineBlockWord extends SingleChildRenderObjectWidget {
  const TimelineBlockWord({
    super.key,
    required this.place,
    required Widget super.child,
  });

  final TimelineBlockWordCells place;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTimelineBlockWord(place);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTimelineBlockWord renderObject,
  ) {
    renderObject.place = place;
  }
}

/// The render object of [TimelineBlockWord].
class RenderTimelineBlockWord extends RenderProxyBox {
  RenderTimelineBlockWord(this._place);

  TimelineBlockWordCells _place;
  TimelineBlockWordCells get place => _place;
  set place(TimelineBlockWordCells value) {
    if (value == _place) {
      return;
    }
    _place = value;
    markNeedsLayout();
  }

  ({Offset origin, WordFit fit}) _layout = (
    origin: Offset.zero,
    fit: wordFitsAsItIs,
  );

  @override
  void performLayout() {
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : constraints.constrain(Size.zero);
    final child = this.child;
    if (child == null) {
      return;
    }
    child.layout(const BoxConstraints(), parentUsesSize: true);
    final place = _place;
    final cells = place.cells < 1 ? 1 : place.cells;
    final cellExtent = extentAlong(place.axis, size) / cells;
    _layout = timelineBlockWordLayout(child.size, (
      axis: place.axis,
      room: Offset.zero & size,
      cellStart: cellExtent * place.cellIndex.clamp(0, cells - 1),
      cellExtent: cellExtent,
      growth: place.growth,
      acrossAlignment: place.acrossAlignment,
    ));
  }

  /// Where the word lands in this box, narrowed — ONE transform for what is
  /// painted and for what a hit test or a rect of the word reports, so the
  /// two cannot tell different stories.
  Matrix4 get _childTransform {
    final (:origin, :fit) = _layout;
    return Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..scaleByDouble(fit.x, fit.y, 1, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.pushTransform(
        needsCompositing,
        offset,
        _childTransform,
        (context, offset) => context.paintChild(child, offset),
      ),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_childTransform);

  /// A word is read, not pressed: the row's own gestures own this box.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}
