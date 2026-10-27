import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/transform_values.dart';
import 'package:anicel/src/services/stamp_carry.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';

/// 🗣️I-136 (유저 2026-10-27): 「카메라 이동할때나 fx의 트랜스폼
/// 이동할때등 캔버스에서 어떤 조작 할때도 쉬프트 통해 누른상태면
/// 한쪽으로만. 즉 x,y가 있다치면 x 안건들고 y만 이동한다던가」.
///
/// The selection's moves — the Move tool's drag, the inside of the box it
/// opens, the box's cross, a 퍼스 corner — keep to the one way the hand
/// went further while Shift is held: the key, or a finger beside a pen's
/// drag.
void main() {
  const canvasSize = CanvasSize(width: 400, height: 300);

  setUp(CanvasTouchContacts.reset);
  tearDown(CanvasTouchContacts.reset);

  /// One picture over (40..240, 40..140): the box's middle is (140, 90).
  final picture = BrushDab(
    center: CanvasPoint(x: 140, y: 90),
    color: 0xFF000000,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: BrushStampImage(
      id: 'p',
      width: 200,
      height: 100,
      rgba: Uint8List.fromList([
        for (var i = 0; i < 200 * 100; i += 1) ...[40, 90, 200, 255],
      ]),
    ),
  );

  Future<({CanvasSelectionCommands commands, List<StampCarry?> carries})>
  pumpLayer(
    WidgetTester tester, {
    TransformMode mode = TransformMode.normal,
  }) async {
    final commands = CanvasSelectionCommands();
    final slot = SelectionFloatOverlay(null);
    addTearDown(slot.dispose);
    final carries = <StampCarry?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: CanvasSelectionLayer(
                tool: CanvasSelectionTool.move,
                viewport: CanvasViewport(),
                pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
                frameToken: 'frame',
                selectionCommands: commands,
                alwaysShowTransformBox: true,
                transformOptions: TransformToolOptions(mode: mode),
                contentBoundsProvider: () => (
                  left: 40,
                  top: 40,
                  rightExclusive: 240,
                  bottomExclusive: 140,
                ),
                onLiftRequested: (region) => (
                  liftToken: 7,
                  floats: [(stampDab: picture, showsOn: slot, landsOn: null)],
                ),
                onLiftConfirmed: (token, stamps, carry) => carries.add(carry),
                onLiftReverted: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (commands: commands, carries: carries);
  }

  /// A mouse's drag from [from] through [steps], Shift held through it
  /// when [shift].
  Future<void> drag(
    WidgetTester tester,
    Offset from,
    List<Offset> steps, {
    bool shift = true,
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    if (shift) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    final hand = await tester.startGesture(
      from,
      kind: kind,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    for (final step in steps) {
      await hand.moveBy(step);
      await tester.pump();
    }
    await hand.up();
    await tester.pump();
    if (shift) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  }

  (double, double) moveOf(TransformValues? values) =>
      (values!.tx, values.ty);

  testWidgets('the Move tool\'s drag goes across alone, or down alone — '
      'whichever the hand went further', (tester) async {
    final env = await pumpLayer(tester);

    await drag(tester, const Offset(100, 60), [
      const Offset(20, -4),
      const Offset(10.4, -8),
    ]);

    expect(moveOf(env.commands.transformValues), (30.0, 0.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('↩️without Shift it goes where the hand went', (tester) async {
    final env = await pumpLayer(tester);

    await drag(tester, const Offset(100, 60), [
      const Offset(20, -4),
      const Offset(10.4, -8),
    ], shift: false);

    expect(moveOf(env.commands.transformValues), (30.0, -12.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the inside of the box already open keeps to one way too', (
    tester,
  ) async {
    final env = await pumpLayer(tester);
    env.commands.beginTransform();
    await tester.pump();

    await drag(tester, const Offset(100, 60), [
      const Offset(4, 20),
      const Offset(-6, 15.6),
    ]);

    expect(moveOf(env.commands.transformValues), (0.0, 36.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the box\'s CROSS keeps to one way', (tester) async {
    final env = await pumpLayer(tester);
    env.commands.beginTransform();
    await tester.pump();

    await drag(tester, const Offset(140, 90), [
      const Offset(20, 3),
      const Offset(5, 4),
    ]);

    final values = env.commands.transformValues!;
    expect((values.anchorX, values.anchorY), (25.0, 0.0));
    expect(moveOf(values), (0.0, 0.0), reason: 'the cross, not the inside');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 퍼스 corner keeps to one way on the canvas', (tester) async {
    final env = await pumpLayer(tester, mode: TransformMode.perspective);
    env.commands.beginTransform();
    await tester.pump();

    await drag(tester, const Offset(240, 140), [
      const Offset(5, 10),
      const Offset(10, 10),
    ]);
    env.commands.applyTransform();
    await tester.pump();

    final carry = env.carries.single;
    expect(carry, isA<QuadCarry>(), reason: '⛔premise: the corner made one');
    final corners = (carry! as QuadCarry).corners;
    expect(
      [for (final c in corners) (c.x, c.y)],
      [(40.0, 40.0), (240.0, 40.0), (240.0, 160.0), (40.0, 140.0)],
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finger resting beside a PEN\'s move is its Shift — the '
      'tablet\'s key', (tester) async {
    final env = await pumpLayer(tester);
    CanvasTouchContacts.noteAppWide(
      const PointerDownEvent(pointer: 90, kind: PointerDeviceKind.touch),
    );

    await drag(
      tester,
      const Offset(100, 60),
      [const Offset(20, -4), const Offset(10.4, -8)],
      shift: false,
      kind: PointerDeviceKind.stylus,
    );

    expect(moveOf(env.commands.transformValues), (30.0, 0.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('⛔a FINGER\'s own move takes no Shift from a second finger: '
      'the pair is a screen gesture still, and the move is let go', (
    tester,
  ) async {
    final env = await pumpLayer(tester);
    final hand = await tester.startGesture(
      const Offset(100, 60),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await hand.moveBy(const Offset(30, 8));
    await tester.pump();
    expect(
      moveOf(env.commands.transformValues),
      (30.0, 8.0),
      reason: '⛔premise: a finger moves it',
    );

    final second = await tester.startGesture(
      const Offset(300, 250),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    await hand.moveBy(const Offset(10, 20));
    await tester.pump();
    await second.up();
    await hand.up();
    await tester.pump();

    expect(
      moveOf(env.commands.transformValues),
      (30.0, 8.0),
      reason: 'neither kept to one way (40, 0) nor carried on (40, 28): the '
          'second finger let the move go where it found it',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
