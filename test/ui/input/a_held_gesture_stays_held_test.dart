import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🗣️F-189 (유저 2026-09-26): 「가끔 터치로 팬하거나 줌하거나 터치조작할때
/// 아직 손 대고있는데 동작 풀리거든? 터치중 펜 호버하면 자주 풀리는거같은데.
/// 아이패드였어. 윈도우도 그냥 스페이스바로 팬하다가 그냥 풀리고」.
///
/// A gesture the hand still holds is still the hand's. Through the whole app
/// — every hover listener, cursor and overlay the canvas mounts — the
/// neighbours of a held gesture arrive mid-way: a pencil coming into hover
/// range (iPadOS reports it as a MOUSE: add, then hover), an S-Pen's hover
/// (a stylus), a palm, the space bar's own key repeats.
void main() {
  late EditorSessionManager session;

  Future<Finder> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    return find
        .byKey(const ValueKey<String>('brush-canvas-editor-viewport'))
        .first;
  }

  /// The view the canvas SHOWS — the project's framing the panel publishes
  /// ([EditorSessionManager.canvasViewport]); null until something framed
  /// it.
  CanvasViewport? live() => session.canvasViewport.value;

  /// A point the canvas itself receives, with room for a finger either
  /// side. ⚠️The floating docks cover part of the viewport (its middle is a
  /// dock's splitter at this size), so a point counts only when a hit test
  /// there reaches the canvas's gesture layer.
  Offset onTheCanvas(WidgetTester tester, Finder area) {
    final layer = tester.renderObject(
      find.descendant(
        of: area,
        matching: find.byKey(
          const ValueKey<String>('canvas-viewport-gesture-layer'),
        ),
      ),
    );
    bool reaches(Offset point) {
      final result = HitTestResult();
      tester.binding.hitTestInView(result, point, tester.view.viewId);
      return result.path.any((entry) => identical(entry.target, layer));
    }

    final rect = tester.getRect(area);
    for (var y = rect.top + 80; y < rect.bottom - 80; y += 20) {
      for (var x = rect.left + 200; x < rect.right - 200; x += 20) {
        final point = Offset(x, y);
        if (reaches(point) &&
            reaches(point - const Offset(160, 0)) &&
            reaches(point + const Offset(160, 0)) &&
            reaches(point + const Offset(0, 60))) {
          return point;
        }
      }
    }
    throw StateError('no free point on the canvas');
  }

  /// Two fingers down on the canvas and spread once — the pinch LOCKED and
  /// zooming. Returns the two fingers and the zoom it reached.
  Future<(TestGesture, TestGesture, double)> pinchUnderway(
    WidgetTester tester,
    Finder area,
  ) async {
    final centre = onTheCanvas(tester, area);
    final before = live();
    final a = await tester.startGesture(
      centre - const Offset(60, 0),
      kind: PointerDeviceKind.touch,
    );
    final b = await tester.startGesture(
      centre + const Offset(60, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
    final reached = live();
    expect(reached, isNot(before), reason: 'premise: the pinch navigates');
    return (a, b, reached!.zoom);
  }

  Future<void> spreadAgain(
    WidgetTester tester,
    TestGesture a,
    TestGesture b,
  ) async {
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
  }

  testWidgets('iPad: a pencil hovering in (a MOUSE add + hover) leaves the '
      'pinch the fingers\'', (tester) async {
    final area = await pumpHome(tester);
    final (a, b, zoom) = await pinchUnderway(tester, area);

    final pencil = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pencil.addPointer(
      location: onTheCanvas(tester, area) + const Offset(0, 60),
    );
    await pencil.moveTo(onTheCanvas(tester, area) + const Offset(10, 50));
    await tester.pump();
    await spreadAgain(tester, a, b);

    expect(live()!.zoom, greaterThan(zoom));
    await pencil.removePointer();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  });

  testWidgets('an S-Pen hovering in (a STYLUS hover) leaves the pinch the '
      'fingers\'', (tester) async {
    final area = await pumpHome(tester);
    final (a, b, zoom) = await pinchUnderway(tester, area);

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(
      location: onTheCanvas(tester, area) + const Offset(0, 60),
    );
    await pen.moveTo(onTheCanvas(tester, area) + const Offset(10, 50));
    await tester.pump();
    await spreadAgain(tester, a, b);

    expect(live()!.zoom, greaterThan(zoom));
    await pen.removePointer();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  });

  // The pencil does not only hover: 「터치중 펜 호버하면」 is a pencil close
  // enough to TOUCH, and flutter/flutter#122784 names that one — a pencil
  // tip landing during a finger gesture ended the finger's.
  testWidgets('a pencil tip touching down mid-pinch leaves the pinch the '
      'fingers\'', (tester) async {
    final area = await pumpHome(tester);
    final (a, b, zoom) = await pinchUnderway(tester, area);

    final tip = await tester.startGesture(
      onTheCanvas(tester, area) + const Offset(0, 60),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await tip.moveBy(const Offset(3, 2));
    await tester.pump();
    await spreadAgain(tester, a, b);
    final whileTheTipIsDown = live()!.zoom;
    await tip.up();
    await tester.pump();
    await spreadAgain(tester, a, b);

    expect(
      whileTheTipIsDown,
      greaterThan(zoom),
      reason: 'the fingers still zoom while the tip is down',
    );
    expect(
      live()!.zoom,
      greaterThan(whileTheTipIsDown),
      reason: 'and after it lifts',
    );
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a palm landing and lifting mid-pinch leaves the pinch the '
      'fingers\'', (tester) async {
    final area = await pumpHome(tester);
    final (a, b, zoom) = await pinchUnderway(tester, area);

    final palm = await tester.startGesture(
      onTheCanvas(tester, area) + const Offset(0, 60),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await palm.up();
    await tester.pump();
    await spreadAgain(tester, a, b);

    expect(live()!.zoom, greaterThan(zoom));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  });

  /// The space bar held (I-15's 「이동」), a press dragged, and the key's own
  /// auto-repeats arriving mid-drag — Windows sends them for as long as the
  /// key is down.
  Future<void> spacePanThroughRepeats(
    WidgetTester tester,
    PointerDeviceKind kind,
  ) async {
    final area = await pumpHome(tester);
    final centre = onTheCanvas(tester, area);
    final before = live();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final hand = await tester.startGesture(
      centre,
      kind: kind,
      buttons: kPrimaryButton,
    );
    await hand.moveBy(const Offset(40, 0));
    await tester.pump();
    final first = live();
    expect(first, isNot(before), reason: 'premise: it pans');

    for (var i = 0; i < 6; i += 1) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    }
    await tester.pump();
    await hand.moveBy(const Offset(40, 0));
    await tester.pump();

    expect(live()!.panX, isNot(first!.panX));
    await hand.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
    testWidgets('Windows: a space-held pan with a ${kind.name} holds through '
        'the key\'s repeats', (tester) async {
      await spacePanThroughRepeats(tester, kind);
    });
  }
}
