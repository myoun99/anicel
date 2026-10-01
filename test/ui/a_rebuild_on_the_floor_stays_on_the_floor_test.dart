import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨A rebuild on the floor that lands OUTSIDE a frame lays out the floor
/// and nothing above it (F-166, 2026-09-26).
///
/// The floor is built inside a `LayoutBuilder`, which owns the build scope
/// of everything on it: a `setState` down there from a pointer handler or a
/// listener makes the builder lay itself out again on the next frame.
/// Handed the Row's loose height, the builder was no relayout boundary and
/// that relayout climbed every box up to the Scaffold: 21 layouts per
/// pen-up on the real app, each one a repaint mark and a semantics update.
///
/// ↩️The pen-up and the pixel edit it was measured with no longer reach the
/// floor: the canvas area rides a layer of its own (F-244), so its rebuilds
/// stop there. What still lands in the floor's scope is its own furniture —
/// the region's grips, the rails, the docks' chrome — and a region resize is
/// the one every hand makes.
///
/// ⚠️The premise is checked beside the claim: the floor's builder DOES lay
/// out in that frame — a trigger that never reached it would pass against
/// the defect.
void main() {
  Future<void> openApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  final floorBox = find.byKey(const ValueKey<String>('workspace-floor'));

  /// The render objects laid out while [act] runs and in the frame after
  /// it, named by the framework itself (`debugPrintLayouts`).
  Future<Set<String>> laidOutBy(
    WidgetTester tester,
    Future<void> Function() act,
  ) async {
    final laidOut = <String>{};
    final identity = RegExp(r'(\w+#[0-9a-f]{5})');
    final keep = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('Laying out')) {
        final id = identity.firstMatch(message)?.group(1);
        if (id != null) laidOut.add(id);
        return;
      }
      keep(message, wrapWidth: wrapWidth);
    };
    debugPrintLayouts = true;
    try {
      await act();
      await tester.pump();
    } finally {
      debugPrintLayouts = false;
      debugPrint = keep;
    }
    return laidOut;
  }

  /// The floor's box and every render object above it, up to the view.
  Set<String> aboveTheFloor(WidgetTester tester) {
    final above = <String>{};
    for (RenderObject? node = tester.renderObject(floorBox);
        node != null;
        node = node.parent) {
      above.add(describeIdentity(node));
    }
    return above;
  }

  /// The builder the floor is laid out by — the one the rebuild marks.
  String floorBuilder(WidgetTester tester) => describeIdentity(
        (tester.renderObject(floorBox) as RenderProxyBox).child,
      );

  testWidgets('a region resize lays out the floor and nothing above it', (
    tester,
  ) async {
    await openApp(tester);
    final grip = find.byKey(const ValueKey<String>('dock-resize-bottom'));
    final hand = await tester.startGesture(
      tester.getCenter(grip),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var step = 0; step < 3; step += 1) {
      await hand.moveBy(const Offset(0, -12));
      await tester.pump();
    }
    final laidOut = await laidOutBy(
      tester,
      () => hand.moveBy(const Offset(0, -12)),
    );
    await hand.up();
    await tester.pumpAndSettle();

    expect(
      laidOut,
      contains(floorBuilder(tester)),
      reason: 'premise: the resize rebuilt on the floor, so the floor laid out',
    );
    expect(laidOut.intersection(aboveTheFloor(tester)), isEmpty);
  });
}
