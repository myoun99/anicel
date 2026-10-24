import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

// Fingers moved the way the pointer queue delivers them: every finger of a
// frame back to back, in ONE batch (F-260). The lock batch of a group drag
// is the one place a finger read a frame late would skew the anchor — and a
// skewed anchor stays wrong for the whole gesture.

/// One batch: every event dispatched before any microtask runs.
/// `sendEventToBinding` cannot be called twice without an await between,
/// which would be a batch of one.
Future<void> batch(WidgetTester tester, List<PointerEvent> events) async {
  for (final event in events) {
    tester.binding.handlePointerEvent(event);
  }
  await tester.idle();
  await tester.pump();
}

/// Touch fingers down at [at], one after another, then a frame.
Future<List<TestPointer>> fingersDown(
  WidgetTester tester,
  List<Offset> at,
) async {
  final fingers = [
    for (var i = 0; i < at.length; i += 1)
      TestPointer(i + 1, PointerDeviceKind.touch),
  ];
  for (var i = 0; i < at.length; i += 1) {
    await tester.sendEventToBinding(fingers[i].down(at[i]));
  }
  await tester.pump();
  return fingers;
}

/// Every one of [fingers] moved [by] — one batch's worth of events.
List<PointerEvent> moveAll(List<TestPointer> fingers, Offset by) => [
  for (final finger in fingers) finger.move(finger.location! + by),
];

Future<void> liftAll(WidgetTester tester, List<TestPointer> fingers) =>
    batch(tester, [for (final finger in fingers) finger.up()]);
