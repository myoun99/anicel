import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A LINE OF WORDS A TICK CHANGES — the frame counter's numbers — that
/// hears the tick itself, and paints itself alone while it keeps its size.
///
/// 🚨I-57 (10-14): the counter was two `Text`s a listener built again at
/// every frame played, and both halves of that cost the whole command bar.
/// A build inside a tick layer lays the layer out — its LayoutBuilder is
/// the scope the build runs in — and a new paragraph lays its parents out
/// besides: the bar was laid out and painted at every frame (🔬24 render
/// objects, the counter's own lines two of them). This line is built once.
/// It hears [ticks] itself and sets [words] again against the room it was
/// laid out in: only words that change its size ask for a layout, and it
/// is a boundary of its own — the rest is a paint of it alone, and a
/// description of it alone.
///
/// Set as a `Text` sets one line: over the ambient [DefaultTextStyle], at
/// the context's text scale, in its direction and locale.
class TickText extends LeafRenderObjectWidget {
  const TickText({
    super.key,
    this.ticks,
    required this.words,
    required this.style,
  });

  /// What changes the words — heard by the line, never by a build. Null
  /// for words only a build changes.
  final Listenable? ticks;

  /// The words as they read now: asked when [ticks] ticks, and when the
  /// line is built.
  final String Function() words;

  /// Their type, over the ambient [DefaultTextStyle] as a `Text`'s is.
  final TextStyle style;

  @override
  RenderTickText createRenderObject(BuildContext context) =>
      RenderTickText(ticks: ticks, words: words, type: _typeIn(context));

  @override
  void updateRenderObject(BuildContext context, RenderTickText renderObject) {
    renderObject
      ..type = _typeIn(context)
      ..ticks = ticks
      ..words = words;
  }

  /// What a `Text` of [style] would be set in here.
  TickTextType _typeIn(BuildContext context) {
    final ambient = DefaultTextStyle.of(context);
    var style = ambient.style.merge(this.style);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return (
      style: style,
      scaler: MediaQuery.textScalerOf(context),
      direction: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
      heightBehavior:
          ambient.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
    );
  }
}

/// Everything a [RenderTickText] sets its words in — equal while nothing
/// that sets them would change.
typedef TickTextType = ({
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
  Locale? locale,
  TextHeightBehavior? heightBehavior,
});

/// The render object of [TickText].
class RenderTickText extends RenderBox {
  RenderTickText({
    Listenable? ticks,
    required String Function() words,
    required TickTextType type,
  }) : _ticks = ticks,
       _words = words,
       _type = type,
       _data = words() {
    _line = TextPainter(
      text: TextSpan(text: _data, style: type.style),
      textScaler: type.scaler,
      textDirection: type.direction,
      locale: type.locale,
      textHeightBehavior: type.heightBehavior,
    );
  }

  late final TextPainter _line;

  /// The words as the line reads them now.
  String get data => _data;
  String _data;

  Listenable? _ticks;
  Listenable? get ticks => _ticks;
  set ticks(Listenable? value) {
    if (identical(value, _ticks)) {
      return;
    }
    if (attached) {
      _ticks?.removeListener(_heard);
      value?.addListener(_heard);
    }
    _ticks = value;
  }

  String Function() _words;
  String Function() get words => _words;
  set words(String Function() value) {
    _words = value;
    // A build may read them anew — another notation, another rate.
    _heard();
  }

  void _heard() {
    final data = _words();
    if (data == _data) {
      return;
    }
    _data = data;
    _line.text = TextSpan(text: data, style: _type.style);
    markNeedsSemanticsUpdate();
    if (!hasSize) {
      markNeedsLayout();
      return;
    }
    // Set against the room it was last laid out in: the same size is a
    // paint, any other a layout. A layout already owed still runs.
    _line.layout();
    if (constraints.constrain(_line.size) == size) {
      markNeedsPaint();
    } else {
      markNeedsLayout();
    }
  }

  TickTextType _type;
  TickTextType get type => _type;
  set type(TickTextType value) {
    if (value == _type) {
      return;
    }
    _type = value;
    _line
      ..text = TextSpan(text: _data, style: value.style)
      ..textScaler = value.scaler
      ..textDirection = value.direction
      ..locale = value.locale
      ..textHeightBehavior = value.heightBehavior;
    markNeedsSemanticsUpdate();
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // ⛔Nothing to catch up on: a line is away only inside the build that
    // moves it, and no tick lands in a build (mutation, I-57 10-14).
    _ticks?.addListener(_heard);
  }

  @override
  void detach() {
    _ticks?.removeListener(_heard);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  Size _laidOutIn(BoxConstraints constraints) {
    _line.layout();
    return constraints.constrain(_line.size);
  }

  @override
  void performLayout() => size = _laidOutIn(constraints);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _laidOutIn(constraints);

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    _line.layout();
    return _line.width;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    _line.layout();
    return _line.height;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    _line.layout();
    return _line.computeDistanceToActualBaseline(baseline);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    // A room narrower than the line cuts it, as a `Text`'s clip does.
    final cut = _line.width > size.width || _line.height > size.height;
    if (cut) {
      canvas
        ..save()
        ..clipRect(offset & size);
    }
    _line.paint(canvas, offset);
    if (cut) {
      canvas.restore();
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _data
      ..textDirection = _type.direction;
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }
}
