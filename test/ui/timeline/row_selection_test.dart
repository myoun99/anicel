import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/delete_subject.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart'
    show layerDragRun;
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// ⑨ (user, 2026-08-12): 「레이어에도 선택 시스템 — 첫 드래그가 선택
/// (1개/여러 개), 그 다음이 드래그. 타임라인 프레임과 완전히 같은 순서.
/// 선택 상태에서 복사·삭제·이름편집(선택된 편집가능 레이어 전부를 같은
/// 이름으로 일괄 변경)」.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  List<TimelineDisplayRow> railRows(EditorSessionManager s) => [
    for (var index = 0; index < s.layers.length; index += 1)
      TimelineDisplayRow.layer(s.layers[index], layerIndex: index),
  ];

  group('the span is a slice of what the rail DRAWS', () {
    test('a drag grows the selection through the drawn rows, both ways', () {
      final s = session();
      final rows = railRows(s);
      expect(rows.length, greaterThan(2), reason: 'fixture has rows to span');

      s.beginRowSelection(rows.first.address);
      expect(s.rowSelection.value, [rows.first.address]);

      s.updateRowSelection(rows, 2);
      expect(s.rowSelection.value, [
        rows[0].address,
        rows[1].address,
        rows[2].address,
      ]);

      // Coming back shrinks it — the span is anchor-to-head, not a
      // high-water mark.
      s.updateRowSelection(rows, 1);
      expect(s.rowSelection.value, [rows[0].address, rows[1].address]);
    });

    test('a row that is drawn is selectable, whatever kind it is', () {
      // 뿌리 A's promise, restated as a row-selection test: the CAMERA row
      // is not deletable and not renameable, and it still selects.
      final s = session();
      final rows = railRows(s);
      final camera = rows.firstWhere(
        (row) => row.layer.kind == LayerKind.camera,
      );

      s.beginRowSelection(camera.address);
      expect(s.rowIsSelected(camera.address), isTrue);
      expect(
        s.deletableSelectedLayerIds(),
        isEmpty,
        reason: 'kind decides what the edit DOES, not whether it selects',
      );
    });
  });

  // 🚨유저 확정 2026-08-12: 「선택범위는 하나만 작동하도록. 프레임셀
  // 선택범위 작동시키고 레이어쪽 선택범위 작동하면 기존 프레임셀쪽
  // 사라지게. 반대도 마찬가지 (…) 즉 선택한 상태라는건 한 종류만 존재하도록」.
  group('only one kind of selection exists at a time', () {
    test('starting a ROW selection clears the frame-cell one', () {
      final s = session();
      final drawing = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      s.updateFrameRangeSelectionDrag(
        layerId: drawing.id,
        anchorIndex: 0,
        headIndex: 3,
      );
      expect(s.frameRangeSelection.value, isNotNull);

      s.beginRowSelection(LayerRowAddress(drawing.id));
      expect(s.frameRangeSelection.value, isNull);
      expect(s.rowSelection.value, isNotEmpty);
    });

    test('and starting a frame-cell selection clears the ROW one', () {
      final s = session();
      final drawing = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      s.beginRowSelection(LayerRowAddress(drawing.id));
      expect(s.rowSelection.value, isNotEmpty);

      s.updateFrameRangeSelectionDrag(
        layerId: drawing.id,
        anchorIndex: 0,
        headIndex: 3,
      );
      expect(s.rowSelection.value, isEmpty);
      expect(s.frameRangeSelection.value, isNotNull);
    });
  });

  // 🚨유저 확정 2026-08-12: 「어딘가 클릭하면 사라지도록 (…) 근데 선택된 내
  // 물건 클릭해도 사라지도록 하고싶어. 선택레이어로 ABC선택하고, C 클릭하면
  // 사라지도록. 프레임셀쪽도 마찬가지」.
  group('a CLICK clears — even a click inside the selection', () {
    test('clearAllSelections empties every kind at once', () {
      final s = session();
      final drawing = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      s.updateFrameRangeSelectionDrag(
        layerId: drawing.id,
        anchorIndex: 0,
        headIndex: 3,
      );
      expect(s.frameRangeSelection.value, isNotNull);
      s.clearAllSelections();
      expect(s.frameRangeSelection.value, isNull);

      s.beginRowSelection(LayerRowAddress(drawing.id));
      expect(s.rowSelection.value, isNotEmpty);
      s.clearAllSelections();
      expect(s.rowSelection.value, isEmpty);
    });

    testWidgets('tapping a row that is IN the selection drops it', (
      tester,
    ) async {
      // The surprising half of the rule, driven through the real rail: a
      // tap is not a drag, so the row's own InkWell reaches the host's
      // select callback and the selection goes.
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
      final drawing = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      final row = find.byKey(
        ValueKey<String>('timeline-layer-row-${drawing.id}'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();

      // Select it with a sideways nudge (the pan has to clear the slop;
      // only the rail's axis counts as travel).
      await tester.drag(row, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(s.rowSelection.value, isNotEmpty);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(s.rowSelection.value, isEmpty);
    });
  });

  group('what the row verbs then act on', () {
    test('Delete outranks the cell rung once rows are selected', () {
      final s = session();
      final drawing = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      expect(s.deleteSubject, isNot(DeleteSubject.layers));
      s.beginRowSelection(LayerRowAddress(drawing.id));
      expect(s.deleteSubject, DeleteSubject.layers);
    });

    test('deleting a row selection takes them all, in ONE undo', () {
      final s = session();
      s.addLayerOfKind(LayerKind.animation);
      s.addLayerOfKind(LayerKind.animation);
      final drawings = [
        for (final layer in s.layers)
          if (layer.kind == LayerKind.animation) layer,
      ];
      expect(drawings.length, greaterThanOrEqualTo(3));

      final doomed = drawings.take(2).map((layer) => layer.id).toList();
      s.beginRowSelection(LayerRowAddress(doomed.first));
      s.rowSelection.value = [
        for (final id in doomed) LayerRowAddress(id),
      ];

      final before = s.layers.length;
      s.deleteSelectionSubject();
      expect(s.layers.length, before - 2);
      for (final id in doomed) {
        expect(s.layers.any((layer) => layer.id == id), isFalse);
      }

      s.undo();
      expect(s.layers.length, before, reason: 'one gesture, one undo');
      for (final id in doomed) {
        expect(s.layers.any((layer) => layer.id == id), isTrue);
      }
    });

    test('deleting clears the selection — it named rows that are gone', () {
      final s = session();
      s.addLayerOfKind(LayerKind.animation);
      final doomed = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      s.beginRowSelection(LayerRowAddress(doomed.id));
      s.deleteSelectionSubject();

      expect(s.rowSelection.value, isEmpty);
      expect(s.deleteSubject, isNot(DeleteSubject.layers));
    });

    test('rename gives every selected editable row the SAME name', () {
      final s = session();
      s.addLayerOfKind(LayerKind.animation);
      final drawings = [
        for (final layer in s.layers)
          if (layer.kind == LayerKind.animation) layer,
      ];
      expect(drawings.length, greaterThanOrEqualTo(2));

      s.rowSelection.value = [
        for (final layer in drawings) LayerRowAddress(layer.id),
      ];
      s.renameSelectedLayers('BG');

      for (final layer in drawings) {
        expect(_nameOf(s, layer.id), 'BG');
      }

      s.undo();
      for (final layer in drawings) {
        expect(_nameOf(s, layer.id), layer.name, reason: 'one undo, again');
      }
    });

    test('a row that is READ-ONLY in this cut is not renamed with the rest', () {
      // ⚠️The exclusion is exactly [layerKindIsReadOnlyInCut] — the rows a
      // cut only BORROWS from its track. The camera is NOT one of them: its
      // name is editable today through the ordinary rename, and ⑨ invents no
      // new restriction (the assumption that it would was mine, and the
      // first version of this test asserted it wrongly).
      final s = session();
      final camera = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.camera,
      );
      final readOnly = s.layers
          .where((layer) => layerKindIsReadOnlyInCut(layer.kind))
          .toList();

      s.rowSelection.value = [
        LayerRowAddress(camera.id),
        for (final layer in readOnly) LayerRowAddress(layer.id),
      ];

      expect(s.renameableSelectedLayerIds(), [camera.id]);
    });
  });

  group('㊴ the selection RING, and the wash the ACTIVE row keeps', () {
    testWidgets('a selected row rings, and does not take the wash', (
      tester,
    ) async {
      // 유저: 「레이어의 선택범위가 액티브레이어랑 생긴게 똑같아서 이상함.
      // 프레임셀처럼 외곽선으로 감싸자」.
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
      final activeId = s.activeLayerId!;
      final target = s.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation && layer.id != activeId,
        orElse: () => s.layers.firstWhere((layer) => layer.id != activeId),
      );
      Color groundOf(LayerId id) {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>('timeline-layer-row-$id')),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final row = find.byKey(
        ValueKey<String>('timeline-layer-row-${target.id}'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final ring = find.byKey(
        const ValueKey<String>('timeline-row-selection-ring'),
      );
      expect(ring, findsNothing, reason: 'nothing is selected yet');

      // The sideways nudge is the SELECT drag (only the rail's axis counts
      // as travel), exactly as the click-clears test above drives it.
      await tester.drag(row, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(s.rowSelection.value, isNotEmpty);

      expect(ring, findsOneWidget, reason: '㊴: the selection is a ring');
      expect(
        groundOf(target.id),
        isNot(groundOf(activeId)),
        reason:
            '㊴: the wash belongs to the ACTIVE row. While a selected row '
            'shared it, the two states were indistinguishable — which is the '
            'whole report',
      );
    });
  });

  group('㊵ a drag carries the whole selection', () {
    test('the run widens to the selection SPAN', () {
      final s = session();
      s.addLayerOfKind(LayerKind.animation);
      final stack = s.layers;
      final lower = stack[0];
      final upper = stack[1];

      expect(
        layerDragRun(stack, lower.id),
        (start: 0, endExclusive: 1),
        reason: 'alone, an ordinary row carries itself',
      );
      expect(
        layerDragRun(stack, lower.id, alsoMoving: {lower.id, upper.id}),
        (start: 0, endExclusive: 2),
        reason: '㊵: the selection is what travels',
      );
      expect(
        layerDragRun(stack, lower.id, alsoMoving: {upper.id}),
        (start: 0, endExclusive: 1),
        reason:
            'a selection the pressed row is NOT in carries nothing extra — '
            'that press is a fresh select, not a move (⑨)',
      );
    });

    test('two selected rows land together, in order', () {
      final s = session();
      s.addLayerOfKind(LayerKind.animation);
      s.addLayerOfKind(LayerKind.animation);
      final drawings = [
        for (final layer in s.layers)
          if (layer.kind == LayerKind.animation) layer,
      ];
      expect(drawings.length, greaterThanOrEqualTo(3));
      int indexOf(LayerId id) => s.layers.indexWhere((l) => l.id == id);
      drawings.sort((a, b) => indexOf(a.id).compareTo(indexOf(b.id)));
      final first = drawings[0];
      final second = drawings[1];
      final over = drawings[2];

      s.rowSelection.value = [
        LayerRowAddress(first.id),
        LayerRowAddress(second.id),
      ];
      s.beginLayerRowDrag(LayerRowSubject(first.id));
      s.updateLayerRowDrag(s.layers, indexOf(over.id) + 1);
      expect(
        s.layerRowDrag.value?.legal,
        isTrue,
        reason: 'the landing is a plain re-order inside one section',
      );
      s.endLayerRowDrag();

      expect(
        indexOf(first.id),
        greaterThan(indexOf(over.id)),
        reason: '㊵: the pressed row moved',
      );
      expect(
        indexOf(second.id),
        greaterThan(indexOf(over.id)),
        reason:
            '㊵: and so did the other selected row — 「선택한것들 드래그해야 '
            '하는데 하나만 드래그됨」',
      );
      expect(
        indexOf(first.id),
        lessThan(indexOf(second.id)),
        reason: 'a block move keeps the carried rows in their own order',
      );
    });
  });
}

String _nameOf(EditorSessionManager s, LayerId id) =>
    s.layers.firstWhere((Layer layer) => layer.id == id).name;
