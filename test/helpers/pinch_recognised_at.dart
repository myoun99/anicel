import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two fingers whose pinch is RECOGNISED with them at [first] and [second]:
/// the spread, angle and focal the gesture measures from.
///
/// 🗣️F-260: a touch drag starts where it is recognised — where a finger
/// crosses the 18px slop — and the travel before that never lands. So the
/// first finger lands 20px right of [first] and crosses the slop INTO it,
/// and a test moves the pair from exactly the spots it names.
Future<(TestGesture, TestGesture)> pinchRecognisedAt(
  WidgetTester tester,
  Offset first,
  Offset second, {
  int? pointer,
}) async {
  final a = await tester.startGesture(
    first + const Offset(20, 0),
    kind: PointerDeviceKind.touch,
    pointer: pointer,
  );
  final b = await tester.startGesture(
    second,
    kind: PointerDeviceKind.touch,
    pointer: pointer == null ? null : pointer + 1,
  );
  // On a drawing canvas the first finger began a stroke that the second
  // one cancelled, and the canvas hears that on the next frame.
  await tester.pump();
  await a.moveTo(first);
  return (a, b);
}
