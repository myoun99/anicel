import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/drawing_guide.dart';
import '../../models/viewport_point.dart';
import '../../services/guide_geometry.dart';
import '../input/app_input_settings.dart';

/// How far from a handle, in screen pixels, a press still grabs it.
const double kGuideHandleGrabRadius = 14;

/// Screen pixels between a guide's name and the point it names — clear of
/// the handle that sits there, so the two never overlap.
const double _nameGap = 12;

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
    required this.vanishingPointLabel,
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

  /// What a vanishing point is CALLED, without its number — 「소실점」.
  ///
  /// 유저 (guide-sym): 「퍼스자는 **퍼스자의 이름말고 소실점 이름**을 각 소실점
  /// 위 중앙정렬로 표시」, and a vanishing point has no name of its own: the
  /// panel calls it `${strings.guideVanishingPoint} ${index + 1}`. The
  /// overlay says the SAME words, so 「소실점 2」 on the canvas is the row the
  /// user is looking at in the panel.
  ///
  /// ⚠️Passed in rather than read from `AppText` here: a painter that
  /// reaches for a global cannot say in [shouldRepaint] that the language
  /// changed, and the names would sit in the old tongue until something
  /// else moved.
  final String vanishingPointLabel;

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
        // 🚨THE NAMES, and only while the guide tool is out (유저: 「이름표시는
        // 가이드툴이 선택됬을때, 그리고 물론 결과적으로 비지블 on으로 했을때만
        // 표시」). The `visible` half is the `continue` at the top of this
        // loop, so both conditions are the loop's own.
        _paintNames(canvas, bounds, guide, opacity);
      }
    }
  }

  /// The guide's name where the user can read it against the drawing.
  ///
  /// 유저 (guide-sym): 「대칭자같은건 **중앙포인트 위에 중앙정렬**로 해당 자의
  /// 이름(대칭 2)표시. 퍼스자는 퍼스자의 이름말고 **소실점 이름**을 각 소실점
  /// 위 중앙정렬로 표시」 — so a symmetry says ITS name once, and a
  /// perspective says nothing about itself and names each point instead.
  void _paintNames(Canvas canvas, Rect bounds, DrawingGuide guide, double a) {
    switch (guide.shape) {
      case SymmetryShape(:final axis):
        _paintNameAbove(canvas, bounds, _toScreen(axis.origin), guide.name, a);
      case PerspectiveShape(:final vanishingPoints):
        for (var i = 0; i < vanishingPoints.length; i += 1) {
          final at = vanishingPoints[i].resolve().position;
          // ⛔A point at INFINITY has nowhere to be centred above — its
          // family is a set of parallels with no meeting place on any
          // screen. Skipped rather than parked at an edge, which would be a
          // position I chose and the user did not.
          if (at == null) {
            continue;
          }
          _paintNameAbove(
            canvas,
            bounds,
            _toScreen(at),
            '$vanishingPointLabel ${i + 1}',
            a,
          );
        }
    }
  }

  /// One name, centred on [at] and sitting above it.
  ///
  /// ⚠️A SCREEN size, like [kGuideHandleGrabRadius] one file over: a name is
  /// for reading, so it stays the same size zoomed in and out rather than
  /// growing into the artwork.
  void _paintNameAbove(
    Canvas canvas,
    Rect bounds,
    Offset at,
    String text,
    double opacity,
  ) {
    if (text.isEmpty) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: 11,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final origin = Offset(
      at.dx - painter.width / 2,
      at.dy - painter.height - _nameGap,
    );
    // Off-screen names cost a raster and say nothing — a vanishing point
    // usually sits well outside the paper.
    if (!bounds.overlaps(origin & painter.size)) {
      painter.dispose();
      return;
    }
    painter.paint(canvas, origin);
    painter.dispose();
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
      oldDelegate.vanishingPointLabel != vanishingPointLabel ||
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
/// is active, and while it is, IT OWNS THE CANVAS.
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
      // 🚨★★★OPAQUE — 유저 (guide-sym): 「가이드툴이 선택된 상태로 **그림이
      // 그려짐**」.
      //
      // ⛔Translucent meant a press that grabbed no handle fell through to
      // the stroke pipeline in the Stack below, so the guide tool drew.
      // ★The law the rest of the canvas already keeps: the tool in hand
      // owns the canvas. The selection tools mount the interaction layer,
      // the eyedropper and the fill mount `canvas-tool-tap-layer` (opaque,
      // "so no stroke starts"); this layer was the one exception.
      //
      // ⚠️This hides only what is BELOW it in that Stack. Panning, zooming
      // and the flip live in `CanvasViewportGestureLayer`, an ANCESTOR, and
      // an opaque sibling never hides an ancestor — so navigation over the
      // paper keeps working with the guide tool out. I had recorded the
      // opposite as a reason not to do this; the test next door now asserts
      // the ancestor still hears every press.
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_pointer != null) return;
        // TS9: same door as every other tool input layer — a finger is
        // navigating unless the one-finger slot says draw.
        if (!AppInput.toolAcceptsPointer(event.kind)) return;
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
