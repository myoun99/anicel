import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../services/transform_box_law.dart';
import '../input/control_press_claim.dart';
import '../repaint_props.dart';
import '../theme/disabled_ink.dart';
import 'owning_axis_grip.dart';
import 'setting_source_button.dart' show settingGlyphPaint;

/// A DIAL an angle is turned on: its needle points where the angle does —
/// 0° up and clockwise, as After Effects' angle dial reads — and a drag on
/// it turns the angle as far as the hand goes round its middle, whole
/// turns and all ([onTurned]).
///
/// 🗣️I-132-Q18 b (유저 2026-10-28): 「레인 줄에 작은 다이얼」 — beside an
/// angle lane's boxes, always there, the needle at the angle and a drag on
/// it turning it. A drag that starts on it is its own, whichever way it
/// goes ([OwningAxisGrip], 「컨트롤 위에서 시작한 제스처는 그 컨트롤의 것이다」);
/// a press that does not move does nothing.
class AngleDial extends StatefulWidget {
  const AngleDial({
    super.key,
    required this.degrees,
    required this.enabled,
    this.onTurnStart,
    required this.onTurned,
    this.onTurnEnd,
  });

  /// The angle the needle points at.
  final double degrees;

  /// Off, the dial still shows its needle, dimmed, and turns nothing — but
  /// a press on it is still the dial's, not a scroll's.
  final bool enabled;

  /// A turn begins: the press, before the hand has moved.
  final VoidCallback? onTurnStart;

  /// The degrees the hand has turned since the press — clockwise up, whole
  /// turns counted ([TransformBoxLaw.turn]).
  final ValueChanged<double> onTurned;

  /// The turn is over: the hand let go, or the press was taken away.
  final VoidCallback? onTurnEnd;

  /// As tall as the number boxes beside it.
  static const double size = 24;

  @override
  State<AngleDial> createState() => _AngleDialState();
}

class _AngleDialState extends State<AngleDial> {
  /// The hand's angle about the middle at the last move.
  double _lastAngle = 0;

  /// How far it has turned since the press.
  double _turned = 0;

  CanvasPoint get _middle {
    final size = context.size ?? Size.zero;
    return CanvasPoint(x: size.width / 2, y: size.height / 2);
  }

  static CanvasPoint _at(Offset local) =>
      CanvasPoint(x: local.dx, y: local.dy);

  void _started(DragStartDetails details) {
    _lastAngle = TransformBoxLaw.angleAbout(
      _middle,
      _at(details.localPosition),
    );
    _turned = 0;
    widget.onTurnStart?.call();
  }

  void _moved(DragUpdateDetails details) {
    final turn = TransformBoxLaw.turn(
      centre: _middle,
      pointer: _at(details.localPosition),
      lastAngle: _lastAngle,
    );
    _lastAngle = turn.angle;
    if (turn.turned == 0) {
      return;
    }
    _turned += turn.turned;
    widget.onTurned(_turned);
  }

  void _over() => widget.onTurnEnd?.call();

  @override
  Widget build(BuildContext context) {
    final ink = dimmedIfDisabled(
      Theme.of(context).colorScheme.onSurface,
      enabled: widget.enabled,
    );
    // ⚠️The press is CLAIMED though it does nothing on a release, as a
    // number box's face is: a row around the dial does not take it for its
    // own tap.
    return ControlPressClaim(
      onPressed: null,
      child: OwningAxisGrip(
        axis: null,
        configure: widget.enabled
            ? (recognizer) {
                recognizer.dragStartBehavior = DragStartBehavior.down;
                recognizer.onStart = _started;
                recognizer.onUpdate = _moved;
                recognizer.onEnd = (_) => _over();
                recognizer.onCancel = _over;
              }
            : null,
        child: SizedBox.square(
          dimension: AngleDial.size,
          child: CustomPaint(
            painter: _DialPainter(degrees: widget.degrees, ink: ink),
          ),
        ),
      ),
    );
  }
}

/// The dial's ring and its needle.
class _DialPainter extends CustomPainter with RepaintOnProps {
  const _DialPainter({required this.degrees, required this.ink});

  final double degrees;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = settingGlyphPaint(ink);
    final middle = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    canvas.drawCircle(middle, radius, paint);
    // 0° up, clockwise: the screen's y runs down.
    final radians = degrees * math.pi / 180;
    canvas.drawLine(
      middle,
      middle + Offset(math.sin(radians), -math.cos(radians)) * radius,
      paint,
    );
  }

  @override
  Object get props => (degrees, ink);
}
