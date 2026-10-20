import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/key_flag_row.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart' show Pill;

/// I-89 ④ (Q4 · Q5, A and A′ while they are asked): the key window's
/// yes-or-no rows — the path bending through the covered keys, their time
/// roving — lit as the keys agree, writing only what was picked, and
/// offered but refused where no covered key can say it.
void main() {
  bool? picked;

  Future<void> pumpRow(WidgetTester tester, List<bool> flags) async {
    picked = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 368,
              child: StatefulBuilder(
                builder: (context, setState) => KeyFlagRow(
                  label: 'Roving',
                  help: 'What roving is',
                  off: (id: 'row-off', word: 'Off'),
                  on: (id: 'row-on', word: 'On'),
                  flags: flags,
                  picked: picked,
                  onPicked: (value) => setState(() => picked = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Pill pill(WidgetTester tester, String id) =>
      tester.widget<Pill>(find.byKey(ValueKey<String>('row-$id')));

  ({bool off, bool on}) lit(WidgetTester tester) =>
      (off: pill(tester, 'off').selected, on: pill(tester, 'on').selected);

  testWidgets('it lights what the keys all say, and nothing where they '
      'differ', (tester) async {
    await pumpRow(tester, [false, false]);
    expect(lit(tester), (off: true, on: false));

    await pumpRow(tester, [true, true]);
    expect(lit(tester), (off: false, on: true));

    await pumpRow(tester, [false, true]);
    expect(lit(tester), (off: false, on: false));
  });

  testWidgets('a pick lights itself over what the keys say, and is what '
      'the window hands on', (tester) async {
    await pumpRow(tester, [false, true]);
    await tester.tap(find.byKey(const ValueKey<String>('row-on')));
    await tester.pumpAndSettle();
    expect(picked, isTrue);
    expect(lit(tester), (off: false, on: true));

    await tester.tap(find.byKey(const ValueKey<String>('row-off')));
    await tester.pumpAndSettle();
    expect(picked, isFalse);
    expect(lit(tester), (off: true, on: false));
  });

  testWidgets('where no covered key can say it the row keeps its place and '
      'takes no pick', (tester) async {
    await pumpRow(tester, const []);
    expect(lit(tester), (off: false, on: false));
    expect(pill(tester, 'off').onTap, isNull);
    expect(pill(tester, 'on').onTap, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('row-on')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
