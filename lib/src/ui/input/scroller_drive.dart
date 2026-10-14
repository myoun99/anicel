import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../timeline/axis_turn.dart';

/// One scroller moved by a drag that is not its own: what `Scrollable` does
/// with its own recogniser's callbacks — hold on the press, drag from the
/// start, fling on the release — fed the part of each movement that runs
/// the scroller's way.
///
/// Two drags drive scrollers this way: the press hold
/// ([holdThePressForItsScroller]), which moves the one scroller a press
/// landed in when the drag across it is the one that wins, and a sheet's
/// one drag ([TwoAxisDrag]), which moves both of the sheet's axes at once.
class ScrollerDrive {
  ScrollerDrive(this.position);

  final ScrollPosition position;
  ScrollHoldController? _hold;
  Drag? _drag;

  double _along(Offset offset) =>
      position.axis == Axis.horizontal ? offset.dx : offset.dy;

  Offset _onTheAxis(double value) =>
      offsetAlong(position.axis, along: value, across: 0);

  /// The press: a scroller that is coasting stops under it.
  void hold() => _hold = position.hold(_dropHold);

  void start(DragStartDetails details) {
    _drag = position.drag(details, _dropDrag);
  }

  void update(DragUpdateDetails details) {
    final along = _along(details.delta);
    _drag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: _onTheAxis(along),
        primaryDelta: along,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void end(DragEndDetails details) {
    final along = _along(details.velocity.pixelsPerSecond);
    _drag?.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: _onTheAxis(along)),
        primaryVelocity: along,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void cancel() {
    _hold?.cancel();
    _drag?.cancel();
  }

  void _dropHold() => _hold = null;

  void _dropDrag() => _drag = null;
}
