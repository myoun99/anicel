import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/overflow_scrollers.dart';

/// What [OverflowScrollers] hands its body: the FLOOR, exactly, on an axis
/// the room is short of it, and the room as it was given on an axis that
/// holds it.
///
/// 🧪The three escapes it replaced laid a short body out in a box of the
/// floor's size — the dock as "the larger of the floor and the dock", the
/// media pool and the import table as a `SizedBox` of the floor — and each
/// of their bodies fills whatever it is given, so none of their tests could
/// tell a floor from a ceiling. A body that does not fill can.
void main() {
  const probe = ValueKey('probe');

  Widget roomOf(Size room, {required Widget child}) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(size: room, child: child),
    ),
  );

  testWidgets('a room short of the floor lays the body out AT the floor, on '
      'both axes', (tester) async {
    await tester.pumpWidget(
      roomOf(
        const Size(100, 80),
        child: const OverflowScrollers(
          minWidth: 200,
          minHeight: 150,
          child: SizedBox(key: probe, width: 10, height: 10),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(probe)), const Size(200, 150));
  });

  testWidgets('a room that holds the floor reaches the body as it was given '
      '— tight stays tight, loose stays loose', (tester) async {
    await tester.pumpWidget(
      roomOf(
        const Size(300, 200),
        child: const OverflowScrollers(
          minWidth: 200,
          minHeight: 150,
          child: SizedBox(key: probe, width: 10, height: 10),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(probe)), const Size(300, 200));

    await tester.pumpWidget(
      roomOf(
        const Size(300, 200),
        child: const Align(
          alignment: Alignment.topLeft,
          child: OverflowScrollers(
            minWidth: 200,
            minHeight: 150,
            child: SizedBox(key: probe, width: 10, height: 10),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(probe)), const Size(10, 10));
  });
}
