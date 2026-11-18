import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_transforms.dart';

/// A shape as it was painted: the outline it covers on the canvas, and its
/// paint.
typedef DrawnShape = ({Path outline, Paint paint});

/// A canvas that keeps every path, rectangle and superellipse painted on it
/// as the outline it covers — through the transform it was drawn in, and
/// within the rectangles it was cut to.
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q9 (유저 2026-11-08, 2): a key mark
/// the engine fills exactly — a diamond, a held key's box — is drawn as a
/// rectangle turned and stretched (`paintKeyMark`), every other as a path.
/// What a mark looks like is the shape it covers, whichever call covered
/// it — so that is what a test reads.
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2): what
/// reaches a still region's corner is the region's shape cut by a
/// rectangle (`drawRSuperellipseCut`) — a bar's fill, a grip's band — so
/// the cut is part of what it covers too.
class DrawnShapes extends CanvasTransforms {
  final shapes = <DrawnShape>[];

  /// The rectangles the canvas is cut to now, each with how it cuts.
  var _cuts = <(PathOperation, Path)>[];
  final _savedCuts = <List<(PathOperation, Path)>>[];

  @override
  void save() {
    super.save();
    _savedCuts.add(_cuts);
  }

  @override
  void restore() {
    super.restore();
    _cuts = _savedCuts.removeLast();
  }

  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _cuts = [
    ..._cuts,
    (
      clipOp == ClipOp.intersect
          ? PathOperation.intersect
          : PathOperation.difference,
      (Path()..addRect(rect)).transform(current.storage),
    ),
  ];

  void _add(Path drawn, Paint paint) {
    var outline = drawn.transform(current.storage);
    for (final (operation, cut) in _cuts) {
      outline = Path.combine(operation, outline, cut);
    }
    shapes.add((outline: outline, paint: paint));
  }

  @override
  void drawPath(Path path, Paint paint) => _add(path, paint);

  @override
  void drawRect(Rect rect, Paint paint) => _add(Path()..addRect(rect), paint);

  @override
  void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint) =>
      _add(Path()..addRSuperellipse(rsuperellipse), paint);

  /// The shapes [object] paints, in order — its children's too.
  static List<DrawnShape> of(RenderObject object) {
    final canvas = DrawnShapes();
    object.paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas.shapes;
  }

  /// The shapes [paint] paints on a canvas, in order.
  static List<DrawnShape> by(void Function(Canvas canvas) paint) {
    final canvas = DrawnShapes();
    paint(canvas);
    return canvas.shapes;
  }
}

/// Matches a render object — or the one a finder finds, or a function
/// painting on a canvas, as `paints` takes — that paints a shape of
/// [color] and [style] whose outline covers every point of [includes] and
/// none of [excludes].
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

  static List<DrawnShape>? _shapesOf(Object? item) => switch (item) {
    RenderObject() => DrawnShapes.of(item),
    Finder() => DrawnShapes.of(item.evaluate().single.renderObject!),
    final void Function(Canvas) paint => DrawnShapes.by(paint),
    _ => null,
  };

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      _shapesOf(item)?.any(_isIt) ?? false;

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
  ) => switch (_shapesOf(item)) {
    final shapes? => mismatchDescription.add('painted ${shapes.map(_said)}'),
    null => mismatchDescription.add(
      'is no render object, nor finds one, nor paints',
    ),
  };

  static String _said(DrawnShape shape) =>
      '${shape.paint.style.name} ${shape.paint.color} over '
      '${shape.outline.getBounds()}';
}
