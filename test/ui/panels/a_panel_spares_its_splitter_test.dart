import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_body.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/panels/panel_collapsed_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// 🗣️F-452 (유저 2026-10-23): 「브러시 도구 라이브러리의 스크롤바는 스플리터
/// 자리를 따로 두고 스크롤바 둬서 서로 안겹치는데, 다른 라이브러리나
/// 도구설정패널도 동일하게 … 스플리터가 생길때는 자리 안겹치게 공간 주도록.
/// 패널들 기본 그런식이지만, 타임라인/콘티패널은 예외」.
void main() {
  const band = DockEdgeSplitter.thickness;

  group('the tab group', () {
    Widget tabs({bool spares = true}) => EditorPanelTabs(
      tabs: [
        EditorPanelTab(
          id: 'panel',
          label: 'Panel',
          icon: Icons.tune,
          sparesSplitters: spares,
          builder: (context) => const _Kept(key: ValueKey('content')),
        ),
      ],
      activeTabId: 'panel',
      onTabSelected: (_) {},
    );

    Future<Rect> contentIn(WidgetTester tester, Widget group) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 400, height: 400, child: group),
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const ValueKey('content')));
    }

    testWidgets('a panel stands off the edges its splitters lie on, as deep '
        'as the band — and off no other', (tester) async {
      final whole = await contentIn(tester, tabs());

      expect(
        await contentIn(
          tester,
          DockSplitterEdges(right: true, bottom: true, child: tabs()),
        ),
        Rect.fromLTRB(
          whole.left,
          whole.top,
          whole.right - band,
          whole.bottom - band,
        ),
      );
      expect(
        await contentIn(
          tester,
          DockSplitterEdges(left: true, top: true, child: tabs()),
        ),
        Rect.fromLTRB(
          whole.left + band,
          whole.top + band,
          whole.right,
          whole.bottom,
        ),
      );
      expect(
        await contentIn(
          tester,
          DockSplitterEdges(
            left: true,
            right: true,
            bottom: true,
            child: tabs(spares: false),
          ),
        ),
        whole,
        reason: 'a tab that opts out keeps the whole panel',
      );
    });

    testWidgets('moved onto other edges, the panel stands off them — the '
        'same panel, not built again', (tester) async {
      _Kept.built = 0;
      var edges = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  TextButton(
                    onPressed: () => setState(() => edges += 1),
                    child: const Text('move'),
                  ),
                  Expanded(
                    child: DockSplitterEdges(
                      left: edges == 2,
                      right: edges == 1,
                      child: tabs(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var move = 0; move < 2; move += 1) {
        await tester.tap(find.text('move'));
        await tester.pump();
      }

      expect(_Kept.built, 1);
    });
  });

  group('docked in the workspace', () {
    Future<void> pumpHome(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      );
      await tester.pumpAndSettle();
    }

    Future<Finder> openRailGroup(WidgetTester tester, String id) async {
      final grip = find.byKey(ValueKey<String>('dock-resize-$id'));
      if (grip.evaluate().isEmpty) {
        await tester.tap(find.byKey(ValueKey<String>('rail-group-$id')));
        await tester.pumpAndSettle();
      }
      return find.ancestor(of: grip, matching: find.byType(Stack)).first;
    }

    Rect contentOf(WidgetTester tester, Finder region) => tester.getRect(
      find.descendant(of: region, matching: find.byType(PanelCollapsedScope)),
    );

    testWidgets('a rail panel stands off its inner edge and its bottom — '
        'the tool settings\' bar is no longer under the band', (tester) async {
      await pumpHome(tester);

      final settingsId = EditorWorkspace.railGroupId(right: false, slot: 2);
      final settings = await openRailGroup(tester, settingsId);
      final group = tester.getRect(settings);
      expect(
        contentOf(tester, settings),
        Rect.fromLTRB(
          group.left,
          contentOf(tester, settings).top,
          group.right - band,
          group.bottom - band,
        ),
      );
      final bar = tester.getRect(
        find.descendant(of: settings, matching: find.byType(ContentScrollbar)),
      );
      expect(
        bar.right,
        lessThanOrEqualTo(
          tester
              .getRect(find.byKey(ValueKey<String>('dock-resize-$settingsId')))
              .left,
        ),
      );

      final colours = await openRailGroup(
        tester,
        EditorWorkspace.rightGroupId,
      );
      final right = tester.getRect(colours);
      expect(contentOf(tester, colours).left, right.left + band);
      expect(contentOf(tester, colours).right, right.right);
      expect(contentOf(tester, colours).bottom, right.bottom - band);
    });

    testWidgets('the brush library looks as it did: its body stands 5 off '
        'each edge, the band\'s room counted in', (tester) async {
      await pumpHome(tester);

      final library = await openRailGroup(tester, EditorWorkspace.leftGroupId);
      final group = tester.getRect(library);
      final body = tester.getRect(
        find
            .descendant(
              of: find.descendant(
                of: library,
                matching: find.byType(EditorPanelBody),
              ),
              matching: find.byType(StaticRaster),
            )
            .first,
      );
      expect(body.left, group.left + 5);
      expect(body.right, group.right - 5);
      expect(body.bottom, group.bottom - 5);
    });

    testWidgets('the timeline and the conte keep the whole region; the '
        'region names the edges its grips are on, the folded one too', (
      tester,
    ) async {
      await pumpHome(tester);
      final region = find.byKey(const ValueKey('floating-bottom-region'));
      final left = tester.getRect(
        find.byKey(const ValueKey('bottom-inset-left')),
      );
      final right = tester.getRect(
        find.byKey(const ValueKey('bottom-inset-right')),
      );
      final height = tester.getRect(
        find.byKey(const ValueKey('dock-resize-bottom')),
      );

      for (final tab in const [
        'timeline-mode-timeline-button',
        'timeline-mode-storyboard-button',
      ]) {
        await tester.tap(find.byKey(ValueKey<String>(tab)));
        await tester.pumpAndSettle();
        final content = contentOf(tester, region);
        expect(content.left, left.left, reason: tab);
        expect(content.right, right.right, reason: tab);
        expect(content.top, height.top, reason: tab);
      }

      EdgeInsets edges() => tester
          .widget<DockSplitterEdges>(
            find.descendant(
              of: region,
              matching: find.byType(DockSplitterEdges),
            ),
          )
          .edges;
      expect(
        edges(),
        const EdgeInsets.fromLTRB(band, band, band, 0),
        reason: 'the sides, and the artwork-facing edge above',
      );

      await tester.tap(
        find.byKey(const ValueKey('floating-bottom-collapse')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-resize-bottom')), findsNothing);
      expect(
        edges(),
        const EdgeInsets.fromLTRB(band, 0, band, 0),
        reason: 'folded, the height grip is gone and its room with it',
      );
    });
  });
}

class _Kept extends StatefulWidget {
  const _Kept({super.key});

  static int built = 0;

  @override
  State<_Kept> createState() => _KeptState();
}

class _KeptState extends State<_Kept> {
  @override
  void initState() {
    super.initState();
    _Kept.built += 1;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
