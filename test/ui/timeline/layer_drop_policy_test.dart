import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';

/// The row-order drag's whole judgement, with no widgets in the way: what
/// travels, which way the surface runs, where the run lands, and what the
/// drop is not allowed to do.

Layer _row(
  String id, {
  LayerKind kind = LayerKind.animation,
  String? folderId,
  String? attachedTo,
  AttachedPlacement placement = AttachedPlacement.above,
}) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  kind: kind,
  folderId: folderId == null ? null : LayerId(folderId),
  attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
  attachedPlacement: placement,
  attachedMode: AttachedMode.free,
);

List<String> _ids(List<LayerId> order) => [for (final id in order) id.value];

void main() {
  group('what travels', () {
    test('a plain row takes itself', () {
      final stack = [_row('a'), _row('b'), _row('c')];
      expect(layerDragRun(stack, const LayerId('b')), (
        start: 1,
        endExclusive: 2,
      ));
    });

    test('a folder takes its subtree, and the folder sits at the run top', () {
      // Stack invariant: members first, folder DIRECTLY above them.
      final stack = [
        _row('below'),
        _row('m1', folderId: 'F'),
        _row('m2', folderId: 'F'),
        _row('F', kind: LayerKind.folder),
        _row('above'),
      ];
      expect(layerDragRun(stack, const LayerId('F')), (
        start: 1,
        endExclusive: 4,
      ));
    });

    test('an attach BASE takes its group; an attach ROW takes only itself', () {
      final stack = [
        _row('under', attachedTo: 'base', placement: AttachedPlacement.below),
        _row('base'),
        _row('over', attachedTo: 'base'),
        _row('other'),
      ];
      expect(layerDragRun(stack, const LayerId('base')), (
        start: 0,
        endExclusive: 3,
      ));
      expect(layerDragRun(stack, const LayerId('over')), (
        start: 2,
        endExclusive: 3,
      ));
    });
  });

  group('which way the surface runs is inferred, not declared', () {
    final stack = [_row('a'), _row('b'), _row('c')];

    test('the horizontal rail renders the stack reversed', () {
      final rows = horizontalLayerDisplayOrder(stack); // c, b, a
      expect([for (final row in rows) row.id.value], ['c', 'b', 'a']);
      // Every gap, top of the list → bottom.
      expect(
        [
          for (var slot = 0; slot <= rows.length; slot += 1)
            modelInsertionForSlot(stack: stack, displayRows: rows, slot: slot),
        ],
        [3, 2, 1, 0],
      );
    });

    test('the sheet renders it raw', () {
      final rows = xsheetLayerDisplayOrder(stack); // a, b, c
      expect(
        [
          for (var slot = 0; slot <= rows.length; slot += 1)
            modelInsertionForSlot(stack: stack, displayRows: rows, slot: slot),
        ],
        [0, 1, 2, 3],
      );
    });

    test('a caret among rows this stack does not own answers null', () {
      final foreign = [_row('se1', kind: LayerKind.se)];
      expect(
        modelInsertionForSlot(stack: stack, displayRows: foreign, slot: 0),
        isNull,
      );
    });
  });

  group('where the run lands', () {
    test('a plain move rewrites the order and touches no membership', () {
      final stack = [_row('a'), _row('b'), _row('c')];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('a'),
        insertAt: 3,
      )!;
      expect(_ids(plan.order), ['b', 'c', 'a']);
      expect(plan.folderIds, isEmpty);
      expect(plan.joinedFolderId, isNull);
    });

    test('dropping between a folder\'s members JOINS the folder', () {
      final stack = [
        _row('loose'),
        _row('m1', folderId: 'F'),
        _row('m2', folderId: 'F'),
        _row('F', kind: LayerKind.folder),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('loose'),
        insertAt: 2,
      )!;
      expect(_ids(plan.order), ['m1', 'loose', 'm2', 'F']);
      expect(plan.folderIds, {const LayerId('loose'): const LayerId('F')});
      expect(plan.joinedFolderId, const LayerId('F'));
    });

    test('dropping above the folder ROW leaves the folder', () {
      final stack = [
        _row('m1', folderId: 'F'),
        _row('m2', folderId: 'F'),
        _row('F', kind: LayerKind.folder),
        _row('top'),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('m1'),
        insertAt: 4,
      )!;
      expect(_ids(plan.order), ['m2', 'F', 'top', 'm1']);
      expect(plan.folderIds, {const LayerId('m1'): null});
      expect(plan.joinedFolderId, isNull);
    });

    test('a folder travels whole, and only IT changes hands', () {
      final stack = [
        _row('bottom'),
        _row('m1', folderId: 'F'),
        _row('F', kind: LayerKind.folder),
        _row('o1', folderId: 'OUTER'),
        _row('OUTER', kind: LayerKind.folder),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('F'),
        insertAt: 4,
      )!;
      expect(_ids(plan.order), ['bottom', 'o1', 'm1', 'F', 'OUTER']);
      // The member kept pointing at the folder that carried it.
      expect(plan.folderIds, {const LayerId('F'): const LayerId('OUTER')});
      expect(plan.joinedFolderId, const LayerId('OUTER'));
    });
  });

  group('what the drop may not do', () {
    test('a slot inside the run itself is a no-op, not a move', () {
      final stack = [
        _row('m1', folderId: 'F'),
        _row('m2', folderId: 'F'),
        _row('F', kind: LayerKind.folder),
      ];
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('F'),
          insertAt: 2,
        ),
        isNull,
      );
    });

    test('it cannot cross a SECTION — the display would spring it back', () {
      final stack = [
        _row('draw'),
        _row('se', kind: LayerKind.se),
        _row('cam', kind: LayerKind.camera),
      ];
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('draw'),
          insertAt: 3,
        ),
        isNull,
        reason: 'the drawing row would land in the camera section',
      );
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('cam'),
          insertAt: 0,
        ),
        isNull,
      );
    });

    test('a plain row may not join an attach ORGANIZER folder', () {
      // [연출] holds nothing but one base's attach rows; letting a stranger
      // in would silently stop it being an organizer.
      final stack = [
        _row('base'),
        _row('a1', attachedTo: 'base', folderId: 'ORG'),
        _row('ORG', kind: LayerKind.folder),
        _row('loose'),
      ];
      expect(folderStructureProblem(stack), isNull, reason: 'fixture is sound');
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('loose'),
          insertAt: 2,
        ),
        isNull,
      );
    });

    test('an attach row may leave its group — the group is the caller\'s '
        'business, and the structure validator lets this through', () {
      // Documents the boundary this policy does NOT enforce: detaching is
      // P3's verb, so the ORDER policy only refuses what the structure
      // rules refuse. The gesture layer keeps attach rows in their group
      // until that verb exists.
      final stack = [
        _row('base'),
        _row('over', attachedTo: 'base'),
        _row('other'),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('over'),
        insertAt: 3,
      );
      expect(plan, isNotNull);
    });
  });

  group('SE rows are a flat permutation', () {
    test('a move rewrites the track list', () {
      final se = [
        _row('s1', kind: LayerKind.se),
        _row('s2', kind: LayerKind.se),
        _row('s3', kind: LayerKind.se),
      ];
      final rows = horizontalLayerDisplayOrder(se); // s3, s2, s1
      final order = resolveTrackSeDrop(
        seLayers: se,
        displayRows: rows,
        movingId: const LayerId('s1'),
        slot: 0,
      )!;
      expect(_ids(order), ['s2', 's3', 's1']);
    });

    test('landing back where it started is not a move', () {
      final se = [
        _row('s1', kind: LayerKind.se),
        _row('s2', kind: LayerKind.se),
      ];
      final rows = horizontalLayerDisplayOrder(se); // s2, s1
      expect(
        resolveTrackSeDrop(
          seLayers: se,
          displayRows: rows,
          movingId: const LayerId('s1'),
          slot: 2,
        ),
        isNull,
      );
    });
  });
}
