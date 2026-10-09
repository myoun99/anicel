import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/stamp_carry.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';

/// I-37 — ONE BOX CARRIES EVERY FLOAT.
///
/// 유저 2026-10-02: 「폴더 전체를 하나로 들도록」. A folder's lift floats one
/// picture per row it holds, and the box over them is ONE box: its pivot is
/// the middle of all of them, every float goes through the same mapping of
/// the canvas, each shows in its own row's slot, and the confirm hands every
/// one of them back. A cel's lift is the same code with one float — the
/// rest of the selection suite is that case.
void main() {
  const canvasSize = CanvasSize(width: 400, height: 300);

  /// A [width]×[height] opaque picture standing at [center].
  BrushDab stampAt(CanvasPoint center, int width, int height, String id) =>
      BrushDab(
        center: center,
        color: 0xFF000000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(
          id: id,
          width: width,
          height: height,
          rgba: Uint8List.fromList([
            for (var i = 0; i < width * height; i += 1) ...[40, 90, 200, 255],
          ]),
        ),
      );

  // Two rows' pictures: A over (40..80, 40..60), B over (200..240,
  // 100..140). What they hold together is (40..240, 40..140), whose middle
  // is (140, 90) — the one box's pivot.
  final a = stampAt(CanvasPoint(x: 60, y: 50), 40, 20, 'a');
  final b = stampAt(CanvasPoint(x: 220, y: 120), 40, 40, 'b');

  Future<
    ({
      CanvasSelectionCommands commands,
      SelectionFloatOverlay slotA,
      SelectionFloatOverlay slotB,
      List<List<BrushDab>> confirmed,
      List<StampCarry?> carries,
      List<int> reverted,
    })
  >
  pumpLayer(
    WidgetTester tester, {
    TransformMode mode = TransformMode.normal,
  }) async {
    final commands = CanvasSelectionCommands();
    // ⚠️Disposed only after the layer is gone: an unmount lands what floats
    // and takes back what it showed, into these.
    final slotA = SelectionFloatOverlay(null);
    final slotB = SelectionFloatOverlay(null);
    addTearDown(() {
      slotA.dispose();
      slotB.dispose();
    });
    final confirmed = <List<BrushDab>>[];
    final carries = <StampCarry?>[];
    final reverted = <int>[];
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
                canvasSize: canvasSize,
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
                  floats: [
                    (stampDab: a, showsOn: slotA),
                    (stampDab: b, showsOn: slotB),
                  ],
                ),
                onLiftConfirmed: (token, stamps, carry) {
                  confirmed.add(stamps);
                  carries.add(carry);
                },
                onLiftReverted: reverted.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (
      commands: commands,
      slotA: slotA,
      slotB: slotB,
      confirmed: confirmed,
      carries: carries,
      reverted: reverted,
    );
  }

  testWidgets('every float shows in its OWN slot, moved by the one box', (
    tester,
  ) async {
    final env = await pumpLayer(tester);
    env.commands.beginTransform();
    await tester.pump();
    env.commands.editTransformValues((now) => now.copyWith(tx: 10, ty: 5));
    await tester.pump();

    ({int left, int top, int right, int bottom})? shown(
      SelectionFloatOverlay slot,
    ) {
      final float = slot.value;
      final ink = float?.surface == null
          ? null
          : bitmapSurfaceContentBounds(float!.surface!.surface);
      if (ink == null) {
        return null;
      }
      final dx = float!.surfaceOffset.x.round();
      final dy = float.surfaceOffset.y.round();
      return (
        left: ink.left + dx,
        top: ink.top + dy,
        right: ink.rightExclusive + dx,
        bottom: ink.bottomExclusive + dy,
      );
    }

    expect(
      shown(env.slotA),
      (left: 50, top: 45, right: 90, bottom: 65),
      reason: 'A is A\'s picture, carried by the box — not a merge of both',
    );
    expect(
      shown(env.slotB),
      (left: 210, top: 105, right: 250, bottom: 145),
    );
    expect(
      find.byKey(const ValueKey<String>('transform-resample-preview')),
      findsNothing,
      reason: 'a float with a slot is drawn there, not over every row here',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scale goes about the middle of ALL of them, and the confirm '
      'hands every float back', (tester) async {
    final env = await pumpLayer(tester);
    env.commands.beginTransform();
    await tester.pump();
    env.commands.editTransformValues((now) => now.copyWith(sx: 2, sy: 2));
    await tester.pump();
    env.commands.applyTransform();
    await tester.pump();

    expect(env.confirmed, hasLength(1), reason: 'one confirm');
    final [landedA, landedB] = env.confirmed.single;
    // About (140, 90): A's middle (60, 50) goes to (-20, 10), B's (220,
    // 120) to (300, 150). Each about its own middle would not move them.
    expect(
      (landedA.center.x, landedA.center.y),
      (-20.0, 10.0),
      reason: 'A scaled about the one box\'s pivot',
    );
    expect((landedB.center.x, landedB.center.y), (300.0, 150.0));
    expect(
      (landedA.stamp!.width, landedA.stamp!.height),
      (80, 40),
      reason: 'A took the scale',
    );
    expect((landedB.stamp!.width, landedB.stamp!.height), (80, 80));
    expect(
      env.carries.single,
      isA<AffineCarry>(),
      reason: 'the range\'s other cels are carried the same way',
    );
    expect(
      (env.slotA.value, env.slotB.value),
      (null, null),
      reason: 'a landed session\'s floats leave their slots',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a corner pulled in 퍼스 bends every float through the ONE quad '
      '— the corner of all of them, and each lands as that quad carries it', (
    tester,
  ) async {
    final env = await pumpLayer(tester, mode: TransformMode.perspective);
    env.commands.beginTransform();
    await tester.pump();
    // The bottom-right corner of what A and B hold together — B's own
    // corner too, and nowhere near A's.
    final gesture = await tester.startGesture(
      const Offset(240, 140),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(const Offset(255, 160));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    env.commands.applyTransform();
    await tester.pump();

    final carry = env.carries.single;
    expect(carry, isA<QuadCarry>(), reason: '⛔premise: the corner made a quad');
    expect(
      (carry! as QuadCarry).base,
      cornersOfStampRect((left: 40, top: 40, width: 200, height: 100)),
      reason: 'the quad stands on what the floats hold together',
    );
    final [landedA, landedB] = env.confirmed.single;
    for (final (landed, lifted) in [(landedA, a), (landedB, b)]) {
      final carried = carry.through(lifted);
      expect(
        (landed.center.x, landed.center.y),
        (carried.center.x, carried.center.y),
        reason: '${lifted.stamp!.id} lands where the one quad carries it',
      );
      expect(landed.stamp!.rgba, carried.stamp!.rgba);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling the box that lifted them puts back all of them, '
      'and tells the host once', (tester) async {
    final env = await pumpLayer(tester);
    env.commands.beginTransform();
    await tester.pump();
    env.commands.editTransformValues((now) => now.copyWith(tx: 30));
    await tester.pump();
    expect(env.slotA.value, isNotNull, reason: 'premise: A floats');

    env.commands.cancelTransform();
    await tester.pump();

    expect(env.reverted, [7]);
    expect(env.confirmed, isEmpty);
    expect((env.slotA.value, env.slotB.value), (null, null));
    await tester.pumpWidget(const SizedBox());
  });
}
