import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_entry.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/ui/brush/brush_tip_picker.dart';

BrushTipEntry _tip(String id, String name) {
  final alpha = Uint8List(4 * 4)..fillRange(0, 16, 255);
  return BrushTipEntry(
    id: id,
    name: name,
    size: 4,
    thumbnail: alpha,
    mask: BrushTipMask(id: id, size: 4, alpha: alpha),
  );
}

final _library = [_tip('a', 'Alpha'), _tip('b', 'Beta'), _tip('c', 'Gamma')];

BrushTipMask _mask(String id) =>
    _library.firstWhere((tip) => tip.id == id).mask!;

/// F-176-Q3 (「클튜 여섯 전부 + 끌어서 순서」) in the picker: the tips' slot
/// holds several, in the order the dabs take them — pressed in, pressed
/// back out, and dragged along the strip into another order.
void main() {
  const strip = ValueKey<String>('brush-tip-turns');

  Finder cell(String id) => find.byKey(ValueKey<String>('brush-tip-cell-$id'));
  Finder turnAt(int index) =>
      find.byKey(ValueKey<String>('brush-tip-turn-at-$index'));

  /// Pumps [role]'s row holding [selected] and opens its popup; what the
  /// popup applies when it goes away lands in the returned list.
  Future<List<List<String>>> open(
    WidgetTester tester, {
    BrushTipRole role = BrushTipRole.tip,
    List<String> selected = const [],
    void Function(BrushTipEntry tip)? onDeleteTip,
  }) async {
    final applied = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: BrushTipPickerRow(
                label: 'Tip',
                role: role,
                selected: [for (final id in selected) _mask(id)],
                tips: _library,
                onPicked: (masks) =>
                    applied.add([for (final mask in masks) mask.id]),
                onDeleteTip: onDeleteTip,
              ),
            ),
          ),
        ),
      ),
    );
    final swatch = ValueKey<String>('brush-tip-picker-${role.name}');
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    return applied;
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  }

  testWidgets('the tips\' slot takes each tip pressed, in the order pressed', (
    tester,
  ) async {
    final applied = await open(tester);
    expect(find.byKey(strip), findsOneWidget, reason: 'empty, not absent');
    expect(turnAt(0), findsNothing);

    for (final id in ['b', 'a', 'c']) {
      await tester.tap(cell(id));
      await tester.pumpAndSettle();
    }
    expect(turnAt(2), findsOneWidget);

    await dismiss(tester);
    expect(applied, [
      ['b', 'a', 'c'],
    ]);
  });

  testWidgets('a second press takes a tip back out, wherever it stands', (
    tester,
  ) async {
    final applied = await open(tester, selected: ['a', 'b', 'c']);

    await tester.tap(cell('b'));
    await tester.pumpAndSettle();
    expect(turnAt(2), findsNothing);

    await dismiss(tester);
    expect(applied, [
      ['a', 'c'],
    ]);
  });

  testWidgets('none empties the slot', (tester) async {
    final applied = await open(tester, selected: ['a', 'b']);

    await tester.tap(cell('none'));
    await tester.pumpAndSettle();
    expect(turnAt(0), findsNothing);

    await dismiss(tester);
    expect(applied, [<String>[]]);
  });

  testWidgets('a one-mask slot takes the pressed mask in place of the last, '
      'and has no strip', (tester) async {
    final applied = await open(tester, role: BrushTipRole.dual);
    expect(find.byKey(strip), findsNothing);

    await tester.tap(cell('a'));
    await tester.pumpAndSettle();
    await tester.tap(cell('b'));
    await tester.pumpAndSettle();

    await dismiss(tester);
    expect(applied, [
      ['b'],
    ]);
  });

  /// Drags the strip's tip at [from] along to where the one at [to] stands.
  Future<void> drag(WidgetTester tester, int from, int to) async {
    final start = tester.getCenter(turnAt(from));
    final by = tester.getCenter(turnAt(to)) - start;
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 8));
    await tester.pump();
    await gesture.moveBy(by);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('🚨a tip dragged along the strip takes its new place', (
    tester,
  ) async {
    final applied = await open(tester, selected: ['a', 'b', 'c']);

    await drag(tester, 0, 1);

    await dismiss(tester);
    expect(applied, [
      ['b', 'a', 'c'],
    ]);
  });

  testWidgets('a tip dragged with its name up does not take the popup down', (
    tester,
  ) async {
    // The hand that drags a tip has been resting on it: its name is up when
    // the drag starts — the preset list's R4 #11, in this list.
    final applied = await open(tester, selected: ['a', 'b', 'c']);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(turnAt(2)));
    await tester.pump(const Duration(seconds: 2));

    await drag(tester, 2, 0);

    expect(tester.takeException(), isNull);
    await dismiss(tester);
    expect(applied, [
      ['c', 'a', 'b'],
    ]);
  });

  testWidgets('a tip pressed in the strip is the one the manage row acts on', (
    tester,
  ) async {
    final deleted = <String>[];
    await open(
      tester,
      selected: ['a', 'b'],
      onDeleteTip: (tip) => deleted.add(tip.id),
    );

    await tester.tap(turnAt(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('brush-tip-delete')));
    await tester.pumpAndSettle();

    expect(deleted, ['b']);
  });
}
