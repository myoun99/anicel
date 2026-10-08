// F-80 ①: A SHEET WHOSE DRAWING IS OFF PANS LIKE THE VIEWER — one finger and
// a plain click-drag move the view, and a press on a control on the sheet
// stays the control's.
//
// A sheet with drawing off takes no strokes, so it is a canvas panel with no
// drawing mode; the viewer's answer for that is already law (I-14, 유저
// 2026-09-11: 「뷰어패널은 기본적으로 드로잉모드 존재안하니 한손가락 핑거시
// 팬」).
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';

void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    debugClearValueControlPointers();
  });

  const controlKey = ValueKey<String>('f80-sheet-control');
  const cellKey = ValueKey<String>('f214-sheet-cell');

  /// A 400×300 sheet, drawing on or off, with a claimed control in its top
  /// left corner — a button on the sheet — and a cell of its paper at
  /// (200, 100)–(280, 140): the part a timesheet head cell and a conte
  /// cell's words and picture play (F-214).
  Future<({List<CanvasViewport> emitted, List<int> pressed})> pump(
    WidgetTester tester, {
    required bool drawing,
  }) async {
    final emitted = <CanvasViewport>[];
    final pressed = <int>[];
    final stroke = SheetStrokeHold(brushInput: (_) {});
    addTearDown(stroke.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: SheetCanvasPanel(
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              sheetSize: const Size(600, 800),
              viewLimit: null,
              viewport: CanvasViewport(),
              onViewportChanged: emitted.add,
              drawingOn: drawing,
              strokeHold: stroke,
              content: (context, viewport) => Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 80,
                    height: 40,
                    child: ControlPressClaim(
                      key: controlKey,
                      onPressed: () => pressed.add(1),
                      child: const ColoredBox(color: Color(0xFF406080)),
                    ),
                  ),
                  Positioned(
                    left: 200,
                    top: 100,
                    width: 80,
                    height: 40,
                    child: PressFireScope(
                      fireOn: PressFire.upInsideOrPan,
                      child: ControlPressClaim(
                        key: cellKey,
                        onPressed: () => pressed.add(2),
                        child: const ColoredBox(color: Color(0xFF608040)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Whatever the first layout framed is not a pan.
    emitted.clear();
    return (emitted: emitted, pressed: pressed);
  }

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    PointerDeviceKind kind,
  ) async {
    final gesture = await tester.startGesture(from, kind: kind);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(12, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Offset free(WidgetTester tester) =>
      tester.getCenter(find.byType(SheetCanvasPanel));

  group('drawing OFF', () {
    for (final kind in const [
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
    ]) {
      testWidgets('a plain ${kind.name} drag pans the view', (tester) async {
        final h = await pump(tester, drawing: false);
        await drag(tester, free(tester), kind);
        expect(h.emitted, isNotEmpty);
      });
    }

    testWidgets('one finger pans the view, whatever the one-finger slot says', (
      tester,
    ) async {
      final h = await pump(tester, drawing: false);
      expect(
        AppInput.settings.value.touchDragOneFinger,
        CanvasTouchDragAction.draw,
        reason: 'fixture premise: the slot says draw',
      );
      await drag(tester, free(tester), PointerDeviceKind.touch);
      expect(h.emitted, isNotEmpty);
    });

    testWidgets("⛔a drag that starts on a control is the control's — the "
        'view stays', (tester) async {
      final h = await pump(tester, drawing: false);
      await drag(
        tester,
        tester.getCenter(find.byKey(controlKey)),
        PointerDeviceKind.mouse,
      );
      expect(h.emitted, isEmpty);
    });

    testWidgets('⛔and a click on the control still presses it', (tester) async {
      final h = await pump(tester, drawing: false);
      await tester.tap(find.byKey(controlKey));
      await tester.pumpAndSettle();
      expect(h.pressed, [1]);
      expect(h.emitted, isEmpty);
    });

    // 🗣️F-214 (유저 2026-09-28): 「해당 칸 내에서 펜업하면 창
    // 열리게하고, 아니면 그냥 드래그 작동하도록. 픽쳐칸도 똑같음」.
    group('a cell of the paper', () {
      for (final kind in const [
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
      ]) {
        testWidgets('${kind.name}: a click presses it', (tester) async {
          final h = await pump(tester, drawing: false);
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(cellKey)),
            kind: kind,
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(h.pressed, [2]);
          expect(h.emitted, isEmpty);
        });

        testWidgets('${kind.name}: a hand that wobbles inside it still '
            'presses it, and the view stays', (tester) async {
          final h = await pump(tester, drawing: false);
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(cellKey)),
            kind: kind,
          );
          for (final step in const [
            Offset(3, 2),
            Offset(-5, 1),
            Offset(1, -4),
          ]) {
            await gesture.moveBy(step);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(h.pressed, [2]);
          expect(h.emitted, isEmpty);
        });

        // 🗣️H53 (유저 2026-09-30): 「그냥 클릭한다=클릭, 드래그=바로스크롤」.
        testWidgets('${kind.name}: a drag pans the moment it passes the touch '
            'slop — inside the cell, from where it passed it — and does not '
            'press it', (tester) async {
          final h = await pump(tester, drawing: false);
          // From the middle (240, 120), 12 a step to the right: 252 is a
          // hand that wobbles; 264 is past the slop (18), where the pan
          // starts — well inside the cell, whose right edge is 280 — and on
          // to 276, 288, 300 and 312.
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(cellKey)),
            kind: kind,
          );
          for (var i = 0; i < 6; i += 1) {
            await gesture.moveBy(const Offset(12, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(h.pressed, isEmpty);
          // The first view the pan gives is where the press passed the slop
          // — not the press, so the view does not jump — and the last is 48
          // points further, in the view's device pixels.
          expect(h.emitted, hasLength(5), reason: 'at 264, 276 … 312');
          expect(
            h.emitted.last.panX - h.emitted.first.panX,
            48 * tester.view.devicePixelRatio,
            reason: '312 − 264',
          );
          expect(h.emitted.last.panY, h.emitted.first.panY);
        });

        testWidgets('${kind.name}: a drag that leaves it and comes back does '
            'not press it', (tester) async {
          final h = await pump(tester, drawing: false);
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(cellKey)),
            kind: kind,
          );
          for (final step in const [
            Offset(30, 0),
            Offset(30, 0),
            Offset(-30, 0),
            Offset(-30, 0),
          ]) {
            await gesture.moveBy(step);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(h.pressed, isEmpty);
          expect(h.emitted, isNotEmpty, reason: 'it panned while out');
        });
      }
    });
  });

  // The cell's own half of the law, with no canvas around it to take the
  // press as a pan: a press that left the cell is not the cell's, even
  // when it comes back inside to let go.
  testWidgets('a cell alone: a press that leaves it and comes back does not '
      'press it, nor one that goes past the slop inside it (H53) — one that '
      'stays within the slop does', (tester) async {
    final pressed = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 80,
            height: 40,
            child: PressFireScope(
              fireOn: PressFire.upInsideOrPan,
              child: ControlPressClaim(
                key: cellKey,
                onPressed: () => pressed.add(2),
                child: const ColoredBox(color: Color(0xFF608040)),
              ),
            ),
          ),
        ),
      ),
    );
    final left = await tester.startGesture(
      const Offset(40, 20),
      kind: PointerDeviceKind.mouse,
    );
    await left.moveTo(const Offset(120, 20));
    await tester.pump();
    await left.moveTo(const Offset(40, 20));
    await tester.pump();
    await left.up();
    await tester.pumpAndSettle();
    expect(pressed, isEmpty);

    // 30 across and 10 down, still inside the 80 × 40 cell: past the slop.
    final dragged = await tester.startGesture(
      const Offset(40, 20),
      kind: PointerDeviceKind.mouse,
    );
    await dragged.moveTo(const Offset(70, 30));
    await tester.pump();
    await dragged.up();
    await tester.pumpAndSettle();
    expect(pressed, isEmpty);

    final stayed = await tester.startGesture(
      const Offset(40, 20),
      kind: PointerDeviceKind.mouse,
    );
    await stayed.moveTo(const Offset(50, 26));
    await tester.pump();
    await stayed.up();
    await tester.pumpAndSettle();
    expect(pressed, [2]);
  });

  testWidgets("⛔drawing ON: a plain mouse drag is not the view's", (
    tester,
  ) async {
    final h = await pump(tester, drawing: true);
    await drag(tester, free(tester), PointerDeviceKind.mouse);
    expect(h.emitted, isEmpty);
  });
}
