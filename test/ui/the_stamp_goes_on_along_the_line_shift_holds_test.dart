import 'dart:typed_data';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart'
    show InputInspectorHost;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/device_viewport.dart';

/// 🗣️I-121 (유저 2026-10-21): 「잘라내기 도구의 스탬프도 쉬프트 누른동안 법
/// 통일해서 스냅. 떼면 스냅 끝남.」 · 「스냅 발생하면 쉬프트 떼기 전까지는
/// 같은스냅」 — the stamp's drag goes through the stroke's lock, and its
/// press onto the line the hold kept, on the canvas panel that keeps it.
///
/// At a render zoom of 1 a local offset on the drawing view IS the canvas
/// coordinate, so where the ink went says where the stamps went.
void main() {
  late BrushFrameEditingCoordinator coordinator;

  /// A 2×2 opaque piece.
  CutPiece piece() => CutPiece(
    image: BrushStampImage(
      id: 'piece',
      width: 2,
      height: 2,
      rgba: Uint8List.fromList([
        for (var index = 0; index < 4; index += 1) ...[0xFF, 0, 0, 0xFF],
      ]),
    ),
    originLeft: 0,
    originTop: 0,
  );

  late ValueNotifier<BrushToolState> brush;

  /// The panel with [tool] in hand — the cut tool's shape a lasso.
  Future<void> pumpStamp(
    WidgetTester tester, {
    CanvasTool tool = CanvasTool.cutStamp,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 240, height: 240),
    );
    final slot = CutPieceSlot()..hold(piece());
    addTearDown(slot.dispose);
    brush = ValueNotifier(
      BrushToolState.defaults.copyWith(
        tool: tool,
        cutShape: CanvasShapeKind.lasso,
      ),
    );
    addTearDown(brush.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Under the app's one observer of every pointer, which counts the
          // fingers resting on the glass (`CanvasTouchContacts`).
          body: InputInspectorHost(
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              brushToolState: brush,
              cutPieceSlot: slot,
              viewport: seedFromRender(tester, CanvasViewport()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(CanvasTouchContacts.reset);

  Offset on(WidgetTester tester, Offset canvas) =>
      tester.getTopLeft(find.byType(InteractiveBrushEditCanvasView)) + canvas;

  Future<void> stampAlong(
    WidgetTester tester,
    List<Offset> path, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final mouse = await tester.startGesture(
      on(tester, path.first),
      kind: kind,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    for (final at in path.skip(1)) {
      await mouse.moveTo(on(tester, at));
      await tester.pump();
    }
    await mouse.up();
    await tester.pumpAndSettle();
  }

  ({int left, int top, int rightExclusive, int bottomExclusive}) ink() =>
      bitmapSurfaceContentBounds(
        coordinator.frameStore.bakedSurfaceOrNull(coordinator.activeFrameKey)!,
      )!;

  /// A drag Shift locks onto y = x, through (20, 20), stamped to (60, 60).
  Future<void> alongTheDiagonal(WidgetTester tester) =>
      stampAlong(tester, const [Offset(20, 20), Offset(40, 46), Offset(62, 60)]);

  testWidgets('🚨a drag under Shift stamps along one of the eight ways, as a '
      'stroke goes', (tester) async {
    await pumpStamp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await stampAlong(tester, const [
      Offset(20, 20),
      Offset(60, 66),
      Offset(100, 94),
    ]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final box = ink();
    expect(
      box.bottomExclusive - box.top,
      closeTo(box.rightExclusive - box.left, 2),
      reason: 'the wobble is gone: as tall as it is wide',
    );
  });

  testWidgets('🚨held through the lift, the next press stamps on the line the '
      'hold kept, where it falls across it', (tester) async {
    await pumpStamp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await alongTheDiagonal(tester);
    // (100, 120) falls across y = x at (110, 110).
    await stampAlong(tester, const [Offset(100, 120)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final box = ink();
    expect(box.rightExclusive, inInclusiveRange(110, 113));
    expect(box.bottomExclusive, inInclusiveRange(110, 113));
  });

  testWidgets('🚨and the drag it begins goes on along the line', (
    tester,
  ) async {
    await pumpStamp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await alongTheDiagonal(tester);
    // Nearly level from (110, 110), where the press fell: its own eight ways
    // would lay it flat. Along y = x, (170, 118) is (144, 144).
    await stampAlong(tester, const [Offset(100, 120), Offset(170, 118)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(ink().bottomExclusive, inInclusiveRange(140, 147));
  });

  testWidgets('🚨let go between them, the press stamps where it is', (
    tester,
  ) async {
    await pumpStamp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await alongTheDiagonal(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await stampAlong(tester, const [Offset(100, 120)]);

    final box = ink();
    expect(box.bottomExclusive, inInclusiveRange(120, 123));
    expect(box.rightExclusive, inInclusiveRange(100, 103));
  });

  // ONE line for the panel: whichever path the hand drew under the hold,
  // the stamp's press goes on along it.
  for (final (verb, tool) in [
    ('a stroke', CanvasTool.brush),
    ('a lasso', CanvasTool.cut),
  ]) {
    testWidgets('🚨the line $verb locked under the hold is the one the stamp '
        'presses onto', (tester) async {
      await pumpStamp(tester, tool: tool);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await alongTheDiagonal(tester);
      brush.value = brush.value.copyWith(tool: CanvasTool.cutStamp);
      await tester.pumpAndSettle();
      await stampAlong(tester, const [Offset(100, 120)]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(ink().bottomExclusive, inInclusiveRange(110, 113));
      // The cut tool's drag leaves a timer running (measured): it runs out.
      await tester.pump(const Duration(seconds: 10));
    });
  }

  testWidgets('🚨Shift pressed anew between them is a new hold: the press '
      'stamps where it is', (tester) async {
    await pumpStamp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await alongTheDiagonal(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await stampAlong(tester, const [Offset(100, 120)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final box = ink();
    expect(box.bottomExclusive, inInclusiveRange(120, 123));
    expect(box.rightExclusive, inInclusiveRange(100, 103));
  });

  testWidgets('what the lock still held when the hand lifted is stamped', (
    tester,
  ) async {
    await pumpStamp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final mouse = await tester.startGesture(
      on(tester, const Offset(20, 20)),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    // Too short a travel to have chosen a way: held.
    await mouse.moveTo(on(tester, const Offset(24, 21)));
    await tester.pump();
    final pressed = ink().rightExclusive;
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(ink().rightExclusive, greaterThan(pressed));
  });

  /// 🗣️I-121-Q1 (유저 2026-10-22): 「손가락도 — 세는 곳을 하나로 묶고
  /// 나서」 — a finger resting beside a pen's drag is its Shift, behind the
  /// switch a stroke's finger has, counted where every modifier finger is.
  group('a finger resting on the glass', () {
    void fingers({required bool shift, required bool draw}) {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        strokeFingerModifier: shift,
        touchDragOneFinger: draw
            ? CanvasTouchDragAction.draw
            : CanvasTouchDragAction.navigate,
      );
      addTearDown(
        () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
      );
    }

    /// A finger laid down on the canvas, away from every stamp. Laid down
    /// before a pen's press it navigates (`draw: false`): one that draws is a
    /// press of its own there, a tap that stamps where it lifts.
    Future<TestGesture> rest(WidgetTester tester, {int pointer = 9}) async {
      final finger = await tester.startGesture(
        on(tester, const Offset(200, 200)),
        kind: PointerDeviceKind.touch,
        pointer: pointer,
      );
      await tester.pump();
      return finger;
    }

    Future<void> lift(WidgetTester tester, TestGesture finger) async {
      await finger.up();
      await tester.pumpAndSettle();
    }

    const wobble = [Offset(20, 20), Offset(60, 66), Offset(100, 94)];

    bool square() {
      final box = ink();
      return ((box.bottomExclusive - box.top) - (box.rightExclusive - box.left))
              .abs() <=
          2;
    }

    testWidgets('🚨with the switch on, it is a pen\'s drag\'s Shift: the drag '
        'stamps along one of the eight ways', (tester) async {
      fingers(shift: true, draw: false);
      await pumpStamp(tester);
      final finger = await rest(tester);
      await stampAlong(tester, wobble, kind: PointerDeviceKind.stylus);
      await lift(tester, finger);

      expect(square(), isTrue, reason: 'the wobble is gone');
    });

    testWidgets('⛔with the switch off — as it comes — it is nothing', (
      tester,
    ) async {
      fingers(shift: false, draw: false);
      await pumpStamp(tester);
      final finger = await rest(tester);
      await stampAlong(tester, wobble, kind: PointerDeviceKind.stylus);
      await lift(tester, finger);

      expect(square(), isFalse, reason: 'the wobble is kept');
    });

    testWidgets('⛔a finger\'s own drag takes none: beside it a second finger '
        'is what it always was', (tester) async {
      fingers(shift: true, draw: true);
      await pumpStamp(tester);
      final drawing = await tester.startGesture(
        on(tester, const Offset(20, 20)),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      await tester.pump();
      await drawing.moveTo(on(tester, const Offset(60, 66)));
      await tester.pump();
      final finger = await rest(tester);
      // Nearly level from (60, 66): locked, it would stay at y = 66.
      await drawing.moveTo(on(tester, const Offset(100, 70)));
      await tester.pump();
      await drawing.up();
      await tester.pumpAndSettle();
      await lift(tester, finger);

      expect(ink().bottomExclusive, inInclusiveRange(71, 73), reason: 'free');
    });

    for (final cancelled in [false, true]) {
      final leaving = cancelled ? 'cancelled' : 'lifted';
      testWidgets('🚨landing in the middle of a pen\'s drag it takes nothing '
          'of it: the drag goes on, and $leaving it stamps nothing', (
        tester,
      ) async {
        fingers(shift: false, draw: true);
        await pumpStamp(tester);
        final pen = await tester.startGesture(
          on(tester, const Offset(20, 20)),
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton,
        );
        await tester.pump();
        await pen.moveTo(on(tester, const Offset(60, 20)));
        await tester.pump();
        final finger = await rest(tester);
        await pen.moveTo(on(tester, const Offset(100, 20)));
        await tester.pump();
        if (cancelled) {
          await finger.cancel();
          await tester.pump();
        } else {
          await lift(tester, finger);
        }
        await pen.moveTo(on(tester, const Offset(180, 20)));
        await tester.pump();
        await pen.up();
        await tester.pumpAndSettle();

        final box = ink();
        expect(box.rightExclusive, inInclusiveRange(180, 183));
        expect(box.bottomExclusive, lessThan(30), reason: 'none under it');
      });
    }

    testWidgets('🚨held while it rests, the next press stamps on the line '
        'the hold kept', (tester) async {
      fingers(shift: true, draw: false);
      await pumpStamp(tester);
      final finger = await rest(tester);
      await stampAlong(tester, const [
        Offset(20, 20),
        Offset(40, 46),
        Offset(62, 60),
      ], kind: PointerDeviceKind.stylus);
      // (100, 120) falls across y = x at (110, 110).
      await stampAlong(tester, const [
        Offset(100, 120),
      ], kind: PointerDeviceKind.stylus);
      await lift(tester, finger);

      expect(ink().bottomExclusive, inInclusiveRange(110, 113));
    });

    // Lifting it is letting the key go, and the panel — the line's owner —
    // hears it from the count ([CanvasTouchContacts]).
    testWidgets('🚨lifted and laid down again, it is a new hold: the press '
        'stamps where it is', (tester) async {
      fingers(shift: true, draw: false);
      await pumpStamp(tester);
      final first = await rest(tester);
      await stampAlong(tester, const [
        Offset(20, 20),
        Offset(40, 46),
        Offset(62, 60),
      ], kind: PointerDeviceKind.stylus);
      await lift(tester, first);
      final again = await rest(tester, pointer: 10);
      await stampAlong(tester, const [
        Offset(100, 120),
      ], kind: PointerDeviceKind.stylus);
      await lift(tester, again);

      final box = ink();
      expect(box.bottomExclusive, inInclusiveRange(120, 123));
      expect(box.rightExclusive, inInclusiveRange(100, 103));
    });

    testWidgets('🚨of two fingers resting, the first lifted leaves the line '
        'held by the second', (tester) async {
      fingers(shift: true, draw: false);
      await pumpStamp(tester);
      final first = await rest(tester);
      final second = await rest(tester, pointer: 10);
      await stampAlong(tester, const [
        Offset(20, 20),
        Offset(40, 46),
        Offset(62, 60),
      ], kind: PointerDeviceKind.stylus);
      await lift(tester, first);
      // (100, 120) falls across y = x at (110, 110).
      await stampAlong(tester, const [
        Offset(100, 120),
      ], kind: PointerDeviceKind.stylus);
      await lift(tester, second);

      expect(ink().bottomExclusive, inInclusiveRange(110, 113));
    });
  });
}
