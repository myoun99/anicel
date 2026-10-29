import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart'
    show valueControlOwnsPointer;
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/row_control_surface.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every slot of every rail row wears these two, so a wrapper that only
/// forwards its child is paid once per slot on every panel reopen (card
/// frame-panels-build-in-one-frame, 2026-10-25). They ARE the box they
/// stand for; what they do is held by the tests of the row's drag and of
/// the swipe columns.
void main() {
  Element only(Element parent) {
    final children = <Element>[];
    parent.visitChildren(children.add);
    expect(children, hasLength(1));
    return children.single;
  }

  testWidgets('a filled slot is one box: the marker the row asks for', (
    tester,
  ) async {
    const body = ValueKey<String>('body');
    await tester.pumpWidget(
      Align(
        child: layerRailSlot(
          Axis.horizontal,
          30,
          const SizedBox(key: body, height: 24),
        ),
      ),
    );
    final slot = tester.element(find.byType(RowControlSurface));
    expect(slot.findAncestorWidgetOfExactType<Align>(), isNotNull);
    expect(slot.findAncestorWidgetOfExactType<SizedBox>(), isNull);
    expect(
      tester.renderObject(find.byType(RowControlSurface)),
      isA<RenderRowControlSurface>(),
    );
    expect(only(slot).widget.key, body);
  });

  testWidgets('a filled slot stands as the SizedBox an empty one is', (
    tester,
  ) async {
    // Its box is what [alongBox] gives an empty slot of the same extent —
    // along the rail and across it, laid out and asked.
    Future<void> compare(Axis axis, double extent) async {
      const held = SizedBox(width: 10, height: 24);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Flex(
              direction: axis,
              mainAxisSize: MainAxisSize.min,
              children: [
                alongBox(axis, extent, child: held),
                RowControlSurface(axis: axis, extent: extent, child: held),
              ],
            ),
          ),
        ),
      );
      final sized = tester.renderObject<RenderBox>(
        find.byWidgetPredicate((w) => w is SizedBox && w.child == held),
      );
      final slot = tester.renderObject<RenderBox>(
        find.byType(RowControlSurface),
      );
      expect(slot.size, sized.size, reason: '$axis $extent');
      for (final (name, ask) in <(String, double Function(RenderBox))>[
        ('min width', (b) => b.getMinIntrinsicWidth(double.infinity)),
        ('max width', (b) => b.getMaxIntrinsicWidth(double.infinity)),
        ('min height', (b) => b.getMinIntrinsicHeight(double.infinity)),
        ('max height', (b) => b.getMaxIntrinsicHeight(double.infinity)),
      ]) {
        expect(ask(slot), ask(sized), reason: '$axis $extent $name');
      }
    }

    await compare(Axis.horizontal, 30);
    expect(
      tester.getSize(find.byType(RowControlSurface)),
      const Size(30, 24),
    );
    // Built again with another extent, it stands at the new one.
    await compare(Axis.horizontal, 44);
    expect(
      tester.getSize(find.byType(RowControlSurface)),
      const Size(44, 24),
    );
    await compare(Axis.vertical, 30);
    expect(
      tester.getSize(find.byType(RowControlSurface)),
      const Size(10, 30),
    );
  });

  testWidgets('a press on a filled slot falls through where nothing in it '
      'takes it', (tester) async {
    // The slot is on the hit path, not in the way: what stands under it
    // still gets a press its child leaves.
    var under = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => under += 1,
              ),
            ),
            const Align(
              child: RowControlSurface(
                axis: Axis.horizontal,
                extent: 40,
                child: SizedBox(height: 24),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(RowControlSurface));
    expect(under, 1);
  });

  testWidgets('only a slot marks a control — not any box a press lands in', (
    tester,
  ) async {
    const row = Key('row');
    const box = Key('box');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Row(
            key: row,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: box,
                width: 40,
                height: 24,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      RowControlSurface.covers(
        tester.element(find.byKey(row)),
        tester.getCenter(find.byKey(box)),
      ),
      isFalse,
    );
  });

  testWidgets('a swipe column in its slot is ONE box: the slot, the claim '
      'and the column it says', (tester) async {
    const body = ValueKey<String>('body');
    RailSwipeColumn? said;
    bool? held;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          // Dispatch runs deepest-first, so the slot has spoken by the time
          // a box above it hears the same press — as the rail does.
          child: Listener(
            onPointerDown: (down) {
              said = railSwipeColumnPressedBy(down);
              held = valueControlOwnsPointer(down.pointer);
            },
            child: layerRailSlot(
              Axis.horizontal,
              30,
              const RailSwipeColumnPointer(
                column: RailSwipeColumn.fx,
                child: Listener(
                  key: body,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(height: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(RailSwipeColumnPointer), findsNothing);
    final slot = tester.element(find.byType(RailSwipeColumnSlot));
    expect(only(slot).widget.key, body);
    expect(
      tester.renderObject(find.byType(RailSwipeColumnSlot)),
      isA<RenderRowControlSurface>().having(
        (box) => box is HoldsDragVerb,
        'holds its drag',
        isTrue,
      ),
    );
    expect(
      tester.getSize(find.byType(RailSwipeColumnSlot)),
      const Size(30, 24),
    );
    expect(
      RowControlSurface.covers(
        tester.element(find.byType(Listener).first),
        tester.getCenter(find.byKey(body)),
      ),
      isTrue,
    );

    final press = await tester.startGesture(tester.getCenter(find.byKey(body)));
    expect(said, RailSwipeColumn.fx);
    expect(held, isTrue);
    await press.up();
  });

  testWidgets('a slot built again for another column says the new one', (
    tester,
  ) async {
    RailSwipeColumn? said;
    Future<void> pressIn(RailSwipeColumn column) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            child: Listener(
              onPointerDown: (down) => said = railSwipeColumnPressedBy(down),
              child: layerRailSlot(
                Axis.horizontal,
                30,
                RailSwipeColumnPointer(
                  column: column,
                  child: const Listener(
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(height: 24),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final press = await tester.startGesture(
        tester.getCenter(find.byType(RailSwipeColumnSlot)),
      );
      await press.up();
    }

    await pressIn(RailSwipeColumn.fx);
    final slot = tester.renderObject(find.byType(RailSwipeColumnSlot));
    expect(said, RailSwipeColumn.fx);
    await pressIn(RailSwipeColumn.visibility);
    expect(
      tester.renderObject(find.byType(RailSwipeColumnSlot)),
      same(slot),
      reason: '⛔premise: the same box, built again',
    );
    expect(said, RailSwipeColumn.visibility);
  });

  testWidgets('the eye, the fx switch and the sheet toggle are their faces — '
      'no box over them, and the size the box gave', (tester) async {
    Future<void> check(Widget toggle, Size size) async {
      await tester.pumpWidget(
        MaterialApp(home: Align(child: toggle)),
      );
      final face = only(tester.element(find.byWidget(toggle)));
      expect(face.widget, isA<RailGlyphButton>(), reason: '$toggle');
      expect(tester.getSize(find.byWidget(toggle)), size, reason: '$toggle');
    }

    await check(
      LayerVisibilityToggleButton(
        name: 'eye',
        isVisible: true,
        onToggle: () {},
      ),
      const Size(layerVisibilitySlotWidth, 26),
    );
    await check(
      FxToggleButton(name: 'fx', state: LayerFxState.on, onToggle: () {}),
      const Size(layerFxSlotWidth, 26),
    );
    await check(
      LayerTimesheetToggleButton(
        keyPrefix: 'timeline',
        layerId: const LayerId('a'),
        onTimesheet: true,
        onToggle: (_) {},
      ),
      const Size(layerTimesheetSlotWidth, layerTimesheetSlotWidth),
    );
  });

  testWidgets('a swipe column is the claim it adds, and nothing else — '
      'WHEN its controls act is the row\'s to say', (tester) async {
    const body = ValueKey<String>('body');
    await tester.pumpWidget(
      const RailSwipeColumnPointer(
        column: RailSwipeColumn.visibility,
        child: SizedBox(key: body),
      ),
    );
    final column = tester.element(find.byType(RailSwipeColumnPointer));
    expect(
      tester.renderObject(find.byType(RailSwipeColumnPointer)),
      isA<RenderDragVerbClaim>(),
    );
    expect(only(column).widget.key, body);
    expect(
      PressFireScope.of(tester.element(find.byKey(body))),
      PressFire.upInside,
      reason: 'a column outside a row says nothing of its own',
    );
  });
}
