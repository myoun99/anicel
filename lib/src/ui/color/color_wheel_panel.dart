import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Krita/CSP-style color wheel: a hue ring around a saturation/value
/// TRIANGLE that rotates with the hue (its full-saturation corner rides
/// the ring indicator). Dragging the ring spins the hue (the triangle
/// re-tints and rotates live); dragging the triangle picks saturation and
/// value. The panel keeps its own [HSVColor] so hue survives passing
/// through zero saturation or value, where RGB round-trips would forget
/// it.
///
/// Two color slots, Photoshop-style: the FOREGROUND is the brush color
/// (the wheel always edits it); the BACKGROUND is a spare slot. Swapping
/// (the arrows button or tapping the background swatch) exchanges the two
/// and the brush follows the new foreground.
class ColorWheelPanel extends StatefulWidget {
  const ColorWheelPanel({
    super.key,
    required this.color,
    required this.backgroundColor,
    required this.onColorChanged,
    required this.onBackgroundColorChanged,
  });

  /// The active brush color (ARGB int, the brush tool state's format).
  final int color;

  /// The spare background slot (ARGB int); lives with the owner so it
  /// survives tab switches.
  final int backgroundColor;

  final ValueChanged<int> onColorChanged;
  final ValueChanged<int> onBackgroundColorChanged;

  @override
  State<ColorWheelPanel> createState() => _ColorWheelPanelState();
}

class _ColorWheelPanelState extends State<ColorWheelPanel> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.color));
  int? _lastEmitted;

  @override
  void didUpdateWidget(covariant ColorWheelPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-derive HSV only for EXTERNAL color changes (preset swatches, brush
    // switches); our own emissions round-trip through the parent and must
    // not clobber the held hue.
    if (widget.color != oldWidget.color && widget.color != _lastEmitted) {
      _hsv = HSVColor.fromColor(Color(widget.color));
    }
  }

  void _setHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    final argb = hsv.toColor().toARGB32();
    _lastEmitted = argb;
    widget.onColorChanged(argb);
  }

  @override
  Widget build(BuildContext context) {
    // R10 R5: the wheel, and only the wheel. The swatch pair, the swap
    // button and the hex readout that used to share this panel all left —
    // the pair and the swap to the TOOL RAIL (where a hand rests), the hex
    // to the window's status bar (where every tab can read it). What is
    // left needs no adaptive strip: a square, centred, as big as it fits.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final square = math.min(constraints.maxWidth, constraints.maxHeight);
          return Center(child: _wheel(math.max(0, square).toDouble()));
        },
      ),
    );
  }

  Widget _wheel(double square) {
    return SizedBox(
      width: square,
      height: square,
      child: ColorWheel(
        key: const ValueKey<String>('color-wheel'),
        hsv: _hsv,
        onChanged: _setHsv,
      ),
    );
  }
}

/// Which part of the wheel a pointer engages; locked at pointer-down so a
/// drag never jumps between the ring and the triangle mid-gesture.
enum ColorWheelRegion { hueRing, svTriangle, none }

/// Pure hit/mapping geometry, shared by the painter, the gestures and the
/// tests. The triangle rotates with [hue]: its full-saturation corner
/// always points at the ring's hue position.
class ColorWheelGeometry {
  ColorWheelGeometry(Size size, {required this.hue})
    : center = size.center(Offset.zero),
      outerRadius = size.shortestSide / 2;

  final Offset center;
  final double outerRadius;

  /// Hue in degrees, 0° at 3 o'clock increasing clockwise (the ring's
  /// sweep-gradient convention).
  final double hue;

  double get ringWidth => outerRadius * 0.18;
  double get innerRadius => outerRadius - ringWidth;

  /// Triangle circumradius (small breathing gap to the ring).
  double get triangleRadius => innerRadius * 0.95;

  Offset _cornerAt(double degrees) {
    final radians = degrees * math.pi / 180;
    return center +
        Offset(math.cos(radians), math.sin(radians)) * triangleRadius;
  }

  /// Full-saturation corner (s=1, v=1); rides the hue on the ring.
  Offset get hueCorner => _cornerAt(hue);

  /// White corner (s=0, v=1).
  Offset get whiteCorner => _cornerAt(hue + 240);

  /// Black corner (v=0).
  Offset get blackCorner => _cornerAt(hue + 120);

  /// Barycentric weights of [position] w.r.t. (hue, white, black) corners.
  /// Weights sum to 1; any negative weight means outside the triangle.
  (double hueWeight, double whiteWeight, double blackWeight) _barycentric(
    Offset position,
  ) {
    final a = hueCorner;
    final v0 = whiteCorner - a;
    final v1 = blackCorner - a;
    final v2 = position - a;
    final d00 = v0.dx * v0.dx + v0.dy * v0.dy;
    final d01 = v0.dx * v1.dx + v0.dy * v1.dy;
    final d11 = v1.dx * v1.dx + v1.dy * v1.dy;
    final d20 = v2.dx * v0.dx + v2.dy * v0.dy;
    final d21 = v2.dx * v1.dx + v2.dy * v1.dy;
    final denominator = d00 * d11 - d01 * d01;
    final whiteWeight = (d11 * d20 - d01 * d21) / denominator;
    final blackWeight = (d00 * d21 - d01 * d20) / denominator;
    return (1 - whiteWeight - blackWeight, whiteWeight, blackWeight);
  }

