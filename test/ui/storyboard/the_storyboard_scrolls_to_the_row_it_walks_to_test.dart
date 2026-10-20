import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/app_shortcuts.dart';
import '../../helpers/home_page_probes.dart';

/// 🗣️F-361 (유저 2026-10-14): 「콘티패널만 위아래 플립할때 스크롤바 알아서
/// 작동안함. 법 통일」 — the storyboard's rows follow its ↑/↓ walk as the
/// timeline's follow its own: the row you step to is brought into view.
/// The canvas flip presses the same actions the arrow keys do.
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  ScrollPosition rows(WidgetTester tester) => tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('storyboard-vertical-viewport'),
          ),
          matching: find.byType(Scrollable),
        ),
      )
      .first
      .position;

  /// Presses [key] until the storyboard stands on [row], at most [steps]
  /// times.
  Future<void> walkTo(
    WidgetTester tester,
    LogicalKeyboardKey key,
    TimelineRowAddress row, {
    int steps = 40,
  }) async {
    final session = sessionOf(tester);
    for (var step = 0; step < steps && session.currentRow != row; step += 1) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(session.currentRow, row, reason: '⛔전제: the walk got there');
  }

  testWidgets('a walk down past the foot of the view scrolls the rows to the '
      'row it stands on, and a walk back up scrolls them back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await useAnicelKeys(tester);
    final session = sessionOf(tester);
    // S rows enough to run the rail past the view.
    session.selectLayer(
      session.layers.firstWhere((layer) => layer.kind == LayerKind.se).id,
    );
    for (var count = 0; count < 12; count += 1) {
      session.layerStack.addLayerOfKind(LayerKind.se);
    }
    await showStoryboardPanel(tester);
    final track = session.repository.requireProject().tracks.single;
    final top = LayerRowAddress(trackCameraRowId(track.id));
    final bottom = LayerRowAddress(trackConteRowId(track.id));
    session.standOnRow(top, panel: WorkingPanel.storyboard);
    await tester.pumpAndSettle();
    rows(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      rows(tester).maxScrollExtent,
      greaterThan(0),
      reason: '⛔전제: the rail runs past the view',
    );

    await walkTo(tester, LogicalKeyboardKey.arrowDown, bottom);
    expect(
      rows(tester).pixels,
      rows(tester).maxScrollExtent,
      reason: 'the last row is brought into view',
    );

    await walkTo(tester, LogicalKeyboardKey.arrowUp, top);
    expect(rows(tester).pixels, 0, reason: 'and the first, back up');
    expect(session.workingPanel, WorkingPanel.storyboard);
  });
}
