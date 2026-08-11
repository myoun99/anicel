import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/drawing_guide.dart';
import '../../models/viewport_point.dart';
import '../../services/guide_geometry.dart';

/// How far from a handle, in screen pixels, a press still grabs it.
const double kGuideHandleGrabRadius = 14;

/// Handle radius in screen pixels.
const double _handleRadius = 5;

/// Rays drawn per vanishing point. Enough to read the convergence at a
/// glance, few enough that three vanishing points do not turn the canvas
/// into a solid fan.
const int _raysPerVanishingPoint = 12;

/// What a press on the guide overlay grabbed.
enum GuideHandleKind {
  /// The symmetry axis's origin, or a perspective guide's eye-level
  /// origin — dragging moves the whole guide.
  origin,

  /// The far end of the symmetry axis — dragging rotates it.
  axisAngle,

  /// A finite vanishing point.
  vanishingPoint,

  /// The eye level's far end — dragging tilts the horizon.
  eyeLevelAngle,
}

/// One grabbable point of one guide.
class GuideHandle {
  const GuideHandle({
    required this.guideId,
    required this.kind,
    required this.position,
    this.vanishingPointIndex,
  });

  final GuideId guideId;
  final GuideHandleKind kind;

  /// Canvas-space position.
  final CanvasPoint position;

  /// Which vanishing point, for [GuideHandleKind.vanishingPoint].
  final int? vanishingPointIndex;

  @override
  String toString() =>
      'GuideHandle($guideId, $kind, $position, vp: $vanishingPointIndex)';
}

/// The handles [guides] offers for editing, in the order they should be
/// hit-tested — later entries win, so the small precise ones come last.
///
/// A vanishing point at INFINITY has no position and therefore no handle:
/// a direction is not somewhere you can grab. It is edited from the tool
/// settings, which is also the only place it can be stated exactly.
List<GuideHandle> guideHandles(CutGuides guides) {
  final handles = <GuideHandle>[];
  for (final guide in guides.guides) {
    if (!guide.visible) continue;
    final shape = guide.shape;
    switch (shape) {
      case SymmetryShape():
        handles.add(
          GuideHandle(
            guideId: guide.id,
            kind: GuideHandleKind.origin,
            position: shape.axis.origin,
          ),
        );
        handles.add(
          GuideHandle(
            guideId: guide.id,
            kind: GuideHandleKind.axisAngle,
            position: _alongAxis(shape.axis, _axisHandleReach),
          ),
        );
      case PerspectiveShape():
        handles.add(
          GuideHandle(
            guideId: guide.id,
            kind: GuideHandleKind.origin,
            position: shape.eyeLevel.origin,
          ),
        );
        handles.add(
          GuideHandle(
            guideId: guide.id,
            kind: GuideHandleKind.eyeLevelAngle,
            position: _alongAxis(shape.eyeLevel, _axisHandleReach),
          ),
        );
        for (var index = 0; index < shape.vanishingPoints.length; index += 1) {
          final position = shape.vanishingPoints[index].resolve().position;
          if (position == null) continue;
          handles.add(
            GuideHandle(
              guideId: guide.id,
              kind: GuideHandleKind.vanishingPoint,
              position: position,
              vanishingPointIndex: index,
            ),
          );
        }
    }
  }
  return handles;
}

/// The handle nearest [point] within [grabRadius] CANVAS units, or null.
///
/// Later handles win ties so the precise ones (vanishing points) beat the
/// coarse ones (an origin that happens to sit under them).
GuideHandle? guideHandleAt(
  List<GuideHandle> handles,
  CanvasPoint point, {
  required double grabRadius,
}) {
  GuideHandle? best;
  var bestDistance = grabRadius * grabRadius;
  for (final handle in handles) {
    final dx = handle.position.x - point.x;
    final dy = handle.position.y - point.y;
    final distance = dx * dx + dy * dy;
    if (distance <= bestDistance) {
      bestDistance = distance;
      best = handle;
    }
  }
  return best;
}

/// How far along its own direction an axis puts its rotate handle, in
/// canvas units.
const double _axisHandleReach = 120;

CanvasPoint _alongAxis(GuideAxis axis, double distance) {
  final radians = axis.angleDegrees * math.pi / 180;
  return CanvasPoint(
    x: axis.origin.x + math.cos(radians) * distance,
    y: axis.origin.y + math.sin(radians) * distance,
  );
}

