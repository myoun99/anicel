import 'package:flutter/material.dart';

import '../../models/brush_pressure_curve.dart';
import '../theme/app_theme.dart';
import 'anchored_popup.dart';

/// BB-3 (R26 #11): the shared pen-pressure curve editor — a CSP-style
/// 筆圧設定 popup. One [PressureCurveButton] sits at the right of each
/// pressure-capable slider row (size/opacity/flow/hardness); tapping it
/// opens the small anchored editor. The widget is generic over the value
/// (a [BrushPressureCurve]?), so any future pressure-capable setting can
/// reuse it unchanged.
///
/// Editor grammar (CSP vocabulary):
///  - drag a control point to move it (endpoints keep their x),
///  - press an empty spot on the curve area to ADD a point and drag on,
///  - drag a middle point well outside the graph to REMOVE it,
///  - the switch turns pressure OFF (curve = null) / ON (identity line).
class PressureCurveButton extends StatelessWidget {
  const PressureCurveButton({
    super.key,
    required this.keyValue,
    required this.title,
    required this.curve,
    required this.onChanged,
  });

  /// Widget key string for the trigger button ('brush-tool-pressure-size').
  final String keyValue;

  /// Popup header label (the setting's name, e.g. 'Size').
  final String title;

  final BrushPressureCurve? curve;
  final ValueChanged<BrushPressureCurve?> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = curve != null;
    return Tooltip(
      message: 'Pen pressure',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>(keyValue),
          borderRadius: BorderRadius.circular(4),
          onTap: () => showPressureCurvePopup(
            context,
            title: title,
            curve: curve,
            onChanged: onChanged,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? AppColors.accent : AppColors.hairline,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              child: CustomPaint(
                size: const Size(22, 14),
                painter: _MiniCurvePainter(
                  curve: curve,
                  color: active ? AppColors.accent : AppColors.textDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tiny in-button preview: the curve when pressure is on, a flat
/// full-value line when off.
class _MiniCurvePainter extends CustomPainter {
  const _MiniCurvePainter({required this.curve, required this.color});

  final BrushPressureCurve? curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path();
    const steps = 12;
    for (var i = 0; i <= steps; i += 1) {
      final t = i / steps;
      final value = curve?.evaluate(t) ?? 1.0;
      final x = t * size.width;
      final y = (1.0 - value) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MiniCurvePainter oldDelegate) =>
      oldDelegate.curve != curve || oldDelegate.color != color;
}

/// Shows the anchored curve editor next to [anchorContext]'s widget.
/// [onChanged] fires live on every edit (the popup keeps its own working
/// state, so the caller may rebuild freely underneath).
Future<void> showPressureCurvePopup(
  BuildContext anchorContext, {
  required String title,
  required BrushPressureCurve? curve,
  required ValueChanged<BrushPressureCurve?> onChanged,
}) {
  // R28 #9: placement and dismissal now live in the SHARED sub-window
  // shell — this popup is where that behaviour was designed, and every
  // other anchored window in the app opens through the same function.
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'pressure-curve-popup',
    width: 216,
    height: 236,
    builder: (context, _) => _PressureCurveEditor(
      title: title,
      initialCurve: curve,
      onChanged: onChanged,
    ),
  );
}

class _PressureCurveEditor extends StatefulWidget {
  const _PressureCurveEditor({
    required this.title,
    required this.initialCurve,
    required this.onChanged,
  });

  final String title;
  final BrushPressureCurve? initialCurve;
  final ValueChanged<BrushPressureCurve?> onChanged;

  @override
  State<_PressureCurveEditor> createState() => _PressureCurveEditorState();
}

class _PressureCurveEditorState extends State<_PressureCurveEditor> {
  static const int _maxPoints = 10;
  static const double _minXGap = 0.02;

  /// The working points while enabled; kept when toggling OFF so ON
  /// restores the shape within this popup session.
  late List<BrushCurvePoint> _points;
  late bool _enabled;

  /// Index of the grabbed point during a drag, or null. A grabbed middle
  /// point dragged far outside is REMOVED but stays "in hand"
  /// ([_dragRemoved]) so dragging back in re-adds it.
  int? _dragIndex;
  bool _dragRemoved = false;

  @override
  void initState() {
    super.initState();
    final curve = widget.initialCurve;
    _enabled = curve != null;
    _points = List.of(
      (curve ?? BrushPressureCurve.identity()).points,
    );
  }

  void _commit() {
    widget.onChanged(
      _enabled ? BrushPressureCurve(List.of(_points)) : null,
    );
  }

  void _setEnabled(bool value) {
    setState(() {
      _enabled = value;
      _dragIndex = null;
      _dragRemoved = false;
    });
    _commit();
  }

  void _reset() {
    setState(() {
      _points = BrushPressureCurve.identity().points.toList();
      _dragIndex = null;
      _dragRemoved = false;
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey<String>('pressure-curve-popup'),
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(6),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.title} — Pen pressure',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text,
                    ),
                  ),
                ),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    child: Switch(
                      key: const ValueKey<String>(
                        'pressure-curve-enable-switch',
                      ),
                      value: _enabled,
                      onChanged: _setEnabled,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildGraph(),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pressure →',
                    style: TextStyle(fontSize: 9, color: AppColors.textDim),
                  ),
                ),
                InkWell(
                  key: const ValueKey<String>('pressure-curve-reset'),
                  onTap: _enabled ? _reset : null,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        fontSize: 10,
                        color: _enabled
                            ? AppColors.text
                            : AppColors.textDim.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const Size _graphSize = Size(196, 150);

  Widget _buildGraph() {
    return GestureDetector(
      key: const ValueKey<String>('pressure-curve-graph'),
      behavior: HitTestBehavior.opaque,
      onPanStart: _enabled ? _handlePanStart : null,
      onPanUpdate: _enabled ? _handlePanUpdate : null,
      onPanEnd: _enabled ? _handlePanEnd : null,
      child: CustomPaint(
        size: _graphSize,
        painter: _CurveGraphPainter(
          points: _points,
          enabled: _enabled,
          accent: AppColors.accent,
        ),
      ),
    );
  }

  Offset _toUnit(Offset local) => Offset(
    (local.dx / _graphSize.width).clamp(0.0, 1.0),
    (1.0 - local.dy / _graphSize.height).clamp(0.0, 1.0),
  );

  void _handlePanStart(DragStartDetails details) {
    final local = details.localPosition;
    // Grab the nearest point within reach, else add one at the press.
    const grabRadius = 14.0;
    int? nearest;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _points.length; i += 1) {
      final point = _points[i];
      final position = Offset(
        point.x * _graphSize.width,
        (1.0 - point.y) * _graphSize.height,
      );
      final distance = (position - local).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }
    if (nearest != null && nearestDistance <= grabRadius) {
      setState(() {
        _dragIndex = nearest;
        _dragRemoved = false;
      });
      return;
    }
    if (_points.length >= _maxPoints) {
      return;
    }
    final unit = _toUnit(local);
    // Insert keeping ascending x; refuse to crowd an existing x.
    var insertAt = _points.length;
    for (var i = 0; i < _points.length; i += 1) {
      if (unit.dx < _points[i].x) {
        insertAt = i;
        break;
      }
    }
    if (insertAt == 0 || insertAt == _points.length) {
      return; // Outside the endpoints' x range (they sit at 0 and 1).
    }
    final clampedX = unit.dx.clamp(
      _points[insertAt - 1].x + _minXGap,
      _points[insertAt].x - _minXGap,
    );
    if (clampedX <= _points[insertAt - 1].x ||
        clampedX >= _points[insertAt].x) {
      return; // Neighbors too close to fit another point.
    }
    setState(() {
      _points.insert(insertAt, BrushCurvePoint(clampedX, unit.dy));
      _dragIndex = insertAt;
      _dragRemoved = false;
    });
    _commit();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final index = _dragIndex;
    if (index == null) {
      return;
    }
    final local = details.localPosition;
    // Middle points dragged far outside the graph are removed (CSP's
    // delete gesture); dragging back inside re-adds them.
    const removeSlack = 28.0;
    final outside =
        local.dx < -removeSlack ||
        local.dx > _graphSize.width + removeSlack ||
        local.dy < -removeSlack ||
        local.dy > _graphSize.height + removeSlack;
    final isMiddle = !_dragRemoved && index > 0 && index < _points.length - 1;
    if (outside && isMiddle) {
      setState(() {
        _points.removeAt(index);
        _dragRemoved = true;
      });
      _commit();
      return;
    }
    if (_dragRemoved) {
      if (outside) {
        return;
      }
      final unit = _toUnit(local);
      var insertAt = _points.length;
      for (var i = 0; i < _points.length; i += 1) {
        if (unit.dx < _points[i].x) {
          insertAt = i;
          break;
        }
      }
      if (insertAt == 0 || insertAt == _points.length) {
        return;
      }
      final clampedX = unit.dx.clamp(
        _points[insertAt - 1].x + _minXGap,
        _points[insertAt].x - _minXGap,
      );
      if (clampedX <= _points[insertAt - 1].x ||
          clampedX >= _points[insertAt].x) {
        return;
      }
      setState(() {
        _points.insert(insertAt, BrushCurvePoint(clampedX, unit.dy));
        _dragIndex = insertAt;
        _dragRemoved = false;
      });
      _commit();
      return;
    }
    final unit = _toUnit(local);
    final double x;
    if (index == 0) {
      x = 0.0;
    } else if (index == _points.length - 1) {
      x = 1.0;
    } else {
      x = unit.dx.clamp(
        _points[index - 1].x + _minXGap,
        _points[index + 1].x - _minXGap,
      );
    }
    setState(() {
      _points[index] = BrushCurvePoint(x, unit.dy);
    });
    _commit();
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _dragIndex = null;
      _dragRemoved = false;
    });
  }
}

