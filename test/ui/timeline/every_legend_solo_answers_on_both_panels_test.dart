import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/home_page_probes.dart';
import '../../helpers/named_finders.dart';

/// 🗣️F-408 (유저 2026-10-19): 「타임라인패널의 레전드의 종류솔로,
/// 애니메이션레이어가 없으니 추가. 대응하는 레이어가 다 있어야함.
/// 콘티패널엔 이미지레이어 없으니 대응안되는거 리스트 정리하고 애초에
/// 콘티패널은 한번 솔로 적용하면 다시 클릭해서 되돌리기가 안됨. 사본인거
/// 같으니 법 통일. 다른 레전드 행도 점검하면서 법 통일.」
///
/// Measured before the round (10-20, the default project): on the timeline
/// every solo checked and unchecked; on the conte the kind, sheet, fx and
/// fill-reference solos never showed checked and set the same solo again
/// at every press — the conte's tab listened to a hand copy of the rail's
/// view without the filter.
void main() {
  const panels = ['timeline', 'conte'];
  const solos = {
    'legend-kind': 'legend-filter-kind-animation',
    'legend-sheet': 'legend-filter-sheet',
    'legend-fx': 'legend-filter-fx',
    'legend-fill-ref': 'legend-filter-fill-ref',
    'legend-eye': 'legend-eye-solo',
  };

  Future<EditorSessionManager> open(WidgetTester tester, String panel) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
    if (panel == 'conte') {
      await showStoryboardPanel(tester);
      await tester.pumpAndSettle();
    }
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  int rows() => find.byType(TimelineLayerControlsRow).evaluate().length;

  /// The entries [menu] lists as it opens, by key — closed again after.
  Future<Map<String, bool?>> listed(WidgetTester tester, String menu) async {
    await tester.tap(find.byKey(ValueKey<String>(menu)));
    await tester.pumpAndSettle();
    final entries = {
      for (final item in tester.widgetList<PopupMenuItem<PanelFlyoutItem>>(
        find.byType(PopupMenuItem<PanelFlyoutItem>),
      ))
        if (item.key case ValueKey<String>(:final value))
          value: item.value?.checked,
    };
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    return entries;
  }

  Future<void> press(WidgetTester tester, String menu, String entry) async {
    await tester.tap(find.byKey(ValueKey<String>(menu)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(entry)));
    await tester.pumpAndSettle();
  }

  for (final panel in panels) {
    for (final MapEntry(key: menu, value: entry) in solos.entries) {
      testWidgets('🚨on the $panel, $entry is set by one press and undone by '
          'the next', (tester) async {
        await open(tester, panel);
        final start = rows();

        await press(tester, menu, entry);
        expect((await listed(tester, menu))[entry], isTrue, reason: 'set');

        await press(tester, menu, entry);
        expect((await listed(tester, menu))[entry], isFalse, reason: 'undone');
        expect(rows(), start, reason: 'every row it hid is back');
      });
    }
  }

  testWidgets('the timeline lists every kind, a row of it there or not', (
    tester,
  ) async {
    final session = await open(tester, 'timeline');
    expect(
      {for (final layer in session.layers) layer.kind},
      isNot(contains(LayerKind.image)),
      reason: '⛔전제: no image row on the cut',
    );

    final kinds = (await listed(tester, 'legend-kind')).keys;

    expect(kinds, [
      for (final kind in LayerKind.values) 'legend-filter-kind-${kind.name}',
    ]);
  });

  testWidgets('the conte lists the kinds its rows can be, and no other', (
    tester,
  ) async {
    await open(tester, 'conte');

    final kinds = (await listed(tester, 'legend-kind')).keys;

    expect(kinds, [
      for (final kind in LayerKind.values)
        if (StoryboardPanel.railKinds.contains(kind))
          'legend-filter-kind-${kind.name}',
    ]);
    for (final none in [
      LayerKind.image,
      LayerKind.instruction,
      LayerKind.adjustment,
    ]) {
      expect(kinds, isNot(contains('legend-filter-kind-${none.name}')));
    }
  });

  for (final panel in panels) {
    testWidgets('on the $panel, a kind solo takes the transition row as it '
        'takes every row', (tester) async {
      final session = await open(tester, panel);
      final prefix = panel == 'conte' ? 'storyboard' : 'timeline';
      final transition = find.named(
        '$prefix-layer-row-${session.activeTrack.transitionLayer.id}',
      );
      expect(transition, findsOneWidget, reason: '⛔전제: it stands');

      await press(tester, 'legend-kind', 'legend-filter-kind-se');

      expect(transition, findsNothing);
    });
  }
}