/// Draws the cut's guides over the editing canvas.
///
/// EDITING CANVAS ONLY. Guides are scaffolding for drawing, not part of the
/// picture: the playback, thumbnail and export routes never see this
/// painter, the same way a ruler never prints.
class GuideOverlayPainter extends CustomPainter {
  GuideOverlayPainter({
    required this.guides,
    required this.viewport,
    required this.canvasSize,
    required this.emphasized,
    required this.color,
    this.selectedGuideId,
  });

  final CutGuides guides;
  final CanvasViewport viewport;
  final CanvasSize canvasSize;

  /// True while the guide tool is active: the lines darken and the handles
  /// appear. Otherwise the guides stay legible but quiet — they are still
  /// steering the brush, so hiding them entirely would be a surprise.
  final bool emphasized;

  final Color color;
  final GuideId? selectedGuideId;

  Offset _toScreen(CanvasPoint point) {
    final viewportPoint = viewport.canvasToViewport(point);
    return Offset(viewportPoint.x, viewportPoint.y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    // The whole viewport, not the canvas rect: guides run off the paper on
    // purpose — a vanishing point usually sits outside it.
    final bounds = Offset.zero & size;
    for (final guide in guides.guides) {
      if (!guide.visible) continue;
      final selected = guide.id == selectedGuideId;
      final opacity = emphasized ? (selected ? 0.95 : 0.6) : 0.28;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = selected && emphasized ? 1.6 : 1.0
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final shape = guide.shape;
      switch (shape) {
        case SymmetryShape():
          _paintSymmetry(canvas, bounds, shape, paint);
        case PerspectiveShape():
          _paintPerspective(canvas, bounds, shape, paint, opacity);
      }
      if (emphasized) {
        _paintHandles(canvas, guide, opacity);
      }
    }
  }

  void _paintSymmetry(
    Canvas canvas,
    Rect bounds,
    SymmetryShape shape,
    Paint paint,
  ) {
    // The MIRROR lines are what the user positions against, so those are
    // what is drawn: one axis for the plain mirror, and the sector
    // boundaries above that. Rotational symmetry has no mirror lines at
    // all, so its spokes are drawn instead — one per copy, which is the
    // honest picture of what it does.
    final origin = shape.axis.origin;
    if (shape.lineSymmetry) {
      final axes = shape.lineCount ~/ 2;
      final step = 180 / axes;
      for (var index = 0; index < axes; index += 1) {
        _drawInfiniteLine(
          canvas,
          bounds,
          origin,
          shape.axis.angleDegrees + step * index,
          paint,
        );
      }
    } else {
      final step = 360 / shape.lineCount;
      for (var index = 0; index < shape.lineCount; index += 1) {
        _drawRay(
          canvas,
          bounds,
          origin,
          shape.axis.angleDegrees + step * index,
          paint,
        );
      }
    }
  }

  void _paintPerspective(
    Canvas canvas,
    Rect bounds,
    PerspectiveShape shape,
    Paint paint,
    double opacity,
  ) {
    if (shape.eyeLevelVisible) {
      final horizon = Paint()
        ..color = paint.color.withValues(alpha: opacity * 0.85)
        ..strokeWidth = paint.strokeWidth
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      _drawInfiniteLine(
        canvas,
        bounds,
        shape.eyeLevel.origin,
        shape.eyeLevel.angleDegrees,
        horizon,
      );
    }
    final rays = Paint()
      ..color = paint.color.withValues(alpha: opacity * 0.5)
      ..strokeWidth = paint.strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final vanishingPoint in shape.vanishingPoints) {
      _paintVanishingFan(canvas, bounds, vanishingPoint, rays);
    }
  }

