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
      const MaterialApp(home: InputInspectorHost(child: _InitCountingChild())),
    );
    expect(_InitCountingChildState.initCount, 1);
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsNothing,
    );

    InputInspector.visible.value = true;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsOneWidget,
    );
    expect(
      _InitCountingChildState.initCount,
      1,
      reason: 'opening the inspector rebuilt the whole editor before',
    );

    InputInspector.visible.value = false;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsNothing,
    );
    expect(
      _InitCountingChildState.initCount,
      1,
      reason: 'closing it must not remount either',
    );
  });

  testWidgets('a hidden inspector records nothing; a visible one records', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: InputInspectorHost(child: SizedBox.expand())),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(
      InputInspector.samples,
      isEmpty,
      reason: 'the always-mounted listener must gate on visibility',
    );

    InputInspector.visible.value = true;
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(InputInspector.samples, isNotEmpty);
  });

  /// 🚨★★H21 (유저 2026-08-23): 「인풋 인스펙터가 리셋도안먹고 **처음 키고
  /// 1초정도 조작하면 멈춰.** 초반1초조작만 인식하고 그 뒤 인식 안하는거같은데」
  ///
  /// ⛔THE CARD COULD NOT DIAGNOSE ITSELF. Every number on it came through
  /// the same `record()` that had stopped, so nothing on screen separated
  /// 「the observer is no longer called」 from 「it is called and the recorder
  /// drops the event」 — and I read the frozen card as evidence three times
  /// in one day before noticing.
  testWidgets('`seen` counts ARRIVALS ahead of every gate — a hidden '
      'inspector still counts, so the number can say whether delivery '
      'itself stopped', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InputInspectorHost(child: SizedBox.expand())),
    );

    expect(InputInspector.arrivals, 0);
    await tester.tapAt(const Offset(100, 100));

    final whileHidden = InputInspector.arrivals;
    expect(
      whileHidden,
      greaterThan(0),
      reason:
          '⛔a counter that stops counting when you stop looking cannot '
          'answer the question it exists for',
    );
    expect(
      InputInspector.samples,
      isEmpty,
      reason: 'and it does NOT disturb the visibility gate on the samples',
    );

    InputInspector.visible.value = true;
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(InputInspector.arrivals, greaterThan(whileHidden));
  });

  /// 🚨H21 (유저): 「터치 다운도 **껏다켜도 리셋안되고**」 — which was not a
  /// bug in the counter. Closing only flipped `visible`; nothing cleared, so
  /// re-opening showed the session before last.
  testWidgets('closing the card CLEARS it — a diagnosis surface you just '
      're-opened is a fresh one', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InputInspectorHost(child: SizedBox.expand())),
    );
    InputInspector.visible.value = true;
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(
      InputInspector.touchDownCount + InputInspector.samples.length,
      greaterThan(0),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('input-inspector-close')),
    );
    await tester.pump();

    expect(InputInspector.visible.value, isFalse);
    expect(InputInspector.samples, isEmpty);
    expect(InputInspector.touchDownCount, 0);
    expect(InputInspector.arrivals, 0);
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
