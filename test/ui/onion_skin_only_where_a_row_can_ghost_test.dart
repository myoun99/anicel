import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart' show RailButton;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

/// 🚨F-145 (유저 2026-09-17): 「폴더등 어니언스킨 활성화 불가능한 곳에
/// 서있는데 왼쪽띠의 어니언스킨버튼이 활성화되있고 조작마저가능함.
/// 비활성화하도록. 낡지않을구조로」.
///
/// The row's own onion cell, the legend's sweep and the ghosts themselves
/// already asked whether a row can ghost; the rail button, the `O` key and
/// the toggle did not. ⛔So the pin is EVERY kind a row can be — a folder was
/// the case the user met, and a kind added later is the case nobody would.
void main() {
  test('on every kind of row, the onion toggle is lit exactly where the row '
      'can ghost, and does nothing anywhere else', () {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    for (final kind in LayerKind.values) {
      session.layerStack.addLayerOfKind(kind);
    }
    final rows = session.layers;
    expect(
      {for (final row in rows) row.kind},
      containsAll([LayerKind.folder, LayerKind.animation]),
      reason: 'LIVENESS — both answers are on the stack',
    );

    for (final row in rows) {
      session.selectLayer(row.id);
      final ghosts = row.kind.takesOnionSkin;
      expect(
        session.onionSkin.canToggleOnionSkin,
        ghosts,
        reason: '${row.kind.name}: the rail button lights where it can ghost',
      );

      final before = session.onionSkin.layerIds.value.contains(row.id);
      final undos = session.historyManager.undoCount;
      session.onionSkin.toggleOnionSkin();
      expect(
        session.onionSkin.layerIds.value.contains(row.id),
        ghosts ? !before : before,
        reason: '${row.kind.name}: the `O` key and the rail button press '
            'this verb',
      );
      expect(
        session.historyManager.undoCount,
        undos + (ghosts ? 1 : 0),
        reason: '${row.kind.name}: a refused press leaves no undo step',
      );
    }
  });

  testWidgets('the left strip\'s onion button is dark on a folder and lit on '
      'a drawing row', (tester) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final drawing = session.activeLayer!;
    expect(drawing.kind.takesOnionSkin, isTrue, reason: 'LIVENESS');
    session.layerStack.addLayerOfKind(LayerKind.folder);
    final folder = session.layers.firstWhere(
      (row) => row.kind == LayerKind.folder,
    );

    VoidCallback? railOnion() => tester
        .widget<RailButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RailButton &&
                widget.keyValue == 'rail-onion-skin-button',
          ),
        )
        .onPressed;

    session.selectLayer(folder.id);
    await tester.pumpAndSettle();
    expect(railOnion(), isNull, reason: '「비활성화하도록」');

    session.selectLayer(drawing.id);
    await tester.pumpAndSettle();
    expect(railOnion(), isNotNull);
  });
}
