import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';

/// 🚨A PANEL IS BUILT ONLY WHILE IT SHOWS (유저 2026-10-14: 「한번이라도 열린
/// 뒤? 열려있을때만 지어지는게 맞는구조 아닌가?」 · 「이건 모든 패널
/// 공통적인 사항이야」). ↩️A heavy tab stayed mounted offstage once opened
/// (R10-②), and offstage still builds and lays out — in the I-57 playback
/// census the timeline kept behind the storyboard was 65% of every film
/// frame's rebuilds.
void main() {
  Widget group({
    required String activeTabId,
    required ValueChanged<String> onTabSelected,
    required bool cachesContent,
    List<Widget>? trailing,
    void Function()? onHeavyBuilt,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: EditorPanelTabs(
          tabs: [
            EditorPanelTab(
              id: 'heavy',
              label: 'Heavy',
              icon: Icons.timeline,
              cachesContent: cachesContent,
              builder: (context) {
                onHeavyBuilt?.call();
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
          activeTabId: activeTabId,
          onTabSelected: onTabSelected,
          trailing: trailing,
        ),
      ),
    );
  }

  testWidgets('a tab put behind another is not in the tree, cached or not — '
      'what it held goes with it', (tester) async {
    for (final cachesContent in const [false, true]) {
      var active = 'heavy';
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => group(
            activeTabId: active,
            onTabSelected: (id) => setState(() => active = id),
            cachesContent: cachesContent,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('heavy')));
      await tester.pump();
      expect(find.text('count: 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('panel-tab-light')));
      await tester.pumpAndSettle();
      expect(find.text('light-content'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('heavy'), skipOffstage: false),
        findsNothing,
        reason: 'cachesContent: $cachesContent — not offstage, not built',
      );

      // What must outlive a switch lives above the group; the panel's own
      // State is made again.
      await tester.tap(find.byKey(const ValueKey<String>('panel-tab-heavy')));
      await tester.pumpAndSettle();
      expect(find.text('count: 0'), findsOneWidget);
      expect(
        find.text('light-content', skipOffstage: false),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an open cached tab is built once however often its group is '
      'built again, and once more each time it opens (R12-①)', (tester) async {
    var heavyBuilds = 0;
    var active = 'heavy';
    var marks = 0;
    late StateSetter setOuter;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return group(
            activeTabId: active,
            onTabSelected: (id) => setState(() => active = id),
            cachesContent: true,
            // Something of the group's own that changes, so the group is
            // built again around the open tab.
            trailing: [Text('mark $marks')],
            onHeavyBuilt: () => heavyBuilds += 1,
          );
        },
      ),
    );
    expect(heavyBuilds, 1);

    for (var step = 0; step < 3; step += 1) {
      setOuter(() => marks += 1);
      await tester.pump();
    }
    expect(find.text('mark 3'), findsOneWidget);
    expect(heavyBuilds, 1, reason: 'the group handed back the same content');

    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('panel-tab-heavy')));
    await tester.pumpAndSettle();
    expect(heavyBuilds, 2, reason: 'opened again, so built again');
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
