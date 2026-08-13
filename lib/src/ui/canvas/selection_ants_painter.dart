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
    this.transformChrome,
    this.movePendingDirty = false,
  }) : _phase = repaint,
       super(repaint: repaint);

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

  /// Where tapping would close the outline — the polygon's first vertex,
  /// once there are enough of them. Null while closing is not on offer, so
  /// the ring never promises a tap that would do nothing.
  final CanvasPoint? closeTarget;
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
    } else if (openTrail.length >= 2) {
      // Not closable yet: show the outline as far as it has been drawn.
      final path = Path()
        ..moveTo(_map(openTrail.first).dx, _map(openTrail.first).dy);
      for (final point in openTrail.skip(1)) {
        final mapped = _map(point);
        path.lineTo(mapped.dx, mapped.dy);
      }
      _paintAnts(canvas, path, phase);
    }

    final close = closeTarget;
    if (close != null) {
      // The tap target that would close the outline. A ring, not a filled
      // dot: it has to read as somewhere to aim rather than as a vertex
      // that is already there.
      canvas.drawCircle(
        _map(close),
        closeTargetRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
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
      oldDelegate.transformChrome != transformChrome ||
      oldDelegate.movePendingDirty != movePendingDirty;
}
