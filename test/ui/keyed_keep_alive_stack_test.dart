import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/keyed_keep_alive_stack.dart';

void main() {
  testWidgets('builds lazily, reuses on equal state, rebuilds on changed '
      'state', (tester) async {
    var builds = 0;
    Future<void> pump({required String active, required int state}) {
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyedKeepAliveStack<String, int>(
            keys: const ['a', 'b'],
            activeKey: active,
            stateOf: () => state,
            builder: (context) {
              builds += 1;
              return Text('$active-$state');
            },
          ),
        ),
      );
    }

    await pump(active: 'a', state: 1);
    expect(builds, 1, reason: 'only the active key builds');
    expect(find.text('a-1'), findsOneWidget);

    // Switch to b: b builds cold; a stays cached offstage.
    await pump(active: 'b', state: 1);
    expect(builds, 2);

    // Back to a with UNCHANGED state: pure index flip, no rebuild.
    await pump(active: 'a', state: 1);
    expect(builds, 2, reason: 'equal state must reuse the cached subtree');
    expect(find.text('a-1'), findsOneWidget);

    // State change while active: rebuilds the active child only.
    await pump(active: 'a', state: 2);
    expect(builds, 3);
    expect(find.text('a-2'), findsOneWidget);

    // Back to b, whose state slice is now different from when it was
    // built: rebuilds.
    await pump(active: 'b', state: 2);
    expect(builds, 4);
  });

  // 🚨A state change of the active key is news for ONE slot (2026-09-26):
  // the IndexedStack's own visibility scaffolding round every key used to be
  // rebuilt with it — forty wrappers a brush pick in each tool panel.
  testWidgets('a state change rebuilds the active slot and none of the '
      "stack's wrappers; a switch rebuilds them", (tester) async {
    Future<void> pump({required String active, required int state}) {
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyedKeepAliveStack<String, int>(
            keys: _keys,
            activeKey: active,
            stateOf: () => state,
            builder: (context) => Text('$active-$state'),
          ),
        ),
      );
    }

    Future<int> wrappersRebuiltBy(Future<void> Function() act) async {
      var wrappers = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is ExcludeFocus) wrappers += 1;
      };
      try {
        await act();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return wrappers;
    }

    // Every key visited, so every key holds a slot and a wrapper.
    for (final key in _keys) {
      await pump(active: key, state: 1);
    }
    await pump(active: 'a', state: 1);

    final onChange = await wrappersRebuiltBy(
      () => pump(active: 'a', state: 2),
    );
    expect(find.text('a-2'), findsOneWidget, reason: 'the slot did rebuild');
    expect(onChange, 0);

    final onSwitch = await wrappersRebuiltBy(
      () => pump(active: 'b', state: 2),
    );
    expect(
      onSwitch,
      _keys.length,
      reason: 'premise: a switch rebuilds the stack, so the count can see it',
    );
  });

  testWidgets('hidden children keep their element state across switches', (
    tester,
  ) async {
    Future<void> pump(String active) {
      return tester.pumpWidget(
        MaterialApp(
          home: KeyedKeepAliveStack<String, int>(
            keys: const ['a', 'b'],
            activeKey: active,
            stateOf: () => 0,
            builder: (context) => _Counter(key: ValueKey('counter-$active')),
          ),
        ),
      );
    }

    await pump('a');
    await tester.tap(find.byType(TextButton).hitTestable());
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    // Away and back: the counter's STATE survives (keep-alive), because
    // the subtree was reused, not rebuilt.
    await pump('b');
    await pump('a');
    expect(
      find.text('count 1').hitTestable(),
      findsOneWidget,
      reason: 'the cached subtree must keep its element state',
    );
  });

  // 🔬A kept child off stage was laid out with the shown one at every
  // change of the stack's box — the brush's tool panels with the fill's on
  // every frame a rail scrolled them to its window (2026-11-20).
  group('only the child shown is laid out', () {
    Widget stack(
      String active,
      Widget Function(String key) child, {
      BoxConstraints box = const BoxConstraints.tightFor(
        width: 100,
        height: 100,
      ),
      TextDirection direction = TextDirection.ltr,
    }) => Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: box,
          child: KeyedKeepAliveStack<String, int>(
            keys: const ['a', 'b'],
            activeKey: active,
            stateOf: () => 0,
            builder: (context) => child(active),
          ),
        ),
      ),
    );

    Widget sized(String key) => SizedBox.fromSize(
      key: ValueKey<String>('child-$key'),
      size: key == 'a' ? const Size(40, 20) : const Size(80, 60),
    );

    testWidgets('a child kept off stage is not laid out as the box changes, '
        'and is laid to the box it comes back to', (tester) async {
      final heights = <String, List<double>>{'a': [], 'b': []};
      Widget recorded(String key) => LayoutBuilder(
        builder: (context, box) {
          heights[key]!.add(box.maxHeight);
          return const SizedBox.expand();
        },
      );
      const taller = BoxConstraints.tightFor(width: 100, height: 200);

      await tester.pumpWidget(stack('a', recorded));
      await tester.pumpWidget(stack('b', recorded));
      await tester.pumpWidget(stack('b', recorded, box: taller));
      expect(heights['b'], [100, 200]);
      expect(heights['a'], [100], reason: 'off stage, it kept its layout');

      await tester.pumpWidget(stack('a', recorded, box: taller));
      expect(heights['a'], [100, 200], reason: 'laid to the box it came to');
    });

    testWidgets('a finder sees the child shown, and not the one kept', (
      tester,
    ) async {
      await tester.pumpWidget(stack('b', sized));
      await tester.pumpWidget(stack('a', sized));

      expect(find.byKey(const ValueKey<String>('child-a')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('child-b')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('child-b'), skipOffstage: false),
        findsOneWidget,
        reason: 'premise: it is kept',
      );
    });

    testWidgets('a stack given room is as big as the child shown — laid out '
        'and dry — not as the bigger one kept', (tester) async {
      const room = BoxConstraints(maxWidth: 100, maxHeight: 100);
      await tester.pumpWidget(stack('b', sized, box: room));
      await tester.pumpWidget(stack('a', sized, box: room));

      final box = tester.renderObject<RenderBox>(
        find.byType(KeyedKeepAliveStack<String, int>),
      );
      expect(box.size, const Size(40, 20));
      expect(box.getDryLayout(room), const Size(40, 20));
    });

    testWidgets('the child shown stands where an IndexedStack stands it — at '
        'the start of the reading direction', (tester) async {
      await tester.pumpWidget(
        stack('a', sized, direction: TextDirection.rtl),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('child-a'))),
        const Offset(60, 0),
      );
    });

    testWidgets('a child kept off stage that changes, and changes again, is '
        'laid out to the box it was last shown in', (tester) async {
      final width = ValueNotifier<double>(10);
      addTearDown(width.dispose);
      Widget changing(String key) => key == 'a'
          ? sized(key)
          : ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, value, _) => SizedBox(
                key: const ValueKey<String>('child-b'),
                width: value,
              ),
            );
      await tester.pumpWidget(stack('b', changing));
      await tester.pumpWidget(stack('a', changing));

      for (final value in [20.0, 30.0]) {
        width.value = value;
        await tester.pump();
      }
      expect(
        tester.getSize(
          find.byKey(const ValueKey<String>('child-b'), skipOffstage: false),
        ),
        const Size(30, 0),
      );
    });

    testWidgets('a child kept off stage cannot take the focus', (
      tester,
    ) async {
      final nodes = {'a': FocusNode(), 'b': FocusNode()};
      addTearDown(() {
        for (final node in nodes.values) {
          node.dispose();
        }
      });
      Widget focusable(String key) =>
          Focus(focusNode: nodes[key], child: const SizedBox.expand());
      await tester.pumpWidget(stack('b', focusable));
      await tester.pumpWidget(stack('a', focusable));

      nodes['b']!.requestFocus();
      await tester.pump();
      expect(nodes['b']!.hasFocus, isFalse);
      nodes['a']!.requestFocus();
      await tester.pump();
      expect(nodes['a']!.hasFocus, isTrue, reason: 'premise: the shown can');
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _count += 1),
      child: Text('count $_count'),
    );
  }
}

const _keys = ['a', 'b', 'c'];
