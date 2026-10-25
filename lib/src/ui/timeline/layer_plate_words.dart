import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../text/vertical_writing_text.dart';
import '../widgets/tick_text.dart';
import 'axis_turn.dart';

/// A word a label plate writes, set the way its rail reads it — stood up
/// down a rail's slot ([StoodPlateWords]), laid across on the sheet's
/// ([LyingPlateWords]). What a box that writes it asks of it: the box it
/// asks for, what it takes in a room, and what paints it.
///
/// ★The words are set by the widgets they used to be: a stood word by its
/// [VerticalWritingText], a lying one as a `Text` sets a line — so a plate
/// that paints them itself paints what those painted.
sealed class PlateWords {
  /// What a screen reader hears.
  String get text;

  /// The type it is set in — its ink included.
  TextStyle get style;

  /// The box the word asks for, unconstrained.
  Size get natural;

  /// The box it takes where [constraints] hold it — as its widget did.
  Size sizeIn(BoxConstraints constraints);

  /// Paints the word set in a box of [size] at the canvas's origin.
  void paint(Canvas canvas, Size size);

  /// What says it must be painted again — a stood word's painter, whose
  /// stand-in words land as bakes later. Null: nothing does.
  Listenable? get repaint;

  /// Whether [other] paints what this one does, laid out alike — so a box
  /// keeps the one it has.
  bool samePaintAs(PlateWords other);

  /// Lets go of what it laid out.
  void dispose();
}

/// A word stood up down a column, as its [VerticalWritingText] paints it.
final class StoodPlateWords extends PlateWords {
  StoodPlateWords(VerticalWritingText column, BuildContext context)
    : text = column.text,
      style = column.style ?? const TextStyle(),
      natural = column.naturalSizeIn(context),
      _painter = column.painterIn(context);

  @override
  final String text;

  @override
  final TextStyle style;

  @override
  final Size natural;

  final CustomPainter _painter;

  /// A column in a room it may not outgrow is clamped to it and packs its
  /// glyphs in, as the column's own box is.
  @override
  Size sizeIn(BoxConstraints constraints) => constraints.constrain(natural);

  @override
  void paint(Canvas canvas, Size size) => _painter.paint(canvas, size);

  @override
  Listenable get repaint => _painter;

  @override
  bool samePaintAs(PlateWords other) =>
      other is StoodPlateWords &&
      other.natural == natural &&
      !_painter.shouldRepaint(other._painter);

  @override
  void dispose() {}
}

/// A word laid across as one line, as a `Text` sets it ([textLineTypeIn]),
/// scaled down whole where it would not fit — the `FittedBox` it stood in.
final class LyingPlateWords extends PlateWords {
  LyingPlateWords(this.text, TextLineType type) : _type = type;

  @override
  final String text;

  final TextLineType _type;

  /// The line, laid out when first asked — a word its box already holds
  /// alike ([samePaintAs]) is let go of without ever being set.
  TextPainter get _line => _laid ??= textLineIn(text, _type)..layout();
  TextPainter? _laid;

  @override
  TextStyle get style => _type.style;

  @override
  Size get natural => _line.size;

  @override
  Size sizeIn(BoxConstraints constraints) =>
      constraints.constrainSizeAndAttemptToPreserveAspectRatio(natural);

