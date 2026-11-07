import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_transforms.dart';

/// A shape as it was painted: the outline it covers on the canvas, and its
/// paint.
typedef DrawnShape = ({Path outline, Paint paint});

/// A canvas that keeps every path and rectangle painted on it as the outline
/// it covers — the rectangle through the transform it was drawn in.
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q9 (유저 2026-11-08, 2): a key mark
/// the engine fills exactly — a diamond, a held key's box — is drawn as a
/// rectangle turned and stretched (`paintKeyMark`), every other as a path.
/// What a mark looks like is the shape it covers, whichever call covered
/// it — so that is what a test reads.
class DrawnShapes extends CanvasTransforms {
  final shapes = <DrawnShape>[];

  @override
  void drawPath(Path path, Paint paint) =>
      shapes.add((outline: path.transform(current.storage), paint: paint));

  @override
  void drawRect(Rect rect, Paint paint) => shapes.add((
    outline: (Path()..addRect(rect)).transform(current.storage),
    paint: paint,
  ));

  /// The shapes [object] paints, in order — its children's too.
  static List<DrawnShape> of(RenderObject object) {
    final canvas = DrawnShapes();
    object.paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas.shapes;
  }
}

/// Matches a render object — or the one a finder finds — that paints a
/// shape of [color] and [style] whose outline covers every point of
/// [includes] and none of [excludes].
Matcher paintsShape({
  Color? color,
  PaintingStyle style = PaintingStyle.fill,
  List<Offset> includes = const [],
  List<Offset> excludes = const [],
}) => _PaintsShape(color, style, includes, excludes);

class _PaintsShape extends Matcher {
  const _PaintsShape(this.color, this.style, this.includes, this.excludes);

  final Color? color;
  final PaintingStyle style;
  final List<Offset> includes;
  final List<Offset> excludes;

  // A paint keeps its colour in 32-bit floats: it is read back to the
  // nearest of 8 bits, as `paints` reads it.
  bool _isIt(DrawnShape shape) =>
      shape.paint.style == style &&
      (color == null ||
          isSameColorAs(color!).matches(shape.paint.color, {})) &&
      includes.every(shape.outline.contains) &&
      !excludes.any(shape.outline.contains);

  static RenderObject? _objectOf(Object? item) => switch (item) {
    RenderObject() => item,
    Finder() => item.evaluate().single.renderObject,
    _ => null,
  };

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final object = _objectOf(item);
    return object != null && DrawnShapes.of(object).any(_isIt);
  }

  @override
  Description describe(Description description) => description.add(
    'paints a ${style.name} shape${color == null ? '' : ' of $color'} '
    'covering $includes and none of $excludes',
  );

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) => switch (_objectOf(item)) {
    final object? => mismatchDescription.add(
      'painted ${DrawnShapes.of(object).map(_said)}',
    ),
    null => mismatchDescription.add('is no render object, nor finds one'),
  };

  static String _said(DrawnShape shape) =>
      '${shape.paint.style.name} ${shape.paint.color} over '
      '${shape.outline.getBounds()}';
}
