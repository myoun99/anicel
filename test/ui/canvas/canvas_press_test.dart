import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/ui/canvas/canvas_pan_hold.dart';
import 'package:anicel/src/ui/canvas/canvas_press.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

/// What a press on the canvas IS — read once, for the pan, for the stroke,
/// and for the empty cel that asks whether the press will draw (I-15
/// follow-up, 유저 2026-09-11: 「스페이스바 하고 클릭하면 … 프레임이
/// 존재하지 않는다는 메시지 안뜨도록 … 근본적/구조적으로 해결」).
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    CanvasPanHold.held.value = false;
  });

  void map({CanvasPointerAction? right, CanvasPointerAction? wheel}) {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      canvasRightClick: right == null
          ? null
          : CanvasPointerMapping(action: right),
      canvasWheelClick: wheel == null
          ? null
          : CanvasPointerMapping(action: wheel),
    );
  }

  bool draws(
    int buttons, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    bool penTailActive = false,
  }) => canvasPressDraws(
    PointerDownEvent(kind: kind, buttons: buttons),
    penTailActive: penTailActive,
  );

  const tipAndBarrel = kPrimaryButton | kSecondaryButton;

  group("whose a press is — the tool in hand's, or not", () {
    /// The raw pen service saying which end of the pen is down — each
    /// call a new report.
    var reports = 0;
    void penIs({required bool turnedOver}) {
      final raw = RawPenInputService.instance;
      if (reports == 0) {
        addTearDown(() {
          raw.debugReset();
          reports = 0;
        });
        RawPenInputService.debugClockOverride = () => DateTime(2024);
        raw.debugPollOverride = () => null;
        raw.start();
      }
      reports += 1;
      raw.debugInjectState(
        QaPenRawState(flags: turnedOver ? 0x08 : 0, sequence: reports),
      );
    }

    void tailIs(CanvasPointerAction action) =>
        AppInput.settings.value = AppInput.settings.value.copyWith(
          canvasPenTail: CanvasPointerMapping(action: action),
        );

    bool isTheTools(
      int buttons, {
      PointerDeviceKind kind = PointerDeviceKind.stylus,
      bool Function(CanvasPointerAction tail)? tailsToolInHand,
    }) => canvasPressIsTheTools(
      PointerDownEvent(kind: kind, buttons: buttons),
      tailsToolInHand: tailsToolInHand ?? (_) => false,
    );

    test('the plain primary contact is; a press with a mapped button down '
        'is that button\'s', () {
      expect(isTheTools(kPrimaryButton), isTrue);
      expect(isTheTools(tipAndBarrel), isFalse);
      expect(isTheTools(kSecondaryButton), isFalse);
      expect(
        isTheTools(kSecondaryMouseButton, kind: PointerDeviceKind.mouse),
        isFalse,
      );
      expect(
        isTheTools(kPrimaryButton, kind: PointerDeviceKind.mouse),
        isTrue,
      );
    });

    test('a finger has no buttons to map and no tail: it is', () {
      penIs(turnedOver: true);
      expect(isTheTools(kPrimaryButton, kind: PointerDeviceKind.touch), isTrue);
    });

    test('🚨a pen turned TAIL-DOWN presses with the tail\'s tool: its contact '
        'is the layer\'s only where that is the tool in hand', () {
      penIs(turnedOver: true);
      expect(canvasPenTailAction(), CanvasPointerAction.eraser);
      expect(isTheTools(kPrimaryButton), isFalse);

      tailIs(CanvasPointerAction.eyedropper);
      expect(canvasPenTailAction(), CanvasPointerAction.eyedropper);
      expect(
        isTheTools(
          kPrimaryButton,
          tailsToolInHand: (tail) => tail == CanvasPointerAction.eyedropper,
        ),
        isTrue,
        reason: 'the eyedropper in hand IS the tail\'s tool',
      );
      expect(
        isTheTools(
          kPrimaryButton,
          tailsToolInHand: (tail) => tail == CanvasPointerAction.eraser,
        ),
        isFalse,
      );
    });

    test('a tail mapped to nothing a contact makes is not a tail here, and '
        'neither is a pen held upright', () {
      penIs(turnedOver: true);
      for (final action in [
        CanvasPointerAction.none,
        CanvasPointerAction.pan,
        CanvasPointerAction.undo,
        CanvasPointerAction.redo,
      ]) {
        tailIs(action);
        expect(canvasPenTailAction(), isNull, reason: action.name);
        expect(isTheTools(kPrimaryButton), isTrue, reason: action.name);
      }

      tailIs(CanvasPointerAction.eraser);
      penIs(turnedOver: false);
      expect(canvasPenTailAction(), isNull);
      expect(isTheTools(kPrimaryButton), isTrue);
    });

    test('with no driver to say which end is down, a pen is upright', () {
      expect(canvasPenTailAction(), isNull);
      expect(isTheTools(kPrimaryButton), isTrue);
    });
  });

  test('the primary button pans only while the 「이동」 key is held', () {
    expect(canvasPressPans(kPrimaryButton), isFalse);
    CanvasPanHold.held.value = true;
    expect(canvasPressPans(kPrimaryButton), isTrue);
    expect(
      canvasPressPans(tipAndBarrel),
      isTrue,
      reason: 'per bit: a barrel held with the tip is still the tip',
    );
    expect(canvasPressPans(0), isFalse, reason: 'a hover presses nothing');
  });

  test('a button pans when its canvas mapping says so — and the wheel no '
      'longer does by default (「잔재 삭제」)', () {
    expect(canvasPressPans(kMiddleMouseButton), isFalse);
    expect(canvasPressPans(kSecondaryMouseButton), isFalse);
    map(wheel: CanvasPointerAction.pan);
    expect(canvasPressPans(kMiddleMouseButton), isTrue);
    expect(canvasPressPans(kSecondaryMouseButton), isFalse);
    map(right: CanvasPointerAction.pan);
    expect(canvasPressPans(kSecondaryMouseButton), isTrue);
  });

  test('a primary press draws — and not while the held pan takes it', () {
    expect(draws(kPrimaryButton), isTrue);
    expect(draws(kPrimaryButton, kind: PointerDeviceKind.stylus), isTrue);
    CanvasPanHold.held.value = true;
    expect(
      draws(kPrimaryButton),
      isFalse,
      reason: 'the held 「이동」 takes the press',
    );
  });

  test('a press a mapped button claims draws only when the mapping '
      'erases', () {
    // The defaults: right = the eyedropper hold, wheel = nothing.
    expect(draws(kSecondaryMouseButton), isFalse);
    expect(draws(kMiddleMouseButton), isFalse);
    expect(
      draws(tipAndBarrel, kind: PointerDeviceKind.stylus),
      isFalse,
      reason: 'a barrel held with the tip is the eyedropper hold — the '
          'stroke path hands it to the mapping',
    );
    map(right: CanvasPointerAction.undo);
    expect(draws(tipAndBarrel, kind: PointerDeviceKind.stylus), isFalse);
    map(right: CanvasPointerAction.pan);
    expect(
      draws(tipAndBarrel, kind: PointerDeviceKind.stylus),
      isFalse,
      reason: 'a barrel mapped to the pan pans',
    );
    map(right: CanvasPointerAction.eraser);
    expect(
      draws(kSecondaryMouseButton),
      isTrue,
      reason: 'the eraser hold IS a stroke',
    );
    expect(draws(tipAndBarrel, kind: PointerDeviceKind.stylus), isTrue);
  });

  test('a live tail hold owns the tool: the barrel claims nothing, and the '
      'tip draws', () {
    expect(
      draws(
        tipAndBarrel,
        kind: PointerDeviceKind.stylus,
        penTailActive: true,
      ),
      isTrue,
    );
  });

  test('a finger draws exactly when its one-finger slot says draw', () {
    expect(draws(kPrimaryButton, kind: PointerDeviceKind.touch), isTrue);
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.navigate,
    );
    expect(
      draws(kPrimaryButton, kind: PointerDeviceKind.touch),
      isFalse,
      reason: 'R27 #15: a finger that navigates is not drawing',
    );
  });

  test('a press with no button down draws nothing', () {
    expect(draws(0), isFalse);
  });

  // 「이동은 확인했는데」 — and it may not be slower than the wheel was: on the
  // whole shell, the held Space and a wheel mapped to the pan move the view
  // by the same amount for the same drag.
  testWidgets('on the shell a held-Space drag pans exactly as far as a wheel '
      'drag mapped to the pan — one pan, whichever door', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // ⚠️On a row with NO cel — the bare project; the app itself opens on a
    // cel (F-211). On a cel the key and then the press, with no frame
    // between them, DRAWS instead (board card
    // `the-pan-key-then-an-instant-press-draws`). This test measures how
    // FAR the pan goes, so it stands where it always stood.
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final layer = find.descendant(
      of: find.byKey(const ValueKey<String>('main-canvas-brush-host')),
      matching: find.byType(CanvasViewportGestureLayer),
    );
    CanvasViewport viewport() =>
        tester.widget<CanvasViewportGestureLayer>(layer).viewport;

    Future<Offset> drag(int buttons, Offset by) async {
      final before = viewport();
      final mouse = await tester.startGesture(
        visibleCanvasPoint(tester),
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await tester.pump();
      for (var step = 0; step < 4; step += 1) {
        await mouse.moveBy(by / 4);
        await tester.pump();
      }
      await mouse.up();
      await tester.pumpAndSettle();
      final after = viewport();
      return Offset(after.panX - before.panX, after.panY - before.panY);
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final held = await drag(kPrimaryButton, const Offset(40, 24));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    map(wheel: CanvasPointerAction.pan);
    final wheel = await drag(kMiddleMouseButton, const Offset(-40, -24));

    expect(held, isNot(Offset.zero), reason: 'LIVENESS — the held Space pans');
    expect(wheel.dx, closeTo(-held.dx, 1e-9), reason: 'the same pan');
    expect(wheel.dy, closeTo(-held.dy, 1e-9), reason: 'the same pan');
  });
}