  @override
  void paint(Canvas canvas, Size size) {
    if (natural.isEmpty) {
      return;
    }
    canvas
      ..save()
      ..scale(size.width / natural.width, size.height / natural.height);
    _line.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  Listenable? get repaint => null;

  @override
  bool samePaintAs(PlateWords other) =>
      other is LyingPlateWords && other.text == text && other._type == _type;

  @override
  void dispose() {
    _laid?.dispose();
    _letGo = true;
  }

  /// Whether its box has let go of it.
  @visibleForTesting
  bool get debugLetGo => _letGo;
  bool _letGo = false;
}

/// What a box holding [PlateWords] does with them: keeps what paints the
/// same, lets go of what it no longer holds, and hears what repaints them.
mixin _HoldsPlateWords on RenderBox {
  List<PlateWords> get _held;
  set _held(List<PlateWords> value);

  /// Holds [next] — each word that paints as the held one in its place
  /// stays the held one, already laid out — and lets go of the rest.
  void _holdWords(List<PlateWords> next) {
    final held = _held;
    final kept = [
      for (final (index, word) in next.indexed)
        if (index < held.length && held[index].samePaintAs(word))
          held[index]
        else
          word,
    ];
    _letGoOf(next, keeping: kept);
    if (kept.length == held.length &&
        kept.indexed.every((entry) => identical(entry.$2, held[entry.$1]))) {
      return;
    }
    if (attached) {
      _hear(held, hear: false);
      _hear(kept, hear: true);
    }
    _held = kept;
    _letGoOf(held, keeping: kept);
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  static void _letGoOf(
    List<PlateWords> words, {
    required List<PlateWords> keeping,
  }) {
    for (final word in words) {
      if (!keeping.any((kept) => identical(kept, word))) {
        word.dispose();
      }
    }
  }

  void _hear(List<PlateWords> words, {required bool hear}) {
    for (final word in words) {
      final repaint = word.repaint;
      if (repaint == null) {
        continue;
      }
      if (hear) {
        repaint.addListener(markNeedsPaint);
      } else {
        repaint.removeListener(markNeedsPaint);
      }
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _hear(_held, hear: true);
  }

  @override
  void detach() {
    _hear(_held, hear: false);
    super.detach();
  }

  @override
  void dispose() {
    for (final word in _held) {
      word.dispose();
    }
    super.dispose();
  }
}

/// The label plate's one box: the slot filled edge to edge with [fill], its
/// words split evenly along [axis], each stretched over its share — what a
/// `SizedBox.expand` › `ColoredBox` › `ClipRect` › `Flex` of `Expanded` ›
/// `FittedBox(fill)` laid and painted.
///
/// It says its words on the node above, as each word's own box did.
class RenderLabelPlate extends RenderBox with _HoldsPlateWords {
  RenderLabelPlate({
    required Color fill,
    required List<PlateWords> words,
    required Axis axis,
    required TextDirection? textDirection,
  }) : _fill = fill,
       _words = words,
       _axis = axis,
       _textDirection = textDirection;

  Color _fill;
  Color get fill => _fill;
  set fill(Color value) {
    if (value == _fill) {
      return;
    }
    _fill = value;
    markNeedsPaint();
  }

  List<PlateWords> _words;
  List<PlateWords> get words => _words;
  set words(List<PlateWords> value) => _holdWords(value);

  @override
  List<PlateWords> get _held => _words;
  @override
  set _held(List<PlateWords> value) => _words = value;

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis value) {
    if (value == _axis) {
      return;
    }
    _axis = value;
    markNeedsPaint();
  }

  TextDirection? _textDirection;
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsSemanticsUpdate();
  }

  @override
  bool get sizedByParent => true;

  /// The whole slot — the row's height on a horizontal rail and the
  /// header's width on the sheet's vertical one; the slot provides the
  /// other extent.
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// Where word [index] is drawn, in the plate's own box — stretched over
  /// one even share along [axis], the whole plate across it.
  ///
  /// 🚨★★★EACH COLUMN FILLS ITS OWN AREA, BOTH WAYS. 유저 2026-08-28:
  /// 「2글자로 작감이면 작감 **위 아래에 글자가 남거든**? 이거 그냥 **글자
  /// 늘려서 꽉 채우게** 하면 멋있을거같아 … **옆으로도 자기 영역 내에서 꽉
  /// 채우게** 하고싶어」.
  ///
  /// ⚠️STRETCHED to the share (`BoxFit.fill`), not scaled inside it, so two
  /// characters and four fill the same plate. That is also what makes the
  /// old 4px overflow impossible — nothing is sized by its natural extent
  /// any more.
  ///
  /// ⛔The shares are EVEN, so 공정 and 수정 own half each and neither pushes
  /// the other. With one word it takes the whole plate.
  Rect wordRectOf(int index) {
    final share = extentAlong(_axis, size) / _words.length;
    return rectAlong(
      _axis,
      along: (from: share * index, to: share * index + share),
      across: (from: 0, to: extentAcross(_axis, size)),
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    if (size > Size.zero) {
      canvas.drawRect(offset & size, Paint()..color = _fill);
    }
    if (_words.isEmpty) {
      return;
    }
    canvas
      ..save()
      ..clipRect(offset & size, doAntiAlias: false);
    for (final (index, word) in _words.indexed) {
      final drawn = wordRectOf(index);
      final natural = word.natural;
      if (drawn.isEmpty || natural.isEmpty) {
        continue;
      }
      canvas
        ..save()
        ..translate(offset.dx + drawn.left, offset.dy + drawn.top)
        ..scale(drawn.width / natural.width, drawn.height / natural.height);
      word.paint(canvas, natural);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_words.isEmpty) {
      return;
    }
    config
      ..label = [for (final word in _words) word.text].join('\n')
      ..textDirection = _textDirection;
  }
}

/// The take's one box: its word at the size it takes in the slot, in the
/// middle, cut at the slot's edge — what a `ClipRect` › `Center` around the
/// word's own box laid and painted. No ground: a take is writing on the
/// rail.
class RenderTakeText extends RenderBox with _HoldsPlateWords {
  RenderTakeText({
    required PlateWords word,
    required TextDirection? textDirection,
  }) : _word = word,
       _textDirection = textDirection;

  PlateWords _word;
  PlateWords get word => _word;
  set word(PlateWords value) => _holdWords([value]);

  @override
  List<PlateWords> get _held => [_word];
  @override
  set _held(List<PlateWords> value) => _word = value.single;

  TextDirection? _textDirection;
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsSemanticsUpdate();
  }

  /// Where the word stands in the take's box.
  Rect get wordRect => Alignment.center.inscribe(
    _word.sizeIn(constraints.loosen()),
    Offset.zero & size,
  );

  @override
  void performLayout() => size = computeDryLayout(constraints);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final word = _word.sizeIn(constraints.loosen());
    return constraints.constrain(
      Size(
        constraints.hasBoundedWidth ? double.infinity : word.width,
        constraints.hasBoundedHeight ? double.infinity : word.height,
      ),
    );
  }

  @override
  bool hitTestSelf(Offset position) => wordRect.contains(position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = wordRect;
    if (rect.isEmpty) {
      return;
    }
    context.canvas
      ..save()
      ..clipRect(offset & size, doAntiAlias: false)
      ..translate(offset.dx + rect.left, offset.dy + rect.top);
    _word.paint(context.canvas, rect.size);
    context.canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _word.text
      ..textDirection = _textDirection;
  }
}
