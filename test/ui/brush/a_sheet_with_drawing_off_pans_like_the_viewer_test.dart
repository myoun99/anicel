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
import 'package:anicel/src/models/canvas_size.dart';
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

  /// A 400×300 sheet, drawing on or off, with a claimed control in its top
  /// left corner — the part a timesheet head cell plays.
  Future<({List<CanvasViewport> emitted, List<int> pressed})> pump(
    WidgetTester tester, {
    required bool drawing,
  }) async {
    final emitted = <CanvasViewport>[];
    final pressed = <int>[];
    final stroke = ValueNotifier<bool>(false);
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
              canvasSize: const CanvasSize(width: 600, height: 800),
              viewport: CanvasViewport(),
              onViewportChanged: emitted.add,
              contentStrokeActive: drawing ? stroke : null,
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
  });

  testWidgets("⛔drawing ON: a plain mouse drag is not the view's", (
    tester,
  ) async {
    final h = await pump(tester, drawing: true);
    await drag(tester, free(tester), PointerDeviceKind.mouse);
    expect(h.emitted, isEmpty);
  });
}
