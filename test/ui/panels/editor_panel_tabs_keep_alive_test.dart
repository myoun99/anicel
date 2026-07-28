import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/panels/panel_visibility_scope.dart';

/// R10-②: keep-alive tabs stay mounted offstage across switches (instant
/// switch-back, state preserved); plain tabs unmount as before.
void main() {
  Widget host({
    required String activeTabId,
    required ValueChanged<String> onTabSelected,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: EditorPanelTabs(
          tabs: [
            EditorPanelTab(
              id: 'heavy',
              label: 'Heavy',
              icon: Icons.timeline,
              keepAlive: true,
              builder: (context) => const _CounterBox(key: ValueKey('heavy')),
            ),
            EditorPanelTab(
              id: 'light',
              label: 'Light',
              icon: Icons.palette,
              builder: (context) => const Text('light-content'),
            ),
          ],
          activeTabId: activeTabId,
          onTabSelected: onTabSelected,
        ),
      ),
    );
  }

  testWidgets('a keep-alive tab keeps its STATE across switches; a plain '
      'tab unmounts', (tester) async {
    var active = 'heavy';
    Future<void> pump() async {
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => host(
            activeTabId: active,
            onTabSelected: (id) => setState(() => active = id),
          ),
        ),
      );
      await tester.pump();
    }

    await pump();
    // Bump the heavy tab's local state.
    await tester.tap(find.byKey(const ValueKey('heavy')));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);

    // Switch away: the heavy subtree stays mounted (offstage, not
    // hittable), the light tab mounts fresh. Finders must opt INTO
    // offstage widgets to see it.
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-light')));
    await tester.pumpAndSettle();
    expect(find.text('light-content'), findsOneWidget);
    expect(find.text('count: 1', skipOffstage: false), findsOneWidget);
    expect(find.text('count: 1'), findsNothing);

    // Switch back: the state survived — no rebuild from scratch.
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-heavy')));
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);

    // The plain tab unmounted when it lost the stage.
    expect(find.text('light-content', skipOffstage: false), findsNothing);
  });

  testWidgets('a keep-alive tab builder runs ONCE: switches and strip '
      'rebuilds reuse the cached content instance (R12-①)', (tester) async {
    var heavyBuilds = 0;
    var active = 'heavy';
    Future<void> pump() async {
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: EditorPanelTabs(
                tabs: [
                  EditorPanelTab(
                    id: 'heavy',
                    label: 'Heavy',
                    icon: Icons.timeline,
                    keepAlive: true,
                    builder: (context) {
                      heavyBuilds += 1;
                      return const _CounterBox(key: ValueKey('heavy'));
                    },
                  ),
                  EditorPanelTab(
                    id: 'light',
                    label: 'Light',
                    icon: Icons.palette,
                    builder: (context) => const Text('light-content'),
                  ),
                ],
                activeTabId: active,
                onTabSelected: (id) => setState(() => active = id),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump();
    expect(heavyBuilds, 1);

    // Switch away and back: the cached instance short-circuits the
    // subtree diff — the heavy builder never runs again.
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-heavy')));
    await tester.pumpAndSettle();
    expect(heavyBuilds, 1);
  });

  testWidgets('PanelAwareListenableBuilder stands down offstage and '
      'catches up ON re-activation (R12-①)', (tester) async {
    final signal = ChangeNotifier();
    addTearDown(signal.dispose);
    var value = 0;
    var builds = <int>[];
    var active = 'gated';
    Future<void> pump() async {
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: EditorPanelTabs(
                tabs: [
                  EditorPanelTab(
                    id: 'gated',
                    label: 'Gated',
                    icon: Icons.timeline,
                    keepAlive: true,
                    builder: (context) => PanelAwareListenableBuilder(
                      listenable: signal,
                      builder: (context) {
                        builds.add(value);
                        return Text('value: $value');
                      },
                    ),
                  ),
                  EditorPanelTab(
                    id: 'other',
                    label: 'Other',
                    icon: Icons.palette,
                    builder: (context) => const Text('other-content'),
                  ),
                ],
                activeTabId: active,
                onTabSelected: (id) => setState(() => active = id),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump();
    expect(builds, [0]);

    // Visible: notifies rebuild as usual.
    value = 1;
    signal.notifyListeners();
    await tester.pump();
    expect(builds, [0, 1]);
    expect(find.text('value: 1'), findsOneWidget);

    // Hidden: notifies are swallowed — no rebuild back there.
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-other')));
    await tester.pumpAndSettle();
    builds = [];
    value = 2;
    signal.notifyListeners();
    await tester.pump();
    expect(builds, isEmpty, reason: 'offstage panels never rebuild');

    // Re-activation flushes ONE catch-up rebuild with the fresh value.
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-gated')));
    await tester.pumpAndSettle();
    expect(builds, [2]);
    expect(find.text('value: 2'), findsOneWidget);

    // Nothing changed while hidden → switching back is rebuild-free.
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-gated')));
    await tester.pumpAndSettle();
    expect(builds, [2], reason: 'clean re-activation skips the catch-up');
  });
}

class _CounterBox extends StatefulWidget {
  const _CounterBox({super.key});

  @override
  State<_CounterBox> createState() => _CounterBoxState();
}

class _CounterBoxState extends State<_CounterBox> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _count += 1),
      child: ColoredBox(
        color: Colors.transparent,
        child: Center(child: Text('count: $_count')),
      ),
    );
  }
}
