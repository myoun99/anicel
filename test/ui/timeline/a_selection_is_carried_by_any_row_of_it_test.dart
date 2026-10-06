import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'timeline_cell_probe.dart';

/// 🚨F-263 (유저 2026-10-02): 「프레임 여러행,여러프레임 복수선택하고
/// 이동하려고 클릭할때, 선택내의 현재 행을 클릭해야 이동시작가능함.
/// 선택된곳 어디든 클릭하면 이동시작하도록」.
///
/// A press seats the row it lands on, and seating a row dropped any frame
/// selection whose ANCHOR was another row — a clause from when a selection
/// was one row (UI-R8). Pressed on any other row it covered, the selection
/// was gone before the drag began, and the drag swept a new one.
///
/// The hand's own gesture: the law of where a carried span lands is pinned a
/// layer down (`session/a_block_leaves_a_row_that_carries_attach_rows_test`
/// and its neighbours); this says the press that starts it is let through.
void main() {
  Layer stored(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  /// The workspace with four cel rows, bottom to top: [lower] and [upper]
  /// each holding a block at 3, then two empty rows above them.
  Future<
    ({
      EditorSessionManager s,
      LayerId lower,
      LayerId upper,
      LayerId above,
    })
  >
  twoBlocksUnderEmptyRows(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    LayerId added() {
      s.layerStack.addLayerOfKind(LayerKind.animation);
      return s.activeLayer!.id;
    }

    final lower = s.activeLayer!.id;
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    final upper = added();
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    final above = added();
    s.selectLayer(lower);
    await tester.pumpAndSettle();
    return (s: s, lower: lower, upper: upper, above: above);
  }

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset to, {
    int steps = 6,
  }) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final step = (to - from) / steps.toDouble();
    for (var i = 0; i < steps; i += 1) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // The clause itself, where a press is not needed to ask it: seated on a
  // row the selection covers it is kept, on any other it is let go.
  test('a selection is let go by a row it does not cover — and kept by '
      'one it does', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    LayerId added() {
      s.layerStack.addLayerOfKind(LayerKind.animation);
      return s.activeLayer!.id;
    }

    final lower = s.activeLayer!.id;
    final upper = added();
    final outside = added();
    s.updateFrameRangeSelectionDrag(
      layerId: lower,
      anchorIndex: 3,
      headIndex: 4,
      headLayerId: upper,
    );
    final swept = s.frameRangeSelection.value;
    expect(
      swept?.spanLayerIds,
      unorderedEquals([lower, upper]),
      reason: '⛔전제',
    );

    s.selectLayer(upper);
    expect(s.frameRangeSelection.value, swept);

    s.selectLayer(outside);
    expect(s.frameRangeSelection.value, isNull);
  });

  for (final sweptFromTheUpperRow in [false, true]) {
    testWidgets('two rows swept from the '
        '${sweptFromTheUpperRow ? 'upper' : 'lower'} one are carried a row '
        'up by the OTHER — the row the sweep did not start on', (
      tester,
    ) async {
      final (:s, :lower, :upper, :above) = await twoBlocksUnderEmptyRows(
        tester,
      );
      final lowerCel = stored(s, lower).timeline[3]!.frameId;
      final upperCel = stored(s, upper).timeline[3]!.frameId;
      Offset cell(LayerId row) => timelineCellCenter(tester, row.value, 3);
      final start = sweptFromTheUpperRow ? upper : lower;
      final other = sweptFromTheUpperRow ? lower : upper;

      await drag(tester, cell(start), cell(other));
      expect(
        s.frameRangeSelection.value?.spanLayerIds,
        unorderedEquals([lower, upper]),
        reason: '⛔전제: both rows swept',
      );
      expect(s.frameRangeSelection.value?.layerId, start, reason: '⛔전제');

      // One row up from the row it is grabbed by: onto [above] from the
      // upper row, and — from the lower — onto the upper row, the one the
      // sweep is anchored on when it began there.
      await drag(tester, cell(other), cell(other == upper ? above : upper));

      expect(stored(s, upper).timeline[3]?.frameId, lowerCel);
      expect(stored(s, above).timeline[3]?.frameId, upperCel);
      expect(stored(s, lower).timeline[3], isNull);
    });
  }
}
