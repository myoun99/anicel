import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'named.dart';

/// A row's PLATE in one box: its fixed size, its ground and borders, the
/// room inside them, and the node a screen reader reads the row as — a
/// boundary that keeps its contents' nodes apart.
///
/// 🪶It was a `Container` — a sized box, a decorated box and a padding —
/// with a `Semantics` under it and a [Named] between them: six elements and
/// four render objects for every row a tab reopens (card frame-panels-
/// build-in-one-frame, 2026-10-28). It is laid out, painted, hit and read
/// as they were: the borders add to the room the contents stand off the
/// edges (as a `Container` adds its decoration's padding), and the node
/// covers the contents alone, where the `Semantics` stood.
class RowPlate extends SingleChildRenderObjectWidget implements NamesItself {
  const RowPlate({
    super.key,
    this.name,
    required this.width,
    required this.height,
    this.padding = EdgeInsets.zero,
    this.decoration,
    required this.label,
    required super.child,
  });

  @override
  final String? name;

  final double width;
  final double height;

  /// How far the contents stand off the plate's edges, inside the borders.
  final EdgeInsets padding;

  /// The ground and its borders; null paints nothing.
  final BoxDecoration? decoration;

  /// What the row's node says.
  final String label;

  EdgeInsets _insets(TextDirection? textDirection) => switch (decoration) {
    final decoration? => padding + decoration.padding.resolve(textDirection),
    null => padding,
  };

  @override
  RenderRowPlate createRenderObject(BuildContext context) {
    final textDirection = Directionality.maybeOf(context);
    return RenderRowPlate(
      extent: Size(width, height),
      insets: _insets(textDirection),
      decoration: decoration,
      configuration: createLocalImageConfiguration(context),
      label: label,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderRowPlate renderObject) {
    final textDirection = Directionality.maybeOf(context);
    renderObject
      ..extent = Size(width, height)
      ..insets = _insets(textDirection)
      ..decoration = decoration
      ..configuration = createLocalImageConfiguration(context)
      ..label = label
      ..textDirection = textDirection;
  }
}

class RenderRowPlate extends RenderShiftedBox with SemanticsAnnotationsMixin {
  RenderRowPlate({
    required Size extent,
    required EdgeInsets insets,
    required BoxDecoration? decoration,
    required ImageConfiguration configuration,
    required String label,
    required TextDirection? textDirection,
  }) : _extent = extent,
       _insets = insets,
       _decoration = decoration,
       _configuration = configuration,
       super(null) {
    // The row's [Semantics] said only these: a boundary round its own
    // node, its contents' nodes kept apart under it.
    initSemanticsAnnotations(
      properties: SemanticsProperties(label: label),
      container: true,
      explicitChildNodes: true,
      excludeSemantics: false,
      blockUserActions: false,
      localeForSubtree: null,
      textDirection: textDirection,
    );
  }

  Size get extent => _extent;
  Size _extent;
  set extent(Size value) {
    if (_extent == value) {
      return;
    }
    _extent = value;
    markNeedsLayout();
  }

  /// The padding and the borders together.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets;
  set insets(EdgeInsets value) {
    if (_insets == value) {
      return;
    }
    _insets = value;
    markNeedsLayout();
  }

  BoxDecoration? get decoration => _decoration;
  BoxDecoration? _decoration;
  BoxPainter? _painter;
  set decoration(BoxDecoration? value) {
    if (_decoration == value) {
      return;
    }
    _painter?.dispose();
    _painter = null;
    _decoration = value;
    markNeedsPaint();
  }

  ImageConfiguration get configuration => _configuration;
  ImageConfiguration _configuration;
  set configuration(ImageConfiguration value) {
    if (_configuration == value) {
      return;
    }
    _configuration = value;
    markNeedsPaint();
  }

  String get label => properties.label!;
  set label(String value) {
    if (label != value) {
      properties = SemanticsProperties(label: value);
    }
  }

  @override
  void performLayout() {
    size = constraints.constrain(_extent);
    if (child case final child?) {
      child.layout(_inner(size), parentUsesSize: true);
      (child.parentData! as BoxParentData).offset = _insets.topLeft;
    }
  }

  BoxConstraints _inner(Size size) =>
      BoxConstraints.tight(size).deflate(_insets);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(_extent);

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final inner = _inner(constraints.constrain(_extent));
    return switch (child?.getDryBaseline(inner, baseline)) {
      final distance? => distance + _insets.top,
      null => null,
    };
  }

  @override
  double computeMinIntrinsicWidth(double height) => _extent.width;

  @override
  double computeMaxIntrinsicWidth(double height) => _extent.width;

  @override
  double computeMinIntrinsicHeight(double width) => _extent.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _extent.height;

  /// The node covers the contents, as the [Semantics] round them did.
  @override
  Rect get semanticBounds => switch (child) {
    final child? => (child.parentData! as BoxParentData).offset & child.size,
    null => super.semanticBounds,
  };

  @override
  bool hitTestSelf(Offset position) =>
      _decoration?.hitTest(
        size,
        position,
        textDirection: _configuration.textDirection,
      ) ??
      false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_decoration case final decoration?) {
      (_painter ??= decoration.createBoxPainter(markNeedsPaint)).paint(
        context.canvas,
        offset,
        _configuration.copyWith(size: size),
      );
      if (decoration.isComplex) {
        context.setIsComplexHint();
      }
    }
    super.paint(context, offset);
  }

  @override
  void detach() {
    _painter?.dispose();
    _painter = null;
    super.detach();
    // As [RenderDecoratedBox]: a painter that is gone hears no change, so
    // the next paint makes a new one.
    markNeedsPaint();
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}
