import 'dart:math' as math;
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/material.dart';

import '../../models/brush_stamp_image.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_piece.dart';
import '../../models/drawing_guide.dart';
import '../../services/guide_geometry.dart';
import '../../models/app_input_settings.dart';
import '../export/offscreen_raster.dart' show rasterizeOffscreen;
import '../repaint_props.dart';
import 'canvas_viewport_offset.dart';

/// How far from a handle, in screen pixels, a press still grabs it.
const double kGuideHandleGrabRadius = 14;

/// Screen pixels between a guide's name and the point it names — clear of
/// the handle that sits there, so the two never overlap.
const double _nameGap = 12;

/// Handle radius in screen pixels.
const double _handleRadius = 5;

/// What a press on the guide overlay grabbed.
enum GuideHandleKind {
  /// The symmetry axis's origin, or a perspective guide's eye-level
  /// origin — dragging slides that line.
  ///
  /// It moves the whole guide while the perspective's
  /// `constrainToEyeLevel` is on, because the vanishing points ride the
  /// horizon then; with it off the horizon slides alone. See
  /// `movedEyeLevel`.
  origin,

  /// The far end of the symmetry axis — dragging rotates it.
  axisAngle,

  /// A finite vanishing point.
  vanishingPoint,

  /// The eye level's far end — dragging tilts the horizon.
  eyeLevelAngle,

  /// A family at infinity's way, on a stem from the eye level's handle —
  /// dragging turns the family about it (vanishing-point-types-Q3).
  parallelDirection,
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

  /// Which vanishing point, for [GuideHandleKind.vanishingPoint] and
  /// [GuideHandleKind.parallelDirection].
  final int? vanishingPointIndex;

  @override
  String toString() =>
      'GuideHandle($guideId, $kind, $position, vp: $vanishingPointIndex)';
}

/// The handles [guides] offers for editing, in the order they should be
/// hit-tested — later entries win, so the small precise ones come last.
///
/// A family at infinity has no position: its handle is its WAY's, on a stem
/// from the eye level's handle ([GuideHandleKind.parallelDirection]) — the
/// same value the panel's angle cell writes. 🗣️vanishing-point-types-Q3
/// (유저 2026-10-16): 「둘 다 — 손잡이로 대충, 각도 칸으로 정확히」.
/// ↩️It had none until then: 「a direction is not somewhere you can grab」
/// was my call when the tool was built (08-12), with no word of the user's
/// behind it, while the settings held only 「정확히 수직으로」 to state one.
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
            position: alongAxis(shape.axis, _axisHandleReach),
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
            position: alongAxis(shape.eyeLevel, _axisHandleReach),
          ),
        );
        handles.addAll(_pointHandles(guide.id, shape));
    }
  }
  return handles;
}

/// A perspective's handle for each of its points: where a point stands, and
/// a family at infinity's way ([_parallelHandleAt]). A family two drawn
/// lines name has neither — its lines say its way.
Iterable<GuideHandle> _pointHandles(
  GuideId guideId,
  PerspectiveShape shape,
) sync* {
  for (var index = 0; index < shape.vanishingPoints.length; index += 1) {
    final point = shape.vanishingPoints[index];
    final (kind, position) = switch (point) {
      VanishingPointTowards() => (
        GuideHandleKind.parallelDirection,
        _parallelHandleAt(shape.eyeLevel, point),
      ),
      _ => (GuideHandleKind.vanishingPoint, point.resolve().position),
    };
    if (position == null) continue;
    yield GuideHandle(
      guideId: guideId,
      kind: kind,
      position: position,
      vanishingPointIndex: index,
    );
  }
}