  /// The fan of lines converging on one vanishing point.
  ///
  /// A finite point gets rays radiating from it; a point at infinity gets
  /// PARALLEL lines, which is exactly what it means. Both cases are read
  /// off the same `resolve()`, so a vertical family and a distant one draw
  /// through one path.
  void _paintVanishingFan(
    Canvas canvas,
    Rect bounds,
    VanishingPoint vanishingPoint,
    Paint paint,
  ) {
    final resolved = vanishingPoint.resolve();
    final diagonal = bounds.longestSide * 2;
    if (resolved.isInfinite) {
      final direction = resolved.directionFrom(
        CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
      );
      if (direction == null) return;
      final center = bounds.center;
      // Step ACROSS the family and draw one line per lane.
      final acrossX = -direction.dy;
      final acrossY = direction.dx;
      final spacing = diagonal / _raysPerVanishingPoint;
      for (var index = -_raysPerVanishingPoint;
          index <= _raysPerVanishingPoint;
          index += 1) {
        final offset = spacing * index;
        final anchor = Offset(
          center.dx + acrossX * offset,
          center.dy + acrossY * offset,
        );
        // The direction is canvas-space; take it to the screen through two
        // mapped points rather than assuming the viewport has no rotation.
        canvas.drawLine(
          anchor,
          Offset(anchor.dx + direction.dx * diagonal,
              anchor.dy + direction.dy * diagonal),
          paint,
        );
      }
      return;
    }
    final position = resolved.position;
    if (position == null) return;
    final apex = _toScreen(position);
    for (var index = 0; index < _raysPerVanishingPoint; index += 1) {
      final angle = math.pi * 2 * index / _raysPerVanishingPoint;
      canvas.drawLine(
        apex,
        Offset(
          apex.dx + math.cos(angle) * diagonal,
          apex.dy + math.sin(angle) * diagonal,
        ),
        paint,
      );
    }
  }

  void _drawInfiniteLine(
    Canvas canvas,
    Rect bounds,
    CanvasPoint origin,
    double angleDegrees,
    Paint paint,
  ) {
    final radians = angleDegrees * math.pi / 180;
    final far = bounds.longestSide * 2 / math.max(viewport.zoom, 1e-6);
    final a = _toScreen(
      CanvasPoint(
        x: origin.x - math.cos(radians) * far,
        y: origin.y - math.sin(radians) * far,
      ),
    );
    final b = _toScreen(
      CanvasPoint(
        x: origin.x + math.cos(radians) * far,
        y: origin.y + math.sin(radians) * far,
      ),
    );
    canvas.drawLine(a, b, paint);
  }

  void _drawRay(
    Canvas canvas,
    Rect bounds,
    CanvasPoint origin,
    double angleDegrees,
    Paint paint,
  ) {
    final radians = angleDegrees * math.pi / 180;
    final far = bounds.longestSide * 2 / math.max(viewport.zoom, 1e-6);
    canvas.drawLine(
      _toScreen(origin),
      _toScreen(
        CanvasPoint(
          x: origin.x + math.cos(radians) * far,
          y: origin.y + math.sin(radians) * far,
        ),
      ),
      paint,
    );
  }

  void _paintHandles(Canvas canvas, DrawingGuide guide, double opacity) {
    final fill = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final handle in guideHandles(CutGuides(guides: [guide]))) {
      final center = _toScreen(handle.position);
      canvas.drawCircle(center, _handleRadius, fill);
      canvas.drawCircle(center, _handleRadius, ring);
    }
  }

  @override
  bool shouldRepaint(GuideOverlayPainter oldDelegate) =>
      oldDelegate.guides != guides ||
      oldDelegate.viewport != viewport ||
      oldDelegate.canvasSize != canvasSize ||
      oldDelegate.emphasized != emphasized ||
      oldDelegate.color != color ||
      oldDelegate.selectedGuideId != selectedGuideId;
}

