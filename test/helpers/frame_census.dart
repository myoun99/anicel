import 'package:flutter/rendering.dart'
    show RenderObject, debugOnProfilePaint, debugProfilePaintsEnabled;
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';

/// What one frame did about [act]: the widget types it rebuilt and the
/// render objects it painted — [act] runs, then the frame it scheduled.
///
/// Read off the framework's own debug hooks, which see every element
/// rebuilt and every render object painted, so a claim like "a brush change
/// rebuilds no panel" is checked against the whole tree rather than a
/// counter someone remembered to put in one widget.
Future<({List<Type> rebuilt, List<RenderObject> painted})> frameCensus(
  WidgetTester tester,
  void Function() act,
) async {
  final rebuilt = <Type>[];
  final painted = <RenderObject>[];
  debugOnRebuildDirtyWidget = (element, _) =>
      rebuilt.add(element.widget.runtimeType);
  debugOnProfilePaint = painted.add;
  debugProfilePaintsEnabled = true;
  try {
    act();
    await tester.pump();
  } finally {
    debugProfilePaintsEnabled = false;
    debugOnProfilePaint = null;
    debugOnRebuildDirtyWidget = null;
  }
  return (rebuilt: rebuilt, painted: painted);
}
