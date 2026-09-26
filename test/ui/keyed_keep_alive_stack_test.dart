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