class _CurveGraphPainter extends CustomPainter {
  const _CurveGraphPainter({
    required this.points,
    required this.enabled,
    required this.accent,
  });

  final List<BrushCurvePoint> points;
  final bool enabled;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = AppColors.surface;
    canvas.drawRect(Offset.zero & size, background);
    final grid = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i += 1) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..color = AppColors.hairline
        ..style = PaintingStyle.stroke,
    );

    final lineColor = enabled ? accent : AppColors.textDim;
    final curvePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final curve = BrushPressureCurve(List.of(points));
    final path = Path();
    const steps = 48;
    for (var i = 0; i <= steps; i += 1) {
      final t = i / steps;
      final value = enabled ? curve.evaluate(t) : 1.0;
      final x = t * size.width;
      final y = (1.0 - value) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, curvePaint);

    if (enabled) {
      final handleFill = Paint()..color = accent;
      final handleStroke = Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final point in points) {
        final center = Offset(
          point.x * size.width,
          (1.0 - point.y) * size.height,
        );
        final rect = Rect.fromCenter(center: center, width: 7, height: 7);
        canvas.drawRect(rect, handleFill);
        canvas.drawRect(rect, handleStroke);
      }
    }
  }

  // The editor mutates its working list in place, so instance identity
  // can't detect changes — the graph is tiny, always repaint.
  @override
  bool shouldRepaint(_CurveGraphPainter oldDelegate) => true;
}
