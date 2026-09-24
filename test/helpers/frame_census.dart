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
///
/// ⚠️`painted` is what a parent handed to `paintChild` — and a repaint
/// boundary whose layer is only reused is handed to it too. Whether a
/// boundary painted AGAIN shows in what it paints inside
/// ([paintedInside]), never in its own entry (2026-09-24: read the other
/// way, every settings row "repainted" when one did).
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

/// Whether anything in [painted] lies strictly inside [boundary] — the one
/// sign that a repaint boundary painted again rather than being handed on
/// with its layer as it was (see [frameCensus]).
bool paintedInside(List<RenderObject> painted, RenderObject boundary) =>
    painted.any((object) {
      for (var node = object.parent; node != null; node = node.parent) {
        if (identical(node, boundary)) {
          return true;
        }
      }
      return false;
    });
