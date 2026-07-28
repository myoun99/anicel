import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

/// R26 #33: toggling the Input Inspector must not REMOUNT the editor
/// under it — the old host swapped its child between bare and wrapped,
/// and that remount's relayout was the visible "layout jumps, then
/// comes back". The tree shape is constant now.
void main() {
  tearDown(InputInspector.reset);

  testWidgets('toggling the inspector keeps the child state alive', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InputInspectorHost(child: _InitCountingChild()),
      ),
    );
    expect(_InitCountingChildState.initCount, 1);
    expect(find.byKey(const ValueKey<String>('input-inspector-card')),
        findsNothing);

    InputInspector.visible.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('input-inspector-card')),
        findsOneWidget);
    expect(_InitCountingChildState.initCount, 1,
        reason: 'opening the inspector rebuilt the whole editor before');

    InputInspector.visible.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('input-inspector-card')),
        findsNothing);
    expect(_InitCountingChildState.initCount, 1,
        reason: 'closing it must not remount either');
  });

  testWidgets('a hidden inspector records nothing; a visible one records', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InputInspectorHost(child: SizedBox.expand()),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(InputInspector.samples, isEmpty,
        reason: 'the always-mounted listener must gate on visibility');

    InputInspector.visible.value = true;
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(InputInspector.samples, isNotEmpty);
  });
}

class _InitCountingChild extends StatefulWidget {
  const _InitCountingChild();

  @override
  State<_InitCountingChild> createState() => _InitCountingChildState();
}

class _InitCountingChildState extends State<_InitCountingChild> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount += 1;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