/// Applies a handle drag to [guides], returning the edited set.
///
/// Pure, so the drag layer stays a thin translator of pointer events and
/// this can be tested without one.
CutGuides dragGuideHandle(
  CutGuides guides,
  GuideHandle handle,
  CanvasPoint to,
) {
  final guide = guides.guideFor(handle.guideId);
  if (guide == null) return guides;
  final shape = guide.shape;
  GuideShape? next;
  switch (shape) {
    case SymmetryShape():
      next = switch (handle.kind) {
        GuideHandleKind.origin => shape.copyWith(
          axis: shape.axis.copyWith(origin: to),
        ),
        GuideHandleKind.axisAngle => shape.copyWith(
          axis: shape.axis.copyWith(
            angleDegrees: _angleTowards(shape.axis.origin, to),
          ),
        ),
        _ => null,
      };
    case PerspectiveShape():
      switch (handle.kind) {
        case GuideHandleKind.origin:
          next = shape.copyWith(
            eyeLevel: shape.eyeLevel.copyWith(origin: to),
          );
        case GuideHandleKind.eyeLevelAngle:
          next = shape.copyWith(
            eyeLevel: shape.eyeLevel.copyWith(
              angleDegrees: _angleTowards(shape.eyeLevel.origin, to),
            ),
          );
        case GuideHandleKind.vanishingPoint:
          final index = handle.vanishingPointIndex;
          if (index == null || index >= shape.vanishingPoints.length) {
            next = null;
            break;
          }
          // The eye-level constraint acts HERE, on the drag, rather than as
          // a sweep over stored geometry — see
          // [constrainedVanishingPointTarget].
          final landing = constrainedVanishingPointTarget(shape, to);
          final points = [...shape.vanishingPoints];
          points[index] = VanishingPointAt(landing);
          next = shape.copyWith(vanishingPoints: points);
        case GuideHandleKind.axisAngle:
          next = null;
      }
  }
  if (next == null) return guides;
  return guides.copyWith(
    guides: [
      for (final entry in guides.guides)
        if (entry.id == handle.guideId) entry.copyWith(shape: next) else entry,
    ],
  );
}

/// The pointer layer that edits guides — mounted ONLY while the guide tool
/// is active, so it never stands between the brush and the canvas.
///
/// It is a thin translator: it turns a press into a handle, a move into
/// [dragGuideHandle], and a release into one commit. The edited value is
/// carried in the callbacks rather than read back out of this State at
/// release time — a drag whose commit value lives in the host's State is
/// how a release silently does nothing.
class GuideEditLayer extends StatefulWidget {
  const GuideEditLayer({
    super.key,
    required this.guides,
    required this.viewport,
    required this.onGuidesChanged,
    required this.onGuidesCommitted,
    this.onGuideSelected,
  });

  final CutGuides guides;
  final CanvasViewport viewport;

  /// Live, per pointer sample — the guide follows the finger.
  final ValueChanged<CutGuides> onGuidesChanged;

  /// Once, at release: the value that goes through the undoable command.
  final ValueChanged<CutGuides> onGuidesCommitted;

  /// A press that grabbed a handle also selects that guide, so the tool
  /// settings follow what the hand is on.
  final ValueChanged<GuideId>? onGuideSelected;

  @override
  State<GuideEditLayer> createState() => _GuideEditLayerState();
}

class _GuideEditLayerState extends State<GuideEditLayer> {
  GuideHandle? _dragging;
  int? _pointer;
  CutGuides? _live;

  CanvasPoint _canvasPoint(Offset local) => widget.viewport.viewportToCanvas(
    ViewportPoint(x: local.dx, y: local.dy),
  );

  void _end() {
    final live = _live;
    if (live != null) {
      widget.onGuidesCommitted(live);
    }
    setState(() {
      _dragging = null;
      _pointer = null;
      _live = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_pointer != null) return;
        final point = _canvasPoint(event.localPosition);
        final handle = guideHandleAt(
          guideHandles(widget.guides),
          point,
          // The grab radius is a SCREEN distance: a handle stays as easy to
          // hit zoomed out as zoomed in.
          grabRadius: kGuideHandleGrabRadius / widget.viewport.zoom,
        );
        if (handle == null) return;
        setState(() {
          _dragging = handle;
          _pointer = event.pointer;
          _live = widget.guides;
        });
        widget.onGuideSelected?.call(handle.guideId);
      },
      onPointerMove: (event) {
        final handle = _dragging;
        if (handle == null || event.pointer != _pointer) return;
        final next = dragGuideHandle(
          _live ?? widget.guides,
          handle,
          _canvasPoint(event.localPosition),
        );
        _live = next;
        widget.onGuidesChanged(next);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _end();
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointer) return;
        _end();
      },
    );
  }
}

double _angleTowards(CanvasPoint origin, CanvasPoint target) {
  final dx = target.x - origin.x;
  final dy = target.y - origin.y;
  if (dx == 0 && dy == 0) return 0;
  return math.atan2(dy, dx) * 180 / math.pi;
}
