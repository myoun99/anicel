import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/canvas/canvas_point_gizmo.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';

/// 🚨★★★H24 — A PRESS INSIDE A CANVAS PANEL IS THAT PANEL'S. THE SCROLLER
/// AROUND IT NEVER MOVES.
///
/// Third report, and the card was reopened rather than a new one written:
/// 08-26 「패널이 여러 개 열려 레일이 생기면 터치 시 스크롤 발생」, 09-01
/// 「전혀 해결안됨 … 내부 터치는 강한 클레임으로 애초에 다른 곳에서 조작이
/// 발생 안 하게」, 09-15 「스페이스바+클릭이나 터치조작이나 뷰어패널 내부에
/// 대한 조작이 다중패널의 스크롤바가 활성되있을때 스크롤바랑 내부조작이랑
/// 동시적용되버리니까 스크롤바 절대 적용안되게 강한클레임으로 잡아줘. 캔버스
/// 베이스패널은 전부 다 똑같이 법 통일해서 적용이야. 타임시트든 콘티패널이든
/// 컷봉투든 뷰어패널이든」.
///
/// The scroller here is the kind the dock wraps a squeezed panel in
/// (`editor_panel_tabs.dart`, a `SingleChildScrollView` under the app's
/// scroll behaviour — which lets a MOUSE drag scroll too). Every canvas
/// panel is [BrushCanvasPanel]; the four sheets mount it through
/// [SheetCanvasPanel] and the viewer mounts it with a one-finger pan.
///
/// 🧪Measured before the fix, same fixture: every drag below scrolled the
/// panel 144px, and two fingers on the sheet did not even reach the pinch —
/// 12 viewports emitted without the scroller around it, 0 with it.
void main() {
  tearDown(() {
    CanvasPanHold.held.value = false;
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    debugClearValueControlPointers();
  });

  const panelKey = ValueKey<String>('h24-panel');
  const outsideKey = ValueKey<String>('h24-outside');

  /// [panel] 300px tall above 600px of something else, in a 400px scroller.
  Future<({ScrollController scroll, List<CanvasViewport> emitted})> pump(
    WidgetTester tester,
    Widget Function(ValueChanged<CanvasViewport> onViewportChanged) panel,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final emitted = <CanvasViewport>[];
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 400,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  SizedBox(
                    key: panelKey,
                    height: 300,
                    child: panel(emitted.add),
                  ),
                  const ColoredBox(
                    key: outsideKey,
                    color: Color(0xFF203040),
                    child: SizedBox(height: 600, width: 400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (scroll: scroll, emitted: emitted);
  }

  Widget sheet(ValueChanged<CanvasViewport> onViewportChanged) =>
      SheetCanvasPanel(
        cacheInvalidationSink: BrushEditCacheInvalidationSink(),
        canvasSize: const CanvasSize(width: 600, height: 800),
        viewport: CanvasViewport(),
        onViewportChanged: onViewportChanged,
        // H24 asks what a press inside the panel does, with no ink mounted
        // — the sheet's drawing is off, as it always was here.
        drawingOn: false,
        content: (context, viewport) => const SizedBox.expand(),
      );

  Widget viewer(ValueChanged<CanvasViewport> onViewportChanged) =>
      BrushCanvasPanel(
        coordinator: null,
        availableFrameKeys: const [],
        cacheInvalidationSink: BrushEditCacheInvalidationSink(),
        canvasSize: const CanvasSize(width: 600, height: 800),
        viewport: CanvasViewport(),
        onViewportChanged: onViewportChanged,
        allowViewRotation: false,
        toolCursorsEnabled: false,
        oneFingerAction: CanvasTouchDragAction.navigate,
        contentOverride: (context, viewport) => const SizedBox.expand(),
      );

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    PointerDeviceKind kind, {
    int pointer = 1,
  }) async {
    final g = await tester.startGesture(from, kind: kind, pointer: pointer);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<void> twoFingerPan(WidgetTester tester, Offset from) async {
    final a = await tester.startGesture(
      from,
      kind: PointerDeviceKind.touch,
      pointer: 11,
    );
    final b = await tester.startGesture(
      from + const Offset(80, 0),
      kind: PointerDeviceKind.touch,
      pointer: 12,
    );
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(0, -24));
      await b.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  Offset inside(WidgetTester tester) =>
      tester.getCenter(find.byKey(panelKey)) + const Offset(-60, -40);

  for (final (family, mount) in [('sheet', sheet), ('viewer', viewer)]) {
    group('$family panel', () {
      testWidgets('⛔fixture premise: a drag OFF the panel scrolls', (
        tester,
      ) async {
        final h = await pump(tester, mount);
        expect(h.scroll.position.maxScrollExtent, greaterThan(0));
        // ⚠️A VISIBLE point of the box below: its centre sits at y=600,
        // outside the 400px scroller, and a press there reaches nothing.
        await drag(
          tester,
          tester.getTopLeft(find.byKey(outsideKey)) + const Offset(200, 40),
          PointerDeviceKind.touch,
        );
        expect(h.scroll.offset, greaterThan(0));
      });

      for (final kind in const [
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.mouse,
      ]) {
        testWidgets('a ${kind.name} drag inside never scrolls', (
          tester,
        ) async {
          final h = await pump(tester, mount);
          await drag(tester, inside(tester), kind);
          expect(h.scroll.offset, 0);
        });
      }

      testWidgets('space + mouse drag pans the view and never scrolls', (
        tester,
      ) async {
        final h = await pump(tester, mount);
        CanvasPanHold.held.value = true;
        await tester.pump();
        await drag(tester, inside(tester), PointerDeviceKind.mouse);
        expect(h.emitted, isNotEmpty, reason: 'the canvas took the pan');
        expect(h.scroll.offset, 0);
      });

      testWidgets('two fingers pan the view and never scroll', (tester) async {
        final h = await pump(tester, mount);
        await twoFingerPan(tester, inside(tester));
        expect(h.emitted, isNotEmpty, reason: 'the canvas took the pinch');
        expect(h.scroll.offset, 0);
      });

      testWidgets('⛔fixture premise: a wheel notch and a trackpad pan OFF '
          'the panel scroll', (tester) async {
        final h = await pump(tester, mount);
        final below =
            tester.getTopLeft(find.byKey(outsideKey)) + const Offset(200, 40);
        final wheel = TestPointer(1, PointerDeviceKind.mouse);
        wheel.hover(below);
        await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
        await tester.pumpAndSettle();
        expect(h.scroll.offset, greaterThan(0), reason: 'the wheel');

        h.scroll.jumpTo(0);
        await tester.pump();
        final pad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await pad.panZoomStart(below);
        await pad.panZoomUpdate(below, pan: const Offset(0, -60));
        await pad.panZoomEnd();
        await tester.pumpAndSettle();
        expect(h.scroll.offset, greaterThan(0), reason: 'the trackpad');
      });

      testWidgets('a wheel notch inside zooms the view and never scrolls', (
        tester,
      ) async {
        final h = await pump(tester, mount);
        final wheel = TestPointer(1, PointerDeviceKind.mouse);
        wheel.hover(inside(tester));
        await tester.sendEventToBinding(wheel.scroll(const Offset(0, 60)));
        await tester.pumpAndSettle();
        expect(h.emitted, isNotEmpty, reason: 'the canvas took the notch');
        expect(h.scroll.offset, 0);
      });

      testWidgets('a trackpad pan and pinch inside move the view and never '
          'scroll', (tester) async {
        final h = await pump(tester, mount);
        final pad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await pad.panZoomStart(inside(tester));
        await pad.panZoomUpdate(inside(tester), pan: const Offset(0, -60));
        await pad.panZoomUpdate(
          inside(tester),
          pan: const Offset(0, -90),
          scale: 1.4,
        );
        await pad.panZoomEnd();
        await tester.pumpAndSettle();
        expect(h.emitted, isNotEmpty, reason: 'the canvas took the gesture');
        expect(h.scroll.offset, 0);
      });
    });
  }

  testWidgets("the viewer's one finger pans the view and never scrolls", (
    tester,
  ) async {
    final h = await pump(tester, viewer);
    await drag(tester, inside(tester), PointerDeviceKind.touch);
    expect(h.emitted, isNotEmpty, reason: 'the viewer pans on one finger');
    expect(h.scroll.offset, 0);
  });

  /// The canvas's own layer with a claimed control under the whole of it —
  /// the playback view's stop, a conte cell, the header editor's tap-away.
  Future<({List<int> presses, List<CanvasViewport> emitted})> pumpClaimed(
    WidgetTester tester,
  ) async {
    final presses = <int>[];
    final emitted = <CanvasViewport>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: CanvasViewportGestureLayer(
              viewport: CanvasViewport(),
              onViewportChanged: emitted.add,
              child: ControlPressClaim(
                onPressed: () => presses.add(presses.length),
                child: const ColoredBox(
                  color: Color(0xFF102030),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (presses: presses, emitted: emitted);
  }

  group('a press the canvas turned into a gesture is not a click', () {
    testWidgets('a finger that wobbles and lifts is still a tap', (
      tester,
    ) async {
      final h = await pumpClaimed(tester);
      final g = await tester.startGesture(
        const Offset(120, 120),
        kind: PointerDeviceKind.touch,
      );
      await g.moveBy(const Offset(3, -4));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(h.presses, hasLength(1));
    });

    testWidgets('a two-finger pan that lifts inside fires nothing', (
      tester,
    ) async {
      final h = await pumpClaimed(tester);
      await twoFingerPan(tester, const Offset(120, 250));
      expect(h.emitted, isNotEmpty, reason: 'the pan ran');
      expect(h.presses, isEmpty);
    });

    testWidgets('a space + mouse pan that lifts inside fires nothing', (
      tester,
    ) async {
      final h = await pumpClaimed(tester);
      CanvasPanHold.held.value = true;
      await tester.pump();
      final g = await tester.startGesture(
        const Offset(120, 250),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, -60));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(h.emitted, isNotEmpty, reason: 'the pan ran');
      expect(h.presses, isEmpty);
    });

    testWidgets('a plain mouse drag inside is still a click — the button '
        'law, pressed and released inside', (tester) async {
      final h = await pumpClaimed(tester);
      final g = await tester.startGesture(
        const Offset(120, 250),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, -60));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(h.emitted, isEmpty, reason: 'a plain mouse press does not pan');
      expect(h.presses, hasLength(1));
    });

    testWidgets('a one-finger flip past the slop that never stepped lifts '
        'as no tap', (tester) async {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      final h = await pumpClaimed(tester);
      final g = await tester.startGesture(
        const Offset(120, 150),
        kind: PointerDeviceKind.touch,
      );
      // Past the slop every group locks at, short of the distance a flip
      // needs before it steps (H30): no step ran, and it is still no tap.
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(h.presses, isEmpty);
    });

    testWidgets("a pinch's still finger lifts as no tap", (tester) async {
      final h = await pumpClaimed(tester);
      final still = await tester.startGesture(
        const Offset(120, 150),
        kind: PointerDeviceKind.touch,
        pointer: 21,
      );
      final moving = await tester.startGesture(
        const Offset(220, 150),
        kind: PointerDeviceKind.touch,
        pointer: 22,
      );
      for (var i = 0; i < 4; i++) {
        await moving.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await moving.up();
      await tester.pump();
      await still.up();
      await tester.pumpAndSettle();
      expect(h.emitted, isNotEmpty, reason: 'the pinch ran');
      expect(h.presses, isEmpty);
    });

    testWidgets('a finger that joins a running pinch lifts as no tap', (
      tester,
    ) async {
      final h = await pumpClaimed(tester);
      final a = await tester.startGesture(
        const Offset(120, 200),
        kind: PointerDeviceKind.touch,
        pointer: 41,
      );
      final b = await tester.startGesture(
        const Offset(220, 200),
        kind: PointerDeviceKind.touch,
        pointer: 42,
      );
      for (var i = 0; i < 3; i++) {
        await a.moveBy(const Offset(0, -20));
        await b.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      final joined = await tester.startGesture(
        const Offset(300, 250),
        kind: PointerDeviceKind.touch,
        pointer: 43,
      );
      await tester.pump();
      await joined.up();
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(h.emitted, isNotEmpty, reason: 'the pinch ran');
      expect(h.presses, isEmpty);
    });

    testWidgets('a claim ends with its gesture — the same pointer id taps '
        'afterwards', (tester) async {
      final h = await pumpClaimed(tester);
      await twoFingerPan(tester, const Offset(120, 250));
      expect(h.presses, isEmpty);
      final g = await tester.startGesture(
        const Offset(120, 120),
        kind: PointerDeviceKind.touch,
        pointer: 11,
      );
      await g.up();
      await tester.pumpAndSettle();
      expect(h.presses, hasLength(1));
    });

    testWidgets('a canvas torn down mid-gesture lets its claim go', (
      tester,
    ) async {
      await pumpClaimed(tester);
      CanvasPanHold.held.value = true;
      await tester.pump();
      final g = await tester.startGesture(
        const Offset(120, 250),
        kind: PointerDeviceKind.mouse,
        pointer: 31,
      );
      expect(valueControlOwnsPointer(31), isTrue, reason: 'the pan is claimed');
      await tester.pumpWidget(const SizedBox());
      expect(valueControlOwnsPointer(31), isFalse);
      await g.up();
    });
  });

  testWidgets('a handle on the canvas keeps its own drag', (tester) async {
    final committed = <CanvasPoint>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: CanvasViewportGestureLayer(
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              child: CanvasPointGizmo(
                glyph: HandleGlyph.crosshair,
                point: CanvasPoint(x: 100, y: 80),
                viewport: CanvasViewport(),
                onCommitted: committed.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // ON the handle: it sits at the point, (100, 80) under an identity view.
    await tester.dragFrom(
      tester.getTopLeft(find.byType(CanvasPointGizmo)) + const Offset(100, 80),
      const Offset(48, -20),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pumpAndSettle();
    expect(committed, hasLength(1), reason: 'the surface held nothing back');
  });

  testWidgets('a drag verb below the surface is made way for', (tester) async {
    var updates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: CanvasViewportGestureLayer(
              viewport: CanvasViewport(),
              onViewportChanged: (_) {},
              child: DragVerbClaim(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (_) => updates++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final g = await tester.startGesture(
      const Offset(120, 120),
      kind: PointerDeviceKind.mouse,
    );
    // ⚠️ONE PIXEL A STEP, and that is the whole case. A first move past the
    // verb's own slop lets the deeper recogniser win by depth whether the
    // surface makes way or not — twelve pixels passed with the make-way
    // deleted (mutant, 2026-09-15). Under the slop, only making way does.
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(1, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(updates, greaterThan(0), reason: 'the verb below kept its drag');
  });
}
