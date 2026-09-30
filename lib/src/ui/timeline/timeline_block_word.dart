import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../text/vertical_writing.dart' show verticalTextCells;
import '../text/vertical_writing_text.dart';
import '../text/word_condensation.dart';
import 'axis_turn.dart' show extentAlong;
import 'timeline_cell_style.dart';
import 'timeline_glyph_cache.dart' show timelineWordSetOnto;

/// Where a WORD sits in a block a row builds as WIDGETS — a lane key's
/// name, an SE name, an instruction's writing: the block is the box the word
/// is given, split evenly into [cells] along [axis], and the word belongs to
/// cell [cellIndex]. It is set and laid by the painters' law
/// ([timelineBlockWordLayout]).
///
/// 🚨One law for painted and built words alike (유저 2026-09-24: 「법같은거
/// 최대한 통일하면서. 컷블록의 텍스트든 se텍스트든 뭐든」). ↩️These words had
/// three rules of their own: a key's name shrank with the zoom, was CLIPPED
/// to its cell and hid below 14px cells; an SE name shrank WHOLE into its
/// chip (`FittedBox`); an instruction's writing ran past its span onto the
/// neighbours' cells. None of the three was the user's — all of them were
/// mine (`git log -S`: 2026-08-11 · 2026-07-09).
typedef TimelineBlockWordCells = ({
  Axis axis,
  int cells,
  int cellIndex,
  TimelineBlockWordGrowth growth,
  double acrossAlignment,
});

/// The box a built word is given: all its parent allows — its ROOM.
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

/// A built word's style: over the ambient [DefaultTextStyle] while it
/// inherits — and at its own size, whatever the OS text size.
///
/// 🗣️block-words-os-text-size-Q1 (유저 2026-09-30: 「블록 글자는 전부 안
/// 따른다」): a block's word keeps one type at every zoom, and at every OS
/// text size too — built or painted alike. ↩️The built ones followed the
/// setting because the `Text` they replaced did (its default, not anyone's
/// rule), so under a large text setting one row wrote its words at two
/// sizes: a lane key's name, an SE name and an instruction's writing
/// larger than the frame names and the koma beside them.
TextStyle _resolvedStyle(BuildContext context, TextStyle style) =>
    DefaultTextStyle.of(context).style.merge(style);

/// A built word WRITTEN IN A LINE — a lane key's name, an instruction's
/// writing along the timeline, an SE name on the sheet. It is set and laid
/// by the painted block word's own code ([timelineWordSetOnto],
/// [timelineBlockWordLayout]): where its room runs short its letter gaps
/// give way first (F-234-Q1: 「글자 사이부터 줄이기」), and only past that is
/// it narrowed, each axis on its own.
///
/// ↩️It was a `Text` inside a box that narrowed whatever child it was given
/// — which can narrow a word but cannot set it: the gaps are how a word is
/// set, and only here, at layout, is its room known. A zoom lays it out
/// again; it does not rebuild it.
class TimelineBlockText extends LeafRenderObjectWidget {
  const TimelineBlockText({
    super.key,
    required this.text,
    required this.style,
    required this.place,
  });

  final String text;
  final TextStyle style;
  final TimelineBlockWordCells place;

  @override
  RenderTimelineBlockText createRenderObject(BuildContext context) =>
      RenderTimelineBlockText(
        text: text,
        style: _resolvedStyle(context, style),
        place: place,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTimelineBlockText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = _resolvedStyle(context, style)
      ..place = place;
  }
}

/// A built word WRITTEN DOWN A COLUMN — an SE name on the timeline, an
/// instruction's writing on the sheet — set and laid by the same law as
/// [TimelineBlockText]: where its room runs short down the column, the
/// space from glyph to glyph gives way first (F-234-Q1), and only past that
/// is it narrowed. The one vertical renderer draws it ([paintVerticalText]).
class TimelineBlockColumn extends LeafRenderObjectWidget {
  const TimelineBlockColumn({
    super.key,
    required this.text,
    required this.style,
    this.lineHeight = verticalWritingLineHeight,
    required this.latinForm,
    required this.place,
  });

  final String text;
  final TextStyle style;

  /// A slot's natural extent down the column, in ems.
  final double lineHeight;
  final VerticalLatinForm latinForm;
  final TimelineBlockWordCells place;

  @override
  RenderTimelineBlockColumn createRenderObject(BuildContext context) =>
      RenderTimelineBlockColumn(
        text: text,
        style: _resolvedStyle(context, style),
        lineHeight: lineHeight,
        latinForm: latinForm,
        place: place,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTimelineBlockColumn renderObject,
  ) {
    renderObject
      ..text = text
      ..style = _resolvedStyle(context, style)
      ..lineHeight = lineHeight
      ..latinForm = latinForm
      ..place = place;
  }
}