  bool _insideTriangle(Offset position) {
    final (hueW, whiteW, blackW) = _barycentric(position);
    const epsilon = -1e-9;
    return hueW >= epsilon && whiteW >= epsilon && blackW >= epsilon;
  }

  ColorWheelRegion regionAt(Offset position) {
    if (_insideTriangle(position)) {
      return ColorWheelRegion.svTriangle;
    }
    final distance = (position - center).distance;
    if (distance >= innerRadius - 4 && distance <= outerRadius + 8) {
      return ColorWheelRegion.hueRing;
    }
    return ColorWheelRegion.none;
  }

  /// Hue in degrees at [position]: 0° at 3 o'clock, increasing clockwise —
  /// the same convention the sweep-gradient ring paints.
  double hueAt(Offset position) {
    final delta = position - center;
    final degrees = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
    return (degrees + 360) % 360;
  }

  static Offset _closestPointOnSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) {
      return a;
    }
    final ap = point - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    return a + ab * t;
  }

  /// [position] if inside the triangle, otherwise the nearest point on its
  /// boundary — how drags locked to the triangle clamp.
  Offset clampToTriangle(Offset position) {
    if (_insideTriangle(position)) {
      return position;
    }
    final corners = [hueCorner, whiteCorner, blackCorner];
    Offset? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < 3; i += 1) {
      final candidate = _closestPointOnSegment(
        position,
        corners[i],
        corners[(i + 1) % 3],
      );
      final distance = (candidate - position).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best!;
  }

  /// Saturation/value at [position], clamped into the triangle. The
  /// mapping is the standard HSV triangle: v = 1 − blackWeight,
  /// s = hueWeight / v (0 at the black corner, where saturation is
  /// undefined).
  (double saturation, double value) svAt(Offset position) {
    final (hueW, _, blackW) = _barycentric(clampToTriangle(position));
    final value = (1 - blackW).clamp(0.0, 1.0);
    final saturation = value <= 1e-9 ? 0.0 : (hueW / value).clamp(0.0, 1.0);
    return (saturation, value);
  }

  /// Where ([saturation], [value]) sits inside the triangle — the inverse
  /// of [svAt] (used by the indicator dot and the tests).
  Offset svPosition(double saturation, double value) {
    final hueW = saturation * value;
    final whiteW = value * (1 - saturation);
    final blackW = 1 - value;
    return Offset(
      hueCorner.dx * hueW + whiteCorner.dx * whiteW + blackCorner.dx * blackW,
      hueCorner.dy * hueW + whiteCorner.dy * whiteW + blackCorner.dy * blackW,
    );
  }
}

class ColorWheel extends StatefulWidget {
  const ColorWheel({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  ColorWheelRegion _activeRegion = ColorWheelRegion.none;

  void _apply(Offset position, Size size) {
    final geometry = ColorWheelGeometry(size, hue: widget.hsv.hue);
    switch (_activeRegion) {
      case ColorWheelRegion.hueRing:
        widget.onChanged(widget.hsv.withHue(geometry.hueAt(position)));
      case ColorWheelRegion.svTriangle:
        final (saturation, value) = geometry.svAt(position);
        widget.onChanged(
          widget.hsv.withSaturation(saturation).withValue(value),
        );
      case ColorWheelRegion.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) {
            _activeRegion = ColorWheelGeometry(
              size,
              hue: widget.hsv.hue,
            ).regionAt(details.localPosition);
            _apply(details.localPosition, size);
          },
          onPanUpdate: (details) => _apply(details.localPosition, size),
          onPanEnd: (_) => _activeRegion = ColorWheelRegion.none,
          onPanCancel: () => _activeRegion = ColorWheelRegion.none,
          child: CustomPaint(painter: _ColorWheelPainter(hsv: widget.hsv)),
        );
      },
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = ColorWheelGeometry(size, hue: hsv.hue);
    final center = geometry.center;

    // Hue ring: a sweep gradient stroke. SweepGradient runs clockwise from
    // the +x axis in screen space — the same angle convention hueAt reads.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = geometry.ringWidth
      ..shader =
          SweepGradient(
            colors: [
              for (var hue = 0; hue <= 360; hue += 30)
                HSVColor.fromAHSV(1, (hue % 360).toDouble(), 1, 1).toColor(),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: geometry.outerRadius),
          );
    final ringRadius = geometry.innerRadius + geometry.ringWidth / 2;
    canvas.drawCircle(center, ringRadius, ringPaint);

    // SV triangle: Gouraud interpolation across (hue, white, black)
    // corners IS the HSV triangle mapping — RGB(h,s,v) = v·s·hueRGB +
    // v·(1−s)·white matches the barycentric weights exactly.
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        [geometry.hueCorner, geometry.whiteCorner, geometry.blackCorner],
        colors: [hueColor, Colors.white, Colors.black],
      ),
      BlendMode.dst,
      Paint(),
    );

    // Indicators: hue dot on the ring, SV dot in the triangle —
    // white/black double stroke so they read on any color underneath.
    final hueAngle = hsv.hue * math.pi / 180;
    final hueDot =
        center + Offset(math.cos(hueAngle), math.sin(hueAngle)) * ringRadius;
    _paintIndicator(canvas, hueDot, geometry.ringWidth * 0.34);

    _paintIndicator(canvas, geometry.svPosition(hsv.saturation, hsv.value), 5);
  }

  void _paintIndicator(Canvas canvas, Offset at, double radius) {
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawCircle(
      at,
      radius + 1.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