/// Where a family at infinity's handle stands: [_parallelHandleReach] along
/// its way from the eye level's handle, which it turns about.
CanvasPoint? _parallelHandleAt(GuideAxis eyeLevel, VanishingPoint point) {
  final origin = eyeLevel.origin;
  final way = point.resolve().directionFrom(origin);
  if (way == null) return null;
  return CanvasPoint(
    x: origin.x + way.dx * _parallelHandleReach,
    y: origin.y + way.dy * _parallelHandleReach,
  );
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

/// How far from the eye level's handle a family at infinity's handle
/// stands, in canvas units — past the eye level's own turning handle, so a
/// level family's two never sit on one another. The approved picture's
/// (vanishing-point-types-Q3).
const double _parallelHandleReach = 220;

/// Draws the cut's guides over the editing canvas.
///
/// EDITING CANVAS ONLY. Guides are scaffolding for drawing, not part of the
/// picture: the playback, thumbnail and export routes never see this
/// painter, the same way a ruler never prints.
class GuideOverlayPainter extends CustomPainter with RepaintOnProps {
  GuideOverlayPainter({
    required this.guides,
    required this.viewport,
    required this.canvasSize,
    required this.emphasized,
    required this.color,
    required this.face,
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

  /// The app's face the guides' names are set in (`appFaceOf`) — set from
  /// scratch they named none and wrote in the OS's font (「앱은 한 글꼴」,
  /// 08-28).
  final TextStyle face;

  /// What a vanishing point is CALLED, without its number — 「소실점」.
  ///
  /// 유저 (guide-sym): 「퍼스자는 **퍼스자의 이름말고 소실점 이름**을 각 소실점
  /// 위 중앙정렬로 표시」, and a vanishing point has no name of its own: the
  /// panel calls it `${strings.guideVanishingPoint} ${index + 1}`. The
  /// overlay says the SAME words, so 「소실점 2」 on the canvas is the row the
  /// user is looking at in the panel.
  ///
  /// ⚠️Passed in rather than read from `AppText` here: a painter that
  /// reaches for a global cannot say in [props] that the language
  /// changed, and the names would sit in the old tongue until something
  /// else moved.
  final String vanishingPointLabel;

  final GuideId? selectedGuideId;

  Offset _toScreen(CanvasPoint point) => viewport.canvasToViewportOffset(point);

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    // The whole viewport, not the canvas rect: guides run off the paper on
    // purpose — a vanishing point usually sits outside it.
    final bounds = Offset.zero & size;
    for (final guide in guides.guides) {
      if (!guide.visible) continue;
      final opacity = _opacityOf(guide);
      _paintLines(canvas, bounds, guide, opacity);
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

  /// [guide]'s LINES over [size], as [paint] draws them — no handle, no
  /// name: what 래스터라이즈 bakes ([guideLinesOnPaper]).
  void paintLines(Canvas canvas, Size size, DrawingGuide guide) =>
      _paintLines(canvas, Offset.zero & size, guide, _opacityOf(guide));

  double _opacityOf(DrawingGuide guide) =>
      emphasized ? (guide.id == selectedGuideId ? 0.95 : 0.6) : 0.28;

  double _weightOf(DrawingGuide guide) =>
      emphasized && guide.id == selectedGuideId ? 1.6 : 1.0;

  void _paintLines(
    Canvas canvas,
    Rect bounds,
    DrawingGuide guide,
    double opacity,
  ) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = _weightOf(guide)
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final shape = guide.shape;
    switch (shape) {
      case SymmetryShape():
        _paintSymmetry(canvas, bounds, shape, paint);
      case PerspectiveShape():
        _paintPerspective(canvas, bounds, shape, paint, opacity);
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
        style: face.copyWith(
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
      _paintVanishingFan(
        canvas,
        bounds,
        vanishingPoint,
        rays,
        shape.lineDensity,
      );
    }
  }

  /// The fan of [lines] lines converging on one vanishing point — the
  /// guide's [PerspectiveShape.lineDensity].
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
    int lines,
  ) {
    final resolved = vanishingPoint.resolve();
    if (resolved.isInfinite) {
      _paintParallelFamily(canvas, bounds, resolved, paint, lines);
      return;
    }
    final position = resolved.position;
    if (position == null) return;
    final diagonal = bounds.longestSide * 2;
    final apex = _toScreen(position);
    for (var index = 0; index < lines; index += 1) {
      final angle = math.pi * 2 * index / lines;
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

  /// A point at infinity's family: one line through the middle of the view
  /// and [lines] either side of it, a 1/[lines] of twice the view's long
  /// side apart, all running [resolved]'s way — the density a finite
  /// point's rays are drawn at sets how close its parallels stand
  /// (vanishing-point-types-Q4).
  void _paintParallelFamily(
    Canvas canvas,
    Rect bounds,
    HomogeneousPoint resolved,
    Paint paint,
    int lines,
  ) {
    final middle = CanvasPoint(
      x: canvasSize.width / 2,
      y: canvasSize.height / 2,
    );
    final direction = resolved.directionFrom(middle);
    if (direction == null) return;
    // 🚨THE DIRECTION IS THE CANVAS'S, THE LINES ARE THE SCREEN'S
    // (vanishing-point-types, 2026-10-16). It is taken to the screen
    // through two mapped points, so a turned or mirrored view turns the
    // family with the paper — this comment said so from 08-12 while the
    // canvas direction was drawn on the screen as it was, and a turned
    // view left the family standing still.
    final along =
        _toScreen(
          CanvasPoint(
            x: middle.x + direction.dx,
            y: middle.y + direction.dy,
          ),
        ) -
        _toScreen(middle);
    if (along.distance == 0) return;
    final ahead = along / along.distance;
    final center = bounds.center;
    final diagonal = bounds.longestSide * 2;
    // Step ACROSS the family and draw one line per lane.
    final spacing = diagonal / lines;
    for (var index = -lines; index <= lines; index += 1) {
      final offset = spacing * index;
      final anchor = center + Offset(-ahead.dy, ahead.dx) * offset;
      // 🚨A LINE, BOTH WAYS FROM ITS ANCHOR (same card, same day). The
      // anchors stand on the line through the view's middle, and each line
      // used to leave its anchor one way only — 「정확히 수직으로」 drew its
      // verticals below the middle of the view alone, most of them under
      // the timeline. A point at infinity is parallel LINES; only a finite
      // point's are rays.
      canvas.drawLine(
        anchor - ahead * diagonal,
        anchor + ahead * diagonal,
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
    final handles = guideHandles(CutGuides(guides: [guide]));
    _paintParallelStems(canvas, guide, handles, opacity);
    for (final handle in handles) {
      final center = _toScreen(handle.position);
      canvas.drawCircle(center, _handleRadius, fill);
      canvas.drawCircle(center, _handleRadius, ring);
    }
  }

  /// The stem each family at infinity's handle hangs on, from the eye
  /// level's handle it turns about — part of the handle, so drawn with the
  /// handles, never baked (the approved picture of
  /// vanishing-point-types-Q3: twice the line's weight).
  void _paintParallelStems(
    Canvas canvas,
    DrawingGuide guide,
    List<GuideHandle> handles,
    double opacity,
  ) {
    final shape = guide.shape;
    if (shape is! PerspectiveShape) return;
    final stem = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = _weightOf(guide) * 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final origin = _toScreen(shape.eyeLevel.origin);
    for (final handle in handles) {
      if (handle.kind == GuideHandleKind.parallelDirection) {
        canvas.drawLine(origin, _toScreen(handle.position), stem);
      }
    }
  }

  @override
  Object get props => (
    guides,
    viewport,
    canvasSize,
    emphasized,
    color,
    face,
    vanishingPointLabel,
    selectedGuideId,
  );
}

/// The colour the guides are drawn in — what the canvas's overlay paints
/// with, and what 래스터라이즈 bakes with, read in one place.
Color guideColorOf(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// [guide]'s lines on [canvasSize]'s paper, a canvas pixel to a pixel, as
/// the canvas draws them while the guide tool holds it picked: its colour,
/// its weight, its density, its eye level — no handle, no name. The
/// picture 래스터라이즈 lands. Null when the picture cannot be read back.
///
/// 🗣️vanishing-point-types-Q6 (유저 2026-10-16): 「화면에 보이는 그대로」 —
/// 「가이드와 같은 색 · 굵기 · 밀도, 아이레벨 선도 포함 — 용지 안만」.
/// ⚠️At 100%, unturned: the paper is the view it is drawn in, so a family at
/// infinity stands its lanes across the paper as the canvas would at 100%
/// — my reading of 「보이는 그대로」, not a word of the user's.
Future<CutPiece?> guideLinesOnPaper(
  DrawingGuide guide, {
  required CanvasSize canvasSize,
  required Color color,
}) async {
  final paper = Size(
    canvasSize.width.toDouble(),
    canvasSize.height.toDouble(),
  );
  final image = await rasterizeOffscreen(
    width: canvasSize.width,
    height: canvasSize.height,
    paint: (canvas) => GuideOverlayPainter(
      guides: CutGuides(guides: [guide]),
      viewport: CanvasViewport(),
      canvasSize: canvasSize,
      emphasized: true,
      color: color,
      face: const TextStyle(),
      vanishingPointLabel: '',
      selectedGuideId: guide.id,
    ).paintLines(canvas, paper, guide),
  );
  try {
    final rgba = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (rgba == null) {
      return null;
    }
    return CutPiece(
      image: BrushStampImage(
        id: 'guide-${guide.id.value}-${DateTime.now().microsecondsSinceEpoch}',
        width: canvasSize.width,
        height: canvasSize.height,
        rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      ),
      originLeft: 0,
      originTop: 0,
    );
  } finally {
    image.dispose();
  }
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
        // Both eye-level handles go through [movedEyeLevel], which is where
        // the constraint decides whether the vanishing points come along —
        // 유저: 「로직부터 통일」. Sliding and tilting are two ways to move ONE
        // line, so they must not each hold an opinion about it.
        case GuideHandleKind.origin:
          next = movedEyeLevel(shape, shape.eyeLevel.copyWith(origin: to));
        case GuideHandleKind.eyeLevelAngle:
          next = movedEyeLevel(
            shape,
            shape.eyeLevel.copyWith(
              angleDegrees: _angleTowards(shape.eyeLevel.origin, to),
            ),
          );
        case GuideHandleKind.vanishingPoint:
          // The eye-level constraint acts HERE, on the drag, rather than as
          // a sweep over stored geometry — see
          // [constrainedVanishingPointTarget].
          next = _withPointAt(
            shape,
            handle.vanishingPointIndex,
            VanishingPointAt(constrainedVanishingPointTarget(shape, to)),
          );
        case GuideHandleKind.parallelDirection:
          // The way from the eye level's handle to the hand. ⛔Not held to
          // the eye level: that binds where a point STANDS, and a family
          // held to it could never be the vertical one
          // (vanishing-point-types-Q3: 「세로 퍼스는 항상 수직」 is a 90 in
          // the angle cell this handle writes too).
          final way = HomogeneousPoint.at(
            to.x,
            to.y,
          ).directionFrom(shape.eyeLevel.origin);
          next = way == null
              ? null
              : _withPointAt(
                  shape,
                  handle.vanishingPointIndex,
                  VanishingPointTowards(dx: way.dx, dy: way.dy),
                );
        case GuideHandleKind.axisAngle:
          next = null;
      }
  }
  if (next == null) return guides;
  return guides.replacing(guide.copyWith(shape: next));
}

/// [shape] with its point at [index] standing as [point] — null for an
/// index the shape holds no point at.
PerspectiveShape? _withPointAt(
  PerspectiveShape shape,
  int? index,
  VanishingPoint point,
) => index == null || index >= shape.vanishingPoints.length
    ? null
    : shape.withVanishingPoint(index, point);

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

  CanvasPoint _canvasPoint(Offset local) =>
      widget.viewport.viewportOffsetToCanvas(local);

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
