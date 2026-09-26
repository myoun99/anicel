import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// 🚨A rebuild on the floor that lands OUTSIDE a frame lays out the floor
/// and nothing above it (F-166, 2026-09-26).
///
/// The floor is built inside a `LayoutBuilder`, which owns the build scope
/// of everything on it: a `setState` down there from a pointer handler or a
/// listener — the canvas panel's at every pen-up — makes the builder lay
/// itself out again on the next frame. Handed the Row's loose height, the
/// builder was no relayout boundary and that relayout climbed every box up
/// to the Scaffold: 21 layouts per pen-up on the real app, each one a
/// repaint mark and a semantics update.
///
/// ⚠️The premise is checked beside the claim: the floor's builder DOES lay
/// out in that frame — a trigger that never reached it would pass against
/// the defect.
void main() {
  Future<EditorWorkspace> openApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));
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

  testWidgets('a pixel edit rebuilds the canvas panel and lays out nothing '
      'above the floor', (tester) async {
    final session = (await openApp(tester)).session;
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    final laidOut = await laidOutBy(tester, () async {
      // Between frames, where a commit's announcement lands.
      session.renderCaches.brushFrameStore.celPixelRevision.value += 1;
    });

    expect(
      laidOut,
      contains(floorBuilder(tester)),
      reason: 'premise: the canvas panel rebuilt, so the floor laid out',
    );
    expect(laidOut.intersection(aboveTheFloor(tester)), isEmpty);
  });

  testWidgets('a stroke\'s pen-up lays out nothing above the floor', (
    tester,
  ) async {
    final session = (await openApp(tester)).session;
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    for (var step = 0; step < 4; step += 1) {
      await pen.moveBy(const Offset(12, 8));
      await tester.pump();
    }
    final laidOut = await laidOutBy(tester, pen.up);
    await tester.pumpAndSettle();

    expect(
      laidOut,
      contains(floorBuilder(tester)),
      reason: 'premise: the pen-up rebuilt on the floor',
    );
    expect(laidOut.intersection(aboveTheFloor(tester)), isEmpty);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
