import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🗣️I-32 (유저 2026-09-14): 「… fx펼치기, … 그룹펼치기 … 레이어에 있는 버튼
/// 전부 조사하고 연결해서 일괄조작가능하게」 — on the APP's rail, whose twirl
/// hooks the workspace hands over: a hook left on a single-row verb is a
/// button that ignores the selection, and the pressed row alone would never
/// tell.
void main() {
  testWidgets('the lane twirl, pressed on a selected row, opens every '
      'selected row', (tester) async {
    final (s, a, b) = await _app(tester);

    await _tapVisible(tester, 'timeline-lane-toggle-${a.value}');

    expect(s.railView.expandedLaneLayerIds.value, containsAll([a, b]));
  });

  testWidgets('the group twirl, pressed on a selected base, folds every '
      'selected base', (tester) async {
    final (s, a, b) = await _app(tester, attachRows: true);

    await _tapVisible(tester, 'timeline-attach-twirl-${a.value}');

    expect(s.railView.collapsedAttachBaseIds.value, containsAll([a, b]));
  });

  testWidgets('the legend\'s 「all」 opens every row with a selection standing',
      (tester) async {
    final (s, a, b) = await _app(tester);

    await _tapVisible(tester, 'legend-lanes-toggle');

    expect(
      s.railView.expandedLaneLayerIds.value,
      containsAll([a, b]),
      reason: 'the first selected row\'s turn opened the second too — '
          'turning the second again would have shut both',
    );
  });
}

/// The app, two cels with the rail tall enough to press them, both selected.
Future<(EditorSessionManager, LayerId, LayerId)> _app(
  WidgetTester tester, {
  bool attachRows = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  final s = tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  s.layerStack.addLayerOfKind(LayerKind.animation);
  final cels = [
    for (final layer in s.layers)
      if (layer.kind == LayerKind.animation) layer.id,
  ];
  if (attachRows) {
    for (final base in cels) {
      s.selectLayer(base);
      s.folders.addAttachedLayer(AttachedPlacement.above);
    }
  }
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -600),
  );
  await tester.pumpAndSettle();
  s.rowSelection.value = [
    for (final id in cels.take(2)) LayerRowAddress(id),
  ];
  await tester.pumpAndSettle();
  return (s, cels[0], cels[1]);
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
