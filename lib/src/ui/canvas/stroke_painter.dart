import 'package:flutter/material.dart';

import '../../core/argb_channels.dart';
import '../../models/brush_settings.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/stroke.dart';
import '../../models/stroke_point.dart';

class PaintableLayer {
  const PaintableLayer({required this.layer, required this.frame});

  final Layer layer;
  final Frame frame;
}

class StrokePainter extends CustomPainter {
  const StrokePainter({
    this.strokes = const <Stroke>[],
    this.paintableLayers = const <PaintableLayer>[],
    this.activePoints = const <StrokePoint>[],
  });

  final List<Stroke> strokes;
  final List<PaintableLayer> paintableLayers;
  final List<StrokePoint> activePoints;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    if (paintableLayers.isEmpty) {
      for (final stroke in strokes) {
        _paintPoints(canvas, stroke.points, stroke.brushSettings);
      }
    } else {
      for (final paintableLayer in paintableLayers) {
        if (!paintableLayer.layer.isVisible) {
          continue;
        }

        final layerOpacity = paintableLayer.layer.opacity
            .clamp(0.0, 1.0)
            .toDouble();
        for (final stroke in paintableLayer.frame.strokes) {
          _paintPoints(
            canvas,
            stroke.points,
            stroke.brushSettings,
            opacityMultiplier: layerOpacity,
          );
        }
      }
    }

    _paintPoints(canvas, activePoints, BrushSettings(opacity: 0.6));

    final borderPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, borderPaint);
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.paintableLayers != paintableLayers ||
        oldDelegate.activePoints != activePoints;
  }

  void _paintPoints(
    Canvas canvas,
    List<StrokePoint> points,
    BrushSettings brushSettings, {
    double opacityMultiplier = 1.0,
  }) {
    if (points.isEmpty) {
      return;
    }

    final paint = Paint()
      ..color = _colorForBrush(brushSettings, opacityMultiplier)
      ..strokeWidth = brushSettings.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      final point = points.first;
      canvas.drawCircle(
        Offset(point.x, point.y),
        brushSettings.size / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(path, paint);
  }

  Color _colorForBrush(BrushSettings brushSettings, double opacityMultiplier) {
    final argb = brushSettings.color;
    final opacity = (brushSettings.opacity * opacityMultiplier)
        .clamp(0.0, 1.0)
        .toDouble();
    // 8-bit integer rounding on purpose: `withValues(alpha: a * opacity)`
    // round-trips through a double and can land a .5 case on the other
    // side of what this has always drawn.
    return Color(argb).withAlpha((argbAlpha(argb) * opacity).round());
  }
}
