import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/sliced_value_listenable_builder.dart';

void main() {
  testWidgets('rebuilds only when the slice changes', (tester) async {
    final notifier = ValueNotifier<(int, String)>((1, 'a'));
    addTearDown(notifier.dispose);
    var builds = 0;

    await tester.pumpWidget(
      SlicedValueListenableBuilder<(int, String), int>(
        valueListenable: notifier,
        slice: (value) => value.$1,
        builder: (context, value) {
          builds += 1;
          return Text(
            '${value.$1}-${value.$2}',
            textDirection: TextDirection.ltr,
          );
        },
      ),
    );
    expect(builds, 1);

    // Off-slice change: no rebuild.
    notifier.value = (1, 'b');
    await tester.pump();
    expect(builds, 1);

    // On-slice change: rebuilds and sees the CURRENT full value
    // (including earlier off-slice changes).
    notifier.value = (2, 'c');
    await tester.pump();
    expect(builds, 2);
    expect(find.text('2-c'), findsOneWidget);
  });

  testWidgets('swaps listeners when the listenable instance changes', (
    tester,
  ) async {
    final first = ValueNotifier<int>(1);
    final second = ValueNotifier<int>(10);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget host(ValueNotifier<int> notifier) =>
        SlicedValueListenableBuilder<int, int>(
          valueListenable: notifier,
          slice: (value) => value,
          builder: (context, value) =>
              Text('$value', textDirection: TextDirection.ltr),
        );

    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(second));
    expect(find.text('10'), findsOneWidget);

    // The old notifier must be fully detached...
    first.value = 2;
    await tester.pump();
    expect(find.text('10'), findsOneWidget);

    // ...and the new one live.
    second.value = 11;
    await tester.pump();
    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('detaches on dispose', (tester) async {
    final notifier = ValueNotifier<int>(1);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      SlicedValueListenableBuilder<int, int>(
        valueListenable: notifier,
        slice: (value) => value,
        builder: (context, value) =>
            Text('$value', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    // No listeners left: mutating must not throw or rebuild anything.
    notifier.value = 2;
    await tester.pump();
    expect(find.text('2'), findsNothing);
  });

  testWidgets('any Listenable slices the same way: news that moves no '
      'slice rebuilds nothing, and the builder is handed the slice', (
    tester,
  ) async {
    final model = _Counter();
    addTearDown(model.dispose);
    final seen = <int>[];

    await tester.pumpWidget(
      SlicedListenableBuilder<int>(
        listenable: model,
        slice: () => model.shown,
        builder: (context, shown) {
          seen.add(shown);
          return Text('$shown', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(seen, [0]);

    model.bumpUnseen();
    await tester.pump();
    expect(seen, [0], reason: 'the news changed nothing shown');

    model.bumpShown();
    await tester.pump();
    expect(seen, [0, 1]);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a rebuild from above hands the builder the slice as it is '
      'NOW, and the next news is measured against that', (tester) async {
    final model = _Counter();
    addTearDown(model.dispose);
    final seen = <int>[];

    Widget host() => SlicedListenableBuilder<int>(
      listenable: model,
      slice: () => model.shown,
      builder: (context, shown) {
        seen.add(shown);
        return Text('$shown', textDirection: TextDirection.ltr);
      },
    );

    await tester.pumpWidget(host());
    model.shown = 5; // changed with no news
    await tester.pumpWidget(host());
    expect(seen, [0, 5]);

    // Already built from 5: news that leaves it at 5 is no change.
    model.bumpUnseen();
    await tester.pump();
    expect(seen, [0, 5]);
  });
  test('a listener that is not a widget hears only the slice move — and '
      'reads the value of its source', () {
    final source = ValueNotifier<(int, String)>((1, 'a'));
    addTearDown(source.dispose);
    final sliced = SlicedValueListenable<(int, String), int>(
      source,
      (value) => value.$1,
    );
    var heard = 0;
    sliced.addListener(() => heard += 1);

    source.value = (1, 'b');
    expect(heard, 0, reason: 'off the slice');
    expect(sliced.value, (1, 'b'), reason: 'the value is its source\'s');

    source.value = (2, 'b');
    expect(heard, 1);
    expect(sliced.slice, 2);

    sliced.dispose();
    source.value = (3, 'c');
    expect(heard, 1, reason: 'a disposed slice has let go of its source');
  });

  testWidgets('the scope keeps ONE sliced channel across rebuilds, and '
      'swaps it with its source', (tester) async {
    final first = ValueNotifier<int>(1);
    final second = ValueNotifier<int>(10);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final handed = <SlicedValueListenable<int, int>>[];

    Widget host(ValueNotifier<int> source) =>
        SlicedValueListenableScope<int, int>(
          valueListenable: source,
          slice: (value) => value,
          builder: (context, sliced) {
            handed.add(sliced);
            return const SizedBox();
          },
        );

    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(first));
    expect(
      identical(handed[0], handed[1]),
      isTrue,
      reason: 'a painter compares its channel by identity — a new one per '
          'build would repaint it every build',
    );

    await tester.pumpWidget(host(second));
    expect(handed.last.value, 10);
    var heard = 0;
    handed.last.addListener(() => heard += 1);
    first.value = 2;
    expect(heard, 0, reason: 'the old source is let go');
    second.value = 11;
    expect(heard, 1);
  });
}

class _Counter extends ChangeNotifier {
  int shown = 0;
  int unseen = 0;

  void bumpShown() {
    shown += 1;
    notifyListeners();
  }

  void bumpUnseen() {
    unseen += 1;
    notifyListeners();
  }
}
