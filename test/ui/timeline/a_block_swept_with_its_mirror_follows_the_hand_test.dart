import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'timeline_cell_probe.dart';

/// 🚨F-276 (유저 2026-10-04): 「지금 어태치 싱크레이어를 가진 레이어의 블록을
/// 다른 레이어로 이동하는게 불가능한데 가능하도록」 — the hand's own gesture.
///
/// A block shows on its row and again on the mirror under it, so the sweep
/// that picks it up takes both — here it starts on the mirror — and the
/// hand carries it off by the mirror it pressed first. The law is pinned a
/// layer down
/// (`session/a_block_leaves_a_row_that_carries_attach_rows_test.dart`);
/// this is the one press-drag-release that says the rail hands the drag
/// what that law reads — the rows swept, the row grabbed, the row pointed
/// at.
///
/// ⚠️Carried by the row the sweep did NOT start on is another card's
/// (F-263): a press there still drops a multi-row selection before any
/// move can begin.
void main() {
  Layer stored(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  testWidgets('swept together with the mirror under it — from the mirror up — '
      'and carried off by it, the block lands where the hand stops', (
    tester,
  ) async {
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
    final base = s.activeLayer!.id;
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    s.folders.addAttachedLayer(AttachedPlacement.below);
    final mirror = s.activeLayer!.id;
    s.selectLayer(base);
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final other = s.activeLayer!.id;
    s.selectLayer(base);
    await tester.pumpAndSettle();
    final cel = stored(s, base).timeline[3]!.frameId;

    final onBase = timelineCellCenter(tester, base.value, 3);
    final onMirror = timelineCellCenter(tester, mirror.value, 3);
    final onOther = timelineCellCenter(tester, other.value, 3);
    expect(
      [onOther.dy < onBase.dy, onBase.dy < onMirror.dy],
      [true, true],
      reason: '⛔전제: the other row, the base, its mirror — top to bottom',
    );

    final sweep = await tester.startGesture(
      onMirror,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await sweep.moveTo(onBase);
    await tester.pump();
    await sweep.up();
    await tester.pumpAndSettle();
    expect(
      s.frameRangeSelection.value?.spanLayerIds,
      unorderedEquals([base, mirror]),
      reason: '⛔전제: the sweep took the block and its mirror',
    );

    final carry = await tester.startGesture(
      onMirror,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final step = (onOther - onMirror) / 6;
    for (var i = 0; i < 6; i += 1) {
      await carry.moveBy(step);
      await tester.pump();
    }
    await carry.up();
    await tester.pumpAndSettle();

    expect(stored(s, other).timeline[3]?.frameId, cel);
    expect(stored(s, base).timeline[3], isNull);
  });
}
