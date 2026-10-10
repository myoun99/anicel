import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_range_move.dart' show unionMixedKeyName;
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/timeline/key_sides_rows.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart' show Pill;

/// 🗣️I-89 ② (유저 2026-10-10: 「B' 두줄 줄마다 세기로 가자」): the key window
/// gives each side of the covered keys a row — its kind, then its ease's
/// 세기 — and writes only what was picked.
void main() {
  late KeySidesEdit picked;

  Future<void> pumpRows(
    WidgetTester tester,
    List<({KeySide incoming, KeyExit outgoing})> sides,
  ) async {
    picked = const KeySidesEdit();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 368,
              child: StatefulBuilder(
                builder: (context, setState) => KeySidesRows(
                  sides: sides,
                  picked: picked,
                  onPicked: (edit) => setState(() => picked = edit),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool lit(WidgetTester tester, String key) =>
      tester.widget<Pill>(find.byKey(ValueKey<String>(key))).selected;

  FieldSlider strength(WidgetTester tester, String row) =>
      tester.widget<FieldSlider>(
        find.byKey(ValueKey<String>('rename-key-$row-influence')),
      );

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  Future<void> slide(WidgetTester tester, String row, double influence) async {
    strength(tester, row).onChanged!(influence);
    await tester.pumpAndSettle();
  }

  const straight = (incoming: KeySide.linear, outgoing: KeySide.linear);

  testWidgets('each row lights the kind its keys all are — nothing where '
      'they differ', (tester) async {
    await pumpRows(tester, [
      straight,
      (incoming: KeySide.linear, outgoing: KeyExit.hold),
    ]);
    expect(lit(tester, 'rename-key-in-linear'), isTrue);
    for (final kind in ['linear', 'ease', 'auto', 'hold']) {
      expect(lit(tester, 'rename-key-out-$kind'), isFalse, reason: kind);
    }
  });

  testWidgets('the side leaving offers the hold; the side arriving cannot '
      'hold', (tester) async {
    await pumpRows(tester, [straight]);
    expect(find.byKey(const ValueKey('rename-key-out-hold')), findsOneWidget);
    expect(find.byKey(const ValueKey('rename-key-in-hold')), findsNothing);
  });

  testWidgets('a side that is no ease keeps its 세기 in its place, '
      'disabled (「없다가 생기는 UI 금지」)', (tester) async {
    await pumpRows(tester, [straight]);
    expect(strength(tester, 'in').onChanged, isNull);
    expect(strength(tester, 'out').onChanged, isNull);
  });

  testWidgets('picking 천천히 lights it and wakes the 세기 at AE\'s Easy '
      'Ease — on that side alone', (tester) async {
    await pumpRows(tester, [straight]);
    await tap(tester, 'rename-key-in-ease');

    expect(lit(tester, 'rename-key-in-ease'), isTrue);
    expect(lit(tester, 'rename-key-in-linear'), isFalse);
    expect(strength(tester, 'in').onChanged, isNotNull);
    expect(strength(tester, 'in').value, EaseSide.easeInfluence);
    expect(strength(tester, 'out').onChanged, isNull);
    expect(
      picked.applyTo(incoming: KeySide.linear, outgoing: KeySide.linear),
      (incoming: const EaseSide(), outgoing: KeySide.linear),
    );
  });

  testWidgets('the 세기 writes the influence alone — each ease keeps its '
      'speed', (tester) async {
    const ownEase = EaseSide(influence: 0.5, speed: 0.2);
    await pumpRows(tester, [
      (incoming: ownEase, outgoing: KeySide.linear),
    ]);
    expect(strength(tester, 'in').value, 0.5);

    await slide(tester, 'in', 0.25);
    expect(strength(tester, 'in').value, 0.25);
    expect(
      picked.applyTo(incoming: ownEase, outgoing: KeySide.linear),
      (
        incoming: const EaseSide(influence: 0.25, speed: 0.2),
        outgoing: KeySide.linear,
      ),
    );
  });

  testWidgets('eases that take different influences write `...` until the '
      '세기 is moved', (tester) async {
    await pumpRows(tester, [
      (incoming: const EaseSide(influence: 0.5), outgoing: KeySide.linear),
      (incoming: const EaseSide(influence: 0.25), outgoing: KeySide.linear),
    ]);
    expect(lit(tester, 'rename-key-in-ease'), isTrue);
    expect(strength(tester, 'in').restingText, unionMixedKeyName);

    await slide(tester, 'in', 0.4);
    expect(strength(tester, 'in').restingText, isNull);
  });

  testWidgets('a kind picked after the 세기 keeps the 세기', (tester) async {
    await pumpRows(tester, [
      (incoming: const EaseSide(), outgoing: KeySide.linear),
    ]);
    await slide(tester, 'in', 0.4);
    await tap(tester, 'rename-key-in-linear');
    expect(strength(tester, 'in').onChanged, isNull);
    await tap(tester, 'rename-key-in-ease');

    expect(strength(tester, 'in').value, 0.4);
    expect(
      picked.applyTo(incoming: KeySide.linear, outgoing: KeySide.linear),
      (incoming: const EaseSide(influence: 0.4), outgoing: KeySide.linear),
    );
  });

  testWidgets('a 세기 moved after picking 천천히 keeps the pick', (
    tester,
  ) async {
    await pumpRows(tester, [straight]);
    await tap(tester, 'rename-key-in-ease');
    await slide(tester, 'in', 0.6);
    expect(lit(tester, 'rename-key-in-ease'), isTrue);
    expect(
      picked.applyTo(incoming: KeySide.linear, outgoing: KeySide.linear),
      (incoming: const EaseSide(influence: 0.6), outgoing: KeySide.linear),
    );
  });

  for (final order in [
    ['rename-key-out-hold', 'rename-key-in-auto'],
    ['rename-key-in-auto', 'rename-key-out-hold'],
  ]) {
    testWidgets('a pick on one side leaves the other side\'s pick — '
        '${order.join(' then ')}', (tester) async {
      await pumpRows(tester, [straight]);
      for (final key in order) {
        await tap(tester, key);
      }
      expect(
        picked.applyTo(incoming: KeySide.linear, outgoing: KeySide.linear),
        (incoming: KeySide.auto, outgoing: KeyExit.hold),
      );
    });
  }

  testWidgets('each choice wears its half of the mark — the left for the '
      'side arriving, the right for the side leaving', (tester) async {
    await pumpRows(tester, [straight]);
    RenderObject glyph(String key) => tester.renderObject(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.size == const Size.square(9),
        ),
      ),
    );
    // A 9px box, cut at 4.5: the mark of a key straight on both sides,
    // with the half its row does not say clipped away.
    expect(
      glyph('rename-key-in-linear'),
      paints
        ..clipRect(rect: const Rect.fromLTRB(0, 0, 4.5, 9))
        ..path(includes: const [Offset(2, 4.5), Offset(7, 4.5)]),
    );
    expect(
      glyph('rename-key-out-linear'),
      paints
        ..clipRect(rect: const Rect.fromLTRB(4.5, 0, 9, 9))
        ..path(includes: const [Offset(2, 4.5), Offset(7, 4.5)]),
    );
  });
}
