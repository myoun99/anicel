import 'dart:ui' as ui show PointerChange, PointerData;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_pen_points.dart';
import 'package:anicel/src/services/input/pen_path.dart';

/// Pairs [event] with [points] — the points the OS saw of its message, the
/// oldest first and the newest its own — as the door pairs a datum as it
/// comes in ([PenPath.arrived]): what a platform's reader wrote into the
/// book for that message. One logical pixel to a physical one.
void pairWithThePointsTheOsSaw(PointerEvent event, List<OsPoint> points) {
  QaPenPoints.debugTake = (_, _, _) => points;
  try {
    PenPath.arrived(
      event,
      ui.PointerData(
        change: switch (event) {
          PointerDownEvent() => ui.PointerChange.down,
          PointerUpEvent() => ui.PointerChange.up,
          PointerHoverEvent() => ui.PointerChange.hover,
          _ => ui.PointerChange.move,
        },
        physicalX: event.position.dx,
        physicalY: event.position.dy,
      ),
      1,
    );
  } finally {
    QaPenPoints.debugTake = null;
  }
}

/// A point the OS saw at [at], in the view's pixels, at [time] — with the
/// pressure it read there, and the driver's packet a reader paired it with.
OsPoint seenAt(
  Offset at, {
  Duration time = Duration.zero,
  double? pressure,
  DriverReading? driven,
}) => (
  x: at.dx,
  y: at.dy,
  at: time,
  pressure: pressure,
  tilt: null,
  orientation: null,
  driven: driven,
);

/// A press of a [kind] contact at [from], moved through [moves] — each a
/// move the OS merged those points into, the newest its own, in the view's
/// pixels — and lifted where the last one ends: one pump after each. A
/// [lift] is the points the OS merged into the lift, the newest its own,
/// and the lift is there.
Future<void> dragThroughMergedMoves(
  WidgetTester tester,
  Offset from,
  List<List<Offset>> moves, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
  List<Offset> lift = const [],
}) async {
  const pointer = 61;
  tester.binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      kind: kind,
      buttons: kPrimaryButton,
      position: from,
    ),
  );
  await tester.pump();
  var before = from;
  for (final points in moves) {
    final at = points.last;
    final move = PointerMoveEvent(
      pointer: pointer,
      kind: kind,
      buttons: kPrimaryButton,
      position: at,
      delta: at - before,
    );
    before = at;
    pairWithThePointsTheOsSaw(move, [
      for (final point in points) seenAt(point),
    ]);
    tester.binding.handlePointerEvent(move);
    await tester.pump();
  }
  final up = PointerUpEvent(
    pointer: pointer,
    kind: kind,
    position: lift.isEmpty ? before : lift.last,
  );
  if (lift.isNotEmpty) {
    pairWithThePointsTheOsSaw(up, [for (final point in lift) seenAt(point)]);
  }
  tester.binding.handlePointerEvent(up);
  await tester.pump();
}
