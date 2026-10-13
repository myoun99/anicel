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

  // F-337 (유저 2026-10-10): 「익스포트/임포트 창이 너무 큼. 앱 화면의
  // 절반정도로」 — by area (F-337-Q1, 유저 2026-10-13: 「면적얘기야」).
  group('half the screen', () {
    test('by area — each side √½ of the screen\'s', () {
      final half = AppWindow.halfScreen(
        const BoxConstraints(maxWidth: 1920, maxHeight: 1200),
      );
      expect(half.width, closeTo(1357.6, 0.1));
      expect(half.height, closeTo(848.5, 0.1));
      expect(half.width * half.height, closeTo(1920 * 1200 / 2, 1));
    });

    test('a window\'s least wins over the half', () {
      final half = AppWindow.halfScreen(
        const BoxConstraints(maxWidth: 1280, maxHeight: 720),
        least: const Size(1018, 600),
      );
      expect((half.width, half.height), (1018.0, 600.0));
    });

    test('never more than the room the dialog leaves, least or not', () {
      final half = AppWindow.halfScreen(
        const BoxConstraints(maxWidth: 1000, maxHeight: 640),
        least: const Size(1018, 600),
      );
      expect(
        (half.width, half.height),
        (920.0, 576.0),
        reason: 'the screen less the dialog\'s own inset, 80 by 64',
      );
    });
  });
}
