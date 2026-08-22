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

  /// 🚨★★★H21 — **THE FREEZE.** (유저 2026-08-23, 스택 트레이스): 「인스펙터
  /// 키고 **터치하거나 키보드 조작하거나 마우스 클릭하거나 하면 뜸**」
  ///
  /// ```
  /// setState() or markNeedsBuild() called during build.
  ///   #6 InputInspector.note   #7 _buildInteractiveCanvas
  ///   #11 _FrameRetargetScopeState.build
  /// ```
  ///
  /// ⛔`State.setState` runs its callback and THEN marks the element dirty,
  /// so the throw leaves the value updated and the element clean: the card
  /// keeps the frame it was showing and nothing can wake it again. The
  /// recorder was never broken — only the picture stopped.
  ///
  /// ⚠️**THIS TEST DOES NOT REPRODUCE THE THROW, AND SAYING SO IS THE
  /// POINT.** The app's stack goes `_RenderLayoutBuilder.performLayout` →
  /// `BuildOwner.buildScope` — a NESTED build scope opened during LAYOUT,
  /// with the card outside it, which is what makes the assert fire. A plain
  /// rebuild here keeps the card inside the same scope, so Flutter permits
  /// the dirty mark and nothing throws either way (checked: it passes with
  /// the deferral removed).
  ///
  /// ⇒ What it DOES pin is the contract that survives the refactor: a probe
  /// fired from inside a build still reaches the card, one rebuild per
  /// frame. The freeze itself is fixed on the strength of the user's stack
  /// trace, not on the strength of this test, and I would rather write that
  /// down than let a green tick imply more than it earned.
  testWidgets('a probe fired DURING BUILD does not throw, and the card still '
      'updates — the freeze was the notification, not the recorder', (
    tester,
  ) async {
    InputInspector.visible.value = true;
    // The child probes from inside its own build, as
    // `_buildInteractiveCanvas` does.
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: InputInspectorHost(
          child: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, tick, _) {
              InputInspector.note('probe $tick');
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    // ⚠️The FIRST build cannot show the bug: the card is a later sibling in
    // the host's Stack, so it is not listening yet when that probe fires.
    // The freeze needs a rebuild while the card is ALREADY mounted — which
    // is the situation on screen, and why this has to be a second pump.
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsOneWidget,
      reason: 'fixture premise: the card is mounted and listening',
    );
    final before = InputInspector.revision.value;

    rebuild.value += 1;
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          '⛔this is the report: notifying during build threw, and the '
          'throw left the card permanently un-dirty',
    );
    expect(InputInspector.notes, isNotEmpty);

    // And the deferred bump really does arrive.
    await tester.pump();
    expect(InputInspector.revision.value, greaterThan(before));
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
