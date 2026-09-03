// THE ONE WINDOW SHELL: THE TITLE AND CLOSE, A TAB STRIP WHERE ONLY AN
// UNSELECTED, ENABLED TAB ANSWERS, AND A FOOTER WHERE A NULL ACTION IS DEAD.
//
// No test named this widget (audit 2026-09-03) although every dialog in
// the app is it. These pins drive the chrome itself, not a dialog built
// on it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/app_window.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppWindow(
            title: 'Window under test',
            titleIcon: Icons.tune,
            windowKey: const ValueKey<String>('window-under-test'),
            onClose: () => events.add('close'),
            tabs: [
              AppWindowTab(
                label: 'First',
                tabKey: const ValueKey<String>('tab-first'),
                onSelected: () => events.add('first'),
              ),
              AppWindowTab(
                label: 'Second',
                tabKey: const ValueKey<String>('tab-second'),
                onSelected: () => events.add('second'),
              ),
              AppWindowTab(
                label: 'Locked',
                tabKey: const ValueKey<String>('tab-locked'),
                enabled: false,
                onSelected: () => events.add('locked'),
              ),
            ],
            selectedTab: 0,
            actions: [
              AppWindowAction(
                label: 'Cancel',
                actionKey: const ValueKey<String>('action-cancel'),
                onPressed: () => events.add('cancel'),
              ),
              const AppWindowAction(
                label: 'Never',
                actionKey: ValueKey<String>('action-never'),
                onPressed: null,
              ),
              AppWindowAction(
                label: 'Apply',
                actionKey: const ValueKey<String>('action-apply'),
                emphasis: AppWindowActionEmphasis.primary,
                onPressed: () => events.add('apply'),
              ),
            ],
            body: const Text('the body'),
          ),
        ),
      ),
    );
    return events;
  }

  testWidgets('the chrome shows the title and the body, and close closes', (
    tester,
  ) async {
    final events = await pump(tester);
    expect(find.text('Window under test'), findsOneWidget);
    expect(find.text('the body'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('app-window-close')));
    expect(events, ['close']);
  });

  testWidgets('only an unselected, enabled tab answers a tap', (tester) async {
    final events = await pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('tab-first')));
    await tester.tap(find.byKey(const ValueKey<String>('tab-locked')));
    await tester.tap(find.byKey(const ValueKey<String>('tab-second')));
    await tester.pump();
    expect(events, ['second']);
  });

  testWidgets('a footer action fires, and a null one is dead', (tester) async {
    final events = await pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('action-never')));
    await tester.tap(find.byKey(const ValueKey<String>('action-cancel')));
    await tester.tap(find.byKey(const ValueKey<String>('action-apply')));
    await tester.pump();
    expect(events, ['cancel', 'apply']);
  });
}
