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

  // 🗣️The second half of F-263, 「물론 클릭한게 이미지레이어같은 이동불가한
  // 대상이면 못하게 하는게 나을까 싶긴함」, answered on F-263-Q1 (유저
  // 2026-10-07): 「옮길 수 없는 행을 누르면 아무 일도 안 일어난다」 — 「이미지
  // 행 칸에서 시작한 드래그는 이동도 새 선택도 만들지 않습니다. 선택은 그대로
  // 남고, 옮기려면 선택 안의 다른 행을 잡습니다」.
  group('F-263-Q1: an image row of the selection is no grip', () {
    /// The workspace with a cel row holding a block at 3 and, above it,
    /// [images] image rows (each born with its one picture over the cut).
    Future<({EditorSessionManager s, LayerId cel, List<LayerId> images})>
    aCelRowUnderImageRows(WidgetTester tester, {int images = 1}) async {
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
      final cel = s.activeLayer!.id;
      s.selectFrameIndex(3);
      s.createDrawingAtCurrentFrame();
      final made = <LayerId>[];
      for (var i = 0; i < images; i += 1) {
        s.layerStack.addLayerOfKind(LayerKind.image);
        made.add(s.activeLayer!.id);
      }
      s.selectLayer(cel);
      await tester.pumpAndSettle();
      return (s: s, cel: cel, images: made);
    }

    Offset cell(WidgetTester tester, LayerId row, int frame) =>
        timelineCellCenter(tester, row.value, frame);

    testWidgets('a drag that starts on it moves nothing and sweeps nothing: '
        'the selection stays — and the same drag from the cel row carries '
        'it', (tester) async {
      final (:s, :cel, :images) = await aCelRowUnderImageRows(tester);
      final image = images.single;
      final block = stored(s, cel).timeline[3]!.frameId;
      final picture = stored(s, image).timeline;

      await drag(tester, cell(tester, cel, 3), cell(tester, image, 4));
      final swept = s.frameRangeSelection.value;
      expect(
        swept?.spanLayerIds,
        unorderedEquals([cel, image]),
        reason: '⛔전제: both rows swept',
      );
      final steps = s.historyManager.undoCount;

      await drag(tester, cell(tester, image, 3), cell(tester, image, 6));

      expect(
        stored(s, cel).timeline[3]?.frameId,
        block,
        reason: 'the cel row\'s block is where it was',
      );
      expect(s.frameRangeSelection.value, swept, reason: 'no new selection');
      expect(s.historyManager.undoCount, steps, reason: 'and no undo step');

      // LIVENESS — 「옮기려면 선택 안의 다른 행을 잡습니다」.
      await drag(tester, cell(tester, cel, 3), cell(tester, cel, 6));

      expect(stored(s, cel).timeline[6]?.frameId, block);
      expect(stored(s, cel).timeline[3], isNull);
      expect(stored(s, image).timeline, picture, reason: 'the picture stays');
    });

    // ⛔Asked of the ROW, not of what else is selected (작업 규칙: 선택으로
    // 법을 가르지 않는다). ↩️In a selection of image rows alone the drag
    // swept a new selection — the one row it started on.
    testWidgets('in a selection of image rows ALONE it answers the same', (
      tester,
    ) async {
      final (:s, cel: _, :images) = await aCelRowUnderImageRows(
        tester,
        images: 2,
      );
      final [lower, upper] = images;

      await drag(tester, cell(tester, lower, 3), cell(tester, upper, 4));
      final swept = s.frameRangeSelection.value;
      expect(
        swept?.spanLayerIds,
        unorderedEquals([lower, upper]),
        reason: '⛔전제: the two image rows, and nothing else',
      );

      await drag(tester, cell(tester, upper, 3), cell(tester, upper, 6));

      expect(s.frameRangeSelection.value, swept);
    });

    testWidgets('a TAP there is still a tap — it lets the selection go, as '
        'on any row', (tester) async {
      final (:s, :cel, :images) = await aCelRowUnderImageRows(tester);
      await drag(
        tester,
        cell(tester, cel, 3),
        cell(tester, images.single, 4),
      );
      expect(s.frameRangeSelection.value, isNotNull, reason: '⛔전제');

      await tester.tapAt(
        cell(tester, images.single, 3),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(s.frameRangeSelection.value, isNull);
    });

    test('which rows: an image row, and no other', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final cel = s.activeLayer!.id;
      s.layerStack.addLayerOfKind(LayerKind.image);
      final image = s.activeLayer!.id;

      expect(s.rangeMove.grabHolds(image), isTrue);
      expect(
        [
          for (final layer in s.requireActiveCut.layers)
            if (s.rangeMove.grabHolds(layer.id)) layer.id,
        ],
        [image],
        reason: 'not the cel row ($cel), the direction row or the camera',
      );
    });
  });
}
