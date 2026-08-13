import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';

/// The Ctrl+T box chrome in viewport space: the transformed box outline,
/// the scale handles and the rotate knob (null in QUAD mode — a free
/// quadrilateral has no rotation lever).
typedef SelectionTransformChrome = ({
  List<Offset> box,
  List<Offset> handles,
  Offset? knob,
});

/// Marching ants: dashed outlines whose dash phase rides the animation.
///
/// R28-S: extracted from the selection layer so the SAME ants can be
/// painted under every tool. The selection is a document fact, not a
/// selection-tool decoration — with the brush armed the user still has to
/// see where paint will land (R26 #18).
class SelectionAntsPainter extends CustomPainter {
  SelectionAntsPainter({
    required Animation<double> repaint,
    required this.viewport,
    required this.committedRegion,
    required this.screenOffset,
    required this.marqueeShape,
    required this.openTrail,
    this.closeTarget,
    this.closeTargetArmed = true,
    this.cursor,
    this.transformChrome,
    this.movePendingDirty = false,
  }) : _phase = repaint,
       super(
         repaint: cursor == null
             ? repaint
             : Listenable.merge(<Listenable>[repaint, cursor]),
       );

  final Animation<double> _phase;
  final CanvasViewport viewport;

  /// The committed selection — its composite outline is the ants.
  final CanvasSelectionRegion? committedRegion;
  final Offset screenOffset;

  /// The polygon being dragged right now (not yet folded into the region).
  final CanvasSelectionShape? marqueeShape;

  /// An outline still being drawn and not yet closable: the lasso's raw
  /// trail, or a polygon's vertices with the rubber band to the cursor on
  /// the end. Drawn open, because it IS open.
  final List<CanvasPoint> openTrail;

  /// Where tapping would END the outline — the polygon's first vertex, from
  /// the moment it is placed.
  ///
  /// TS6: it used to appear only once three vertices could actually close,
  /// on the grounds that the ring must not promise a tap that does nothing.
  /// The promise is wider than that now — a tap here closes when it can and
  /// abandons the trace when it cannot (유저: 불가능할땐 그냥 취소) — so it
  /// is honest from the first point, which is also the only feedback that
  /// the first point landed at all.
  final CanvasPoint? closeTarget;

  /// Whether that tap would CLOSE (three or more vertices) rather than
  /// abandon. Drawn hollow either way; the ring is one shape with two
  /// meanings, so it is drawn thinner while it can only abandon.
  final bool closeTargetArmed;

  /// The pointer, in this painter's own (viewport-local) coordinates — the
  /// far end of the rubber band from the last placed vertex. Null when the
  /// active shape lays no vertices.
  ///
  /// 유저: *"직선이 커서를 따라 이동하고 찍히면 고정이란 느낌 나야하는데 그게
  /// 없음."* ⚠️A listenable rather than a value: it is merged into this
  /// painter's repaint so the band follows the pointer without anyone
  /// rebuilding the layer above.
  final ValueListenable<Offset?>? cursor;
  final SelectionTransformChrome? transformChrome;

  /// R16-① TVP grammar: RED silhouette while the move session holds
  /// unconfirmed changes, GREEN when confirmed/untouched.
  final bool movePendingDirty;

  static const Color _chromeColor = Color(0xFF40C4FF);
  static const Color _confirmedAntsColor = Color(0xFF2ECC71);
  static const Color _pendingAntsColor = Color(0xFFFF4444);

  static const double _dashOn = 5;
  static const double _dashOff = 4;

  /// Screen pixels. The same number the layer hit-tests the close tap
  /// against, so what the ring says is aimable is what is aimable — and
  /// screen pixels rather than canvas ones, because a finger is the same
  /// size at every zoom.
  static const double closeTargetRadius = 9;