/// What the two built words share: a word of [text] in its room, laid by
/// the block-word law, read aloud as its text, and never pressed — the
/// row's own gestures own its box.
abstract class RenderTimelineBuiltWord extends RenderBox {
  RenderTimelineBuiltWord({
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

  /// The word as it is set, before the law narrows it.
  Size _set = Size.zero;
  ({Offset origin, WordFit fit}) _layout = (
    origin: Offset.zero,
    fit: wordFitsAsItIs,
  );

  /// Sets the word in [room] — how long it runs once its gaps gave way.
  Size setWordIn(Size room);

  /// Paints the word as it was set at [origin], narrowed by [fit].
  void paintSetWord(Canvas canvas, Offset origin, WordFit fit);

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => _roomFor(constraints);

  @override
  void performLayout() {
    _set = setWordIn(size);
    _layout = timelineBlockWordLayout(_set, _slotIn(size, _place));
  }

  /// Where the word lands in this box, narrowed — the box is only its room.
  Rect get wordRect {
    final (:origin, :fit) = _layout;
    return origin & Size(_set.width * fit.x, _set.height * fit.y);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_text.isEmpty) {
      return;
    }
    paintSetWord(context.canvas, offset + _layout.origin, _layout.fit);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = TextDirection.ltr;
  }
}

/// The render object of [TimelineBlockText].
class RenderTimelineBlockText extends RenderTimelineBuiltWord {
  RenderTimelineBlockText({
    required super.text,
    required super.style,
    required super.place,
  });

  TextPainter? _glyph;

  @override
  Size setWordIn(Size room) {
    final glyph = timelineWordSetOnto(_text, _style, room.width).glyph;
    _glyph = glyph;
    return glyph.size;
  }

  @override
  void paintSetWord(Canvas canvas, Offset origin, WordFit fit) {
    final glyph = _glyph;
    if (glyph != null) {
      paintFittedText(canvas, glyph, origin, fit);
    }
  }
}

/// The render object of [TimelineBlockColumn].
class RenderTimelineBlockColumn extends RenderTimelineBuiltWord {
  RenderTimelineBlockColumn({
    required super.text,
    required super.style,
    required double lineHeight,
    required VerticalLatinForm latinForm,
    required super.place,
  }) : _lineHeight = lineHeight,
       _latinForm = latinForm;

  double _lineHeight;
  double get lineHeight => _lineHeight;
  set lineHeight(double value) {
    if (value == _lineHeight) {
      return;
    }
    _lineHeight = value;
    markNeedsLayout();
  }

  VerticalLatinForm _latinForm;
  VerticalLatinForm get latinForm => _latinForm;
  set latinForm(VerticalLatinForm value) {
    if (value == _latinForm) {
      return;
    }
    _latinForm = value;
    markNeedsLayout();
  }

  int _slots = 0;

  double get _fontSize => _style.fontSize ?? kDefaultFontSize;

  @override
  Size setWordIn(Size room) {
    final natural = verticalWritingNaturalBox(
      verticalTextCells(_text, latinForm: _latinForm),
      fontSize: _fontSize,
      lineHeight: _lineHeight,
    );
    _slots = natural.slots;
    final tightening = wordTightening(
      extent: natural.size.height,
      gaps: _slots - 1,
      room: room.height,
    );
    return Size(
      natural.size.width,
      natural.size.height - (_slots - 1) * tightening,
    );
  }

  @override
  void paintSetWord(Canvas canvas, Offset origin, WordFit fit) {
    if (_slots <= 0) {
      return;
    }
    // Slots of one extent, the column exactly as long as it was set: the
    // gaps it gave are shared out between them. The leading it keeps is
    // below zero once they gave more than it had, and handing that over is
    // what keeps the type its size — the renderer would shrink a glyph to
    // its slot's extent less a leading it no longer has.
    final slot = _set.height / _slots;
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(fit.x, fit.y);
    paintVerticalText(
      canvas,
      _text,
      style: _style,
      centerX: _set.width / 2,
      top: 0,
      mainExtent: _set.height,
      naturalCellExtent: slot,
      cellPadding: slot - _fontSize,
      maxCellWidth: _set.width,
      mainAlignment: 0.5,
      latinForm: _latinForm,
      overflow: VerticalTextOverflow.ellipsis,
    );
    canvas.restore();
  }
}
