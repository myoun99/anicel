import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

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

  testWidgets('a tab put behind another is not in the tree — what it held '
      'goes with it', (tester) async {
    var active = 'heavy';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => group(
          activeTabId: active,
          onTabSelected: (id) => setState(() => active = id),
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
      reason: 'not offstage, not built',
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
  });

  testWidgets('an open tab is built once however often its group is built '
      'again, and once more each time it opens (R12-①)', (tester) async {
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

  testWidgets('an open tab is built again in another language, program or '
      'notation, and keeps its State', (tester) async {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    var heavyBuilds = 0;
    await tester.pumpWidget(
      group(
        activeTabId: 'heavy',
        onTabSelected: (_) {},
        onHeavyBuilt: () => heavyBuilds += 1,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('heavy')));
    await tester.pump();
    expect(heavyBuilds, 1);

    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ja,
    );
    await tester.pump();
    expect(
      heavyBuilds,
      2,
      reason: '🚨nothing above it is rebuilt here — the group hears it',
    );
    expect(find.text('count: 1'), findsOneWidget, reason: 'built, not made');

    AppText.settings.value = AppText.settings.value.copyWith(
      notationLanguage: AppLanguage.ko,
    );
    await tester.pump();
    expect(heavyBuilds, 3, reason: 'the notation reprints a sheet');
  });

  testWidgets('an open tab is handed back only to itself, and only while it '
      'is built for the same thing (I-7)', (tester) async {
    Widget cachedPair(String activeTabId, Object identity, String said) {
      EditorPanelTab tab(String id) => EditorPanelTab(
        id: id,
        label: id,
        icon: Icons.timeline,
        builder: (context) => Text('$id for $said'),
      ).builtFor(identity);
      return MaterialApp(
        home: Scaffold(
          body: EditorPanelTabs(
            tabs: [tab('timeline'), tab('storyboard')],
            activeTabId: activeTabId,
            onTabSelected: (_) {},
          ),
        ),
      );
    }

    final project = Object();
    await tester.pumpWidget(cachedPair('timeline', project, 'a'));
    expect(find.text('timeline for a'), findsOneWidget);

    await tester.pumpWidget(cachedPair('storyboard', project, 'a'));
    expect(
      find.text('storyboard for a'),
      findsOneWidget,
      reason: 'the tab put in front is built, not handed the one before',
    );

    await tester.pumpWidget(cachedPair('storyboard', Object(), 'b'));
    expect(
      find.text('storyboard for b'),
      findsOneWidget,
      reason: '🚨built for another project, the open tab is built again — '
          'the cached one went on showing the project switched away from',
    );
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