  Offset _map(CanvasPoint point) {
    final mapped = viewport.canvasToViewport(point);
    return Offset(mapped.x, mapped.y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final phase = _phase.value * (_dashOn + _dashOff);

    final committed = committedRegion;
    if (committed != null) {
      // The composite outline: unions merge, subtractions cut holes — the
      // ants trace exactly what the fold selects.
      final path = committed.pathIn(
        (point) => _map(point) + screenOffset,
      );
      _paintAnts(canvas, path, phase);
    }
    final marquee = marqueeShape;
    if (marquee != null) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addPolygon([for (final point in marquee.points) _map(point)], true);
      _paintAnts(canvas, path, phase);
    } else if (openTrail.isNotEmpty) {
      // Not closable yet: show the outline as far as it has been drawn,
      // plus the segment the next tap would lay (TS6). With one vertex the
      // band IS the whole drawing — which is the point, since a lone
      // vertex has no segment of its own to show.
      final band = cursor?.value;
      final path = Path()
        ..moveTo(_map(openTrail.first).dx, _map(openTrail.first).dy);
      for (final point in openTrail.skip(1)) {
        final mapped = _map(point);
        path.lineTo(mapped.dx, mapped.dy);
      }
      if (band != null) {
        path.lineTo(band.dx, band.dy);
      }
      if (openTrail.length >= 2 || band != null) {
        _paintAnts(canvas, path, phase);
      }
    }

    final close = closeTarget;
    if (close != null) {
      // The tap target that ends the outline. A ring, not a filled dot: it
      // has to read as somewhere to aim rather than as a vertex that is
      // already there — and the vertices themselves wear nothing (유저:
      // "꼭짓점 점 그리지말라고. 그냥 라이브로 보이면 찍은건지 알수있으니까"
      // — the band is that liveness).
      canvas.drawCircle(
        _map(close),
        closeTargetRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = closeTargetArmed ? 1.5 : 1.0
          ..color = _chromeColor,
      );
    }

    final chrome = transformChrome;
    if (chrome != null) {
      _paintTransformChrome(canvas, chrome);
    }
  }

  void _paintTransformChrome(Canvas canvas, SelectionTransformChrome chrome) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _chromeColor;
    final fill = Paint()..color = _chromeColor;

    canvas.drawPath(Path()..addPolygon(chrome.box, true), stroke);
    for (final handle in chrome.handles) {
      canvas.drawRect(
        Rect.fromCenter(center: handle, width: 9, height: 9),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromCenter(center: handle, width: 9, height: 9),
        stroke,
      );
    }
    // The rotate lever: line from the top edge midpoint to the knob.
    // Quad mode carries no knob (R20-D2).
    final knob = chrome.knob;
    if (knob != null) {
      final topMid = Offset(
        (chrome.box[0].dx + chrome.box[1].dx) / 2,
        (chrome.box[0].dy + chrome.box[1].dy) / 2,
      );
      canvas.drawLine(topMid, knob, stroke);
      canvas.drawCircle(knob, 5, fill);
    }
  }

  /// White under-stroke + phase-offset colored dashes: GREEN for a
  /// confirmed/untouched selection, RED while a move session holds
  /// unconfirmed changes (R16-①, TVP grammar) — readable on any artwork.
  void _paintAnts(Canvas canvas, Path path, double phase) {
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white;
    final dashes = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = movePendingDirty ? _pendingAntsColor : _confirmedAntsColor;
    canvas.drawPath(path, white);
    canvas.drawPath(_dashPath(path, phase), dashes);
  }

  Path _dashPath(Path source, double phase) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = -phase % (_dashOn + _dashOff);
      while (distance < metric.length) {
        final start = distance.clamp(0.0, metric.length);
        final end = (distance + _dashOn).clamp(0.0, metric.length);
        if (end > start) {
          dashed.addPath(metric.extractPath(start, end), Offset.zero);
        }
        distance += _dashOn + _dashOff;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(covariant SelectionAntsPainter oldDelegate) =>
      oldDelegate.viewport != viewport ||
      oldDelegate.committedRegion != committedRegion ||
      oldDelegate.screenOffset != screenOffset ||
      oldDelegate.marqueeShape != marqueeShape ||
      oldDelegate.openTrail != openTrail ||
      oldDelegate.closeTarget != closeTarget ||
      oldDelegate.closeTargetArmed != closeTargetArmed ||
      !identical(oldDelegate.cursor, cursor) ||
      oldDelegate.transformChrome != transformChrome ||
      oldDelegate.movePendingDirty != movePendingDirty;
}
