import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../text/word_condensation.dart';
import 'axis_turn.dart' show extentAlong;
import 'timeline_cell_style.dart';
import 'timeline_glyph_cache.dart' show timelineWordSetOnto;

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

/// The box a block word is given: all its parent allows — its ROOM.
Size _roomFor(BoxConstraints constraints) => constraints.biggest.isFinite
    ? constraints.biggest
    : constraints.constrain(Size.zero);

/// The slot of a word placed at [place] in a room of [size]
/// ([timelineBlockWordLayout]).
TimelineBlockWordSlot _slotIn(Size size, TimelineBlockWordCells place) {
  final cells = place.cells < 1 ? 1 : place.cells;
  final cellExtent = extentAlong(place.axis, size) / cells;
  return (
    axis: place.axis,
    room: Offset.zero & size,
    cellStart: cellExtent * place.cellIndex.clamp(0, cells - 1),
    cellExtent: cellExtent,
    growth: place.growth,
    acrossAlignment: place.acrossAlignment,
  );
}

/// A block's WORD as a widget — the painters' law
/// ([timelineBlockWordLayout]) for the words a row builds out of widgets:
/// a lane key's name, an SE name, an instruction's writing.
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
///
/// It narrows what it is given and nothing more — a word written in a line
/// is [TimelineBlockText], which sets its letters itself.
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
    size = _roomFor(constraints);
    final child = this.child;
    if (child == null) {
      return;
    }
    child.layout(const BoxConstraints(), parentUsesSize: true);
    _layout = timelineBlockWordLayout(child.size, _slotIn(size, _place));
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

/// A block's WORD written in a line, as a widget that knows its letters — a
/// lane key's name, an instruction's writing along the timeline, an SE name
/// on the sheet. It is set and laid by the painted block word's own code
/// ([timelineWordSetOnto], [timelineBlockWordLayout]): where its room runs
/// short its letter gaps give way first (F-234-Q1: 「글자 사이부터 줄이기」),
/// and only past that is it narrowed, each axis on its own.
///
/// ↩️It was a `Text` inside [TimelineBlockWord], which can narrow a word but
/// cannot set it: the gaps are how a word is set, and only here, at layout,
/// is its room known — a zoom lays it out again, it does not rebuild it.
class TimelineBlockText extends LeafRenderObjectWidget {
  const TimelineBlockText({
    super.key,
    required this.text,
    required this.style,
    required this.place,
  });

  final String text;

  /// Resolved as a [Text] resolves its style: over the ambient
  /// [DefaultTextStyle] while it inherits, and scaled by the ambient text
  /// scaler.
  final TextStyle style;
  final TimelineBlockWordCells place;

  TextStyle _resolvedStyle(BuildContext context) {
    final merged = style.inherit
        ? DefaultTextStyle.of(context).style.merge(style)
        : style;
    return merged.copyWith(
      fontSize: MediaQuery.textScalerOf(
        context,
      ).scale(merged.fontSize ?? kDefaultFontSize),
    );
  }

  @override
  RenderTimelineBlockText createRenderObject(BuildContext context) =>
      RenderTimelineBlockText(
        text: text,
        style: _resolvedStyle(context),
        place: place,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTimelineBlockText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = _resolvedStyle(context)
      ..place = place;
  }
}

/// The render object of [TimelineBlockText].
class RenderTimelineBlockText extends RenderBox {
  RenderTimelineBlockText({
    required String text,
    required TextStyle style,
    required TimelineBlockWordCells place,
  }) : _text = text,
       _style = style,
       _place = place;

  String _text;
  String get text => _text;
  set text(String value) {
    if (value == _text) {
      return;
    }
    _text = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  TextStyle _style;
  TextStyle get style => _style;
  set style(TextStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsLayout();
  }

  TimelineBlockWordCells _place;
  TimelineBlockWordCells get place => _place;
  set place(TimelineBlockWordCells value) {
    if (value == _place) {
      return;
    }
    _place = value;
    markNeedsLayout();
  }

  TextPainter? _glyph;
  ({Offset origin, WordFit fit}) _layout = (
    origin: Offset.zero,
    fit: wordFitsAsItIs,
  );

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => _roomFor(constraints);

  @override
  void performLayout() {
    final glyph = timelineWordSetOnto(_text, _style, size.width).glyph;
    _glyph = glyph;
    _layout = timelineBlockWordLayout(glyph.size, _slotIn(size, _place));
  }

  /// Where the word lands in this box, narrowed — the box is only its room.
  Rect get wordRect {
    final glyph = _glyph;
    if (glyph == null) {
      return Rect.zero;
    }
    final (:origin, :fit) = _layout;
    return origin & Size(glyph.width * fit.x, glyph.height * fit.y);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final glyph = _glyph;
    if (glyph == null) {
      return;
    }
    paintFittedText(
      context.canvas,
      glyph,
      offset + _layout.origin,
      _layout.fit,
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = TextDirection.ltr;
  }
}
