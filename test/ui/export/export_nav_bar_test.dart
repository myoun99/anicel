import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/export/export_nav_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required ExportNavAxis axis,
    required int position,
    required ValueChanged<int> onChanged,
    TextEditingController? inController,
    TextEditingController? outController,
    int? inMark,
    int? outMark,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: ExportNavBar(
                axis: axis,
                position: position,
                enabled: true,
                onChanged: onChanged,
                inController: inController,
                outController: outController,
                inMark: inMark,
                outMark: outMark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  test('axis clamps and captions', () {
    const axis = ExportNavAxis(length: 5);
    expect(axis.clamp(-3), 0);
    expect(axis.clamp(9), 4);
    expect(axis.caption(2), '3');
    final labelled = ExportNavAxis(
      length: 3,
      captionOf: (position) => 'A-${position + 1}',
    );
    expect(labelled.caption(2), 'A-3');
    expect(const ExportNavAxis(length: 0).clamp(4), 0);
  });

  testWidgets('tap seeks by fraction, drag follows', (tester) async {
    final changes = <int>[];
    await pumpBar(
      tester,
      axis: const ExportNavAxis(length: 10),
      position: 0,
      onChanged: changes.add,
    );
    final scrub = find.byKey(const ValueKey<String>('export-nav-scrub'));
    final rect = tester.getRect(scrub);

    await tester.tapAt(Offset(rect.left + rect.width * 0.55, rect.center.dy));
    expect(changes, [5]);

    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    expect(changes.last, 9);

    final gesture = await tester.startGesture(
      Offset(rect.left + 1, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.left + rect.width * 0.35, rect.center.dy));
    await gesture.up();
    expect(changes.last, 3);
  });

  testWidgets('prev/next step and clamp at the ends', (tester) async {
    final changes = <int>[];
    await pumpBar(
      tester,
      axis: const ExportNavAxis(length: 3),
      position: 0,
      onChanged: changes.add,
    );
    await tester.tap(find.byKey(const ValueKey<String>('export-nav-prev')));
    expect(changes, [0]);
    await tester.tap(find.byKey(const ValueKey<String>('export-nav-next')));
    expect(changes.last, 1);
  });

  testWidgets('in/out fields render only when controllers are given',
      (tester) async {
    await pumpBar(
      tester,
      axis: const ExportNavAxis(length: 3),
      position: 0,
      onChanged: (_) {},
    );
    expect(
      find.byKey(const ValueKey<String>('export-range-start-field')),
      findsNothing,
    );

    final inController = TextEditingController(text: '1');
    final outController = TextEditingController(text: '3');
    addTearDown(inController.dispose);
    addTearDown(outController.dispose);
    await pumpBar(
      tester,
      axis: const ExportNavAxis(length: 3),
      position: 0,
      onChanged: (_) {},
      inController: inController,
      outController: outController,
      inMark: 0,
      outMark: 2,
    );
    expect(
      find.byKey(const ValueKey<String>('export-range-start-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-range-end-field')),
      findsOneWidget,
    );
  });
}
