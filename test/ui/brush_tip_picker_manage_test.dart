import 'dart:typed_data';

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

void main() {
  const swatch = ValueKey<String>('brush-tip-picker-tip');
  const grid = ValueKey<String>('brush-tip-picker-grid');
  const renameKey = ValueKey<String>('brush-tip-rename');
  const deleteKey = ValueKey<String>('brush-tip-delete');

  Future<void> pump(
    WidgetTester tester, {
    required ValueChanged<BrushTipMask?> onPicked,
    void Function(BrushTipEntry tip)? onRenameTip,
    void Function(BrushTipEntry tip)? onDeleteTip,
    BrushTipMask? selected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: BrushTipPickerRow(
                label: 'Tip',
                role: BrushTipRole.tip,
                selected: selected,
                tips: [_tip('a', 'Alpha'), _tip('b', 'Beta')],
                onPicked: onPicked,
                onRenameTip: onRenameTip,
                onDeleteTip: onDeleteTip,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('picking no longer closes the popup', (tester) async {
    // The behaviour this whole rework exists for: with picking as the
    // dismiss there was never a moment where a tip was both chosen and on
    // screen, so Delete had nothing to stand next to.
    await pump(tester, onPicked: (_) {}, onDeleteTip: (_) {});
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    expect(find.byKey(grid), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('brush-tip-cell-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(grid), findsOneWidget, reason: 'still open');
  });

  testWidgets('the pick applies when the popup is dismissed', (tester) async {
    final picked = <String?>[];
    await pump(tester, onPicked: (mask) => picked.add(mask?.id));
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('brush-tip-cell-b')));
    await tester.pumpAndSettle();
    // Nothing applied yet — the popup is still up.
    expect(picked, isEmpty);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(picked, ['b']);
  });

  testWidgets('dismissing without picking applies nothing', (tester) async {
    final picked = <String?>[];
    await pump(tester, onPicked: (mask) => picked.add(mask?.id));
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
  });

  testWidgets('the manage row acts on the tip that is picked', (tester) async {
    final renamed = <String>[];
    final deleted = <String>[];
    await pump(
      tester,
      onPicked: (_) {},
      onRenameTip: (tip) => renamed.add(tip.id),
      onDeleteTip: (tip) => deleted.add(tip.id),
    );
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('brush-tip-cell-a')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.byKey(renameKey));
    await tester.pumpAndSettle();
    expect(renamed, ['a']);

    await tester.tap(find.byKey(deleteKey));
    await tester.pumpAndSettle();
    expect(deleted, ['a']);
  });

  testWidgets('manage is dead while "none" is picked', (tester) async {
    // There is no entry behind the none cell to rename or delete.
    await pump(
      tester,
      onPicked: (_) {},
      onRenameTip: (_) {},
      onDeleteTip: (_) {},
    );
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(deleteKey)).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey<String>('brush-tip-cell-a')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(find.byKey(deleteKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a host that wires no handlers gets no manage row', (
    tester,
  ) async {
    await pump(tester, onPicked: (_) {});
    await tester.tap(find.byKey(swatch));
    await tester.pumpAndSettle();
    expect(find.byKey(renameKey), findsNothing);
    expect(find.byKey(deleteKey), findsNothing);
  });
}
