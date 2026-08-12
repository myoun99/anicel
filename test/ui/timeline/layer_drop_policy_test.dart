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

    test('a row that cannot join a group may not land INSIDE one either — '
        'the group is unsplittable', () {
      // 'F' sits clear of the group on purpose: since ④ a row's own two gaps
      // are not landings, so a mover parked on the edge it is meant to prove
      // reachable would answer null for a reason that has nothing to do with
      // the group.
      final stack = [
        _row('under'),
        _row('base'),
        _row('over', attachedTo: 'base'),
        _row('spare'),
        _row('F', kind: LayerKind.folder),
        _row('se', kind: LayerKind.se),
      ];
      expect(folderStructureProblem(stack), isNull, reason: 'fixture is sound');
      // A FOLDER cannot be somebody's attach row, so the slot between the
      // base and its attach row refuses it rather than cutting the run.
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('F'),
          insertAt: 2,
        ),
        isNull,
      );
      // Its outer edges stay open: "next to the group" is always reachable.
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('F'),
          insertAt: 3,
        ),
        isNotNull,
      );
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('F'),
          insertAt: 1,
        ),
        isNotNull,
      );
    });
  });

  // ---------------------------------------------------------------------
  // P3: the drop MAKES and BREAKS attach relationships.
  // ---------------------------------------------------------------------

  group('a drop strictly INSIDE a group mounts', () {
    List<Layer> groupStack() => [
      _row('bottom'),
      _row('base'),
      _row('over', attachedTo: 'base'),
      _row('top'),
    ];

    test('above the base when the slot is above it', () {
      final plan = resolveLayerDrop(
        stack: groupStack(),
        movingId: const LayerId('top'),
        insertAt: 2, // between base and over
      )!;
      expect(plan.attach.mount, (
        layerId: const LayerId('top'),
        baseId: const LayerId('base'),
        placement: AttachedPlacement.above,
      ));
      expect(plan.attach.detachIds, isEmpty);
      expect(_ids(plan.order), ['bottom', 'base', 'top', 'over']);
    });

    test('below the base when the slot is below it', () {
      final stack = [
        _row('bottom'),
        _row('under', attachedTo: 'base', placement: AttachedPlacement.below),
        _row('base'),
        _row('top'),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('top'),
        insertAt: 2, // between under and base
      )!;
      expect(plan.attach.mount?.placement, AttachedPlacement.below);
    });

    test('NOT at the group\'s outer edges — passing above or below a group '
        'commits nothing', () {
      for (final slot in [1, 3]) {
        final plan = resolveLayerDrop(
          stack: groupStack(),
          movingId: const LayerId('top'),
          insertAt: slot,
        );
        expect(
          plan?.attach.mount,
          isNull,
          reason: 'slot $slot touches the group but is not inside it',
        );
      }
    });

    test('and a bare drawing row is not a group at all — the ordinary '
        're-order over another layer stays ordinary', () {
      final stack = [_row('a'), _row('b'), _row('c')];
      for (var slot = 0; slot <= 3; slot += 1) {
        expect(
          resolveLayerDrop(
            stack: stack,
            movingId: const LayerId('c'),
            insertAt: slot,
          )?.attach.mount,
          isNull,
          reason: 'slot $slot',
        );
      }
    });

    test('landing among a 공정 ORGANIZER\'s members mounts on THAT group\'s '
        'base and joins the folder', () {
      final stack = [
        _row('base'),
        _row('a1', attachedTo: 'base', folderId: 'ORG'),
        _row('ORG', kind: LayerKind.folder),
        _row('loose'),
      ];
      expect(folderStructureProblem(stack), isNull, reason: 'fixture is sound');
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('loose'),
        insertAt: 2,
      )!;
      expect(plan.attach.mount?.baseId, const LayerId('base'));
      expect(plan.folderIds, {const LayerId('loose'): const LayerId('ORG')});
    });
  });

  group('leaving a group detaches', () {
    test('an attach row dragged clear of its group', () {
      final stack = [
        _row('base'),
        _row('over', attachedTo: 'base'),
        _row('one'),
        _row('two'),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('over'),
        insertAt: 4,
      )!;
      expect(plan.attach.detachIds, {const LayerId('over')});
      expect(plan.attach.mount, isNull);
    });

    test('but re-ordering INSIDE the group does not — either direction, and '
        'crossing the base flips the side instead', () {
      final stack = [
        _row('base'),
        _row('a1', attachedTo: 'base'),
        _row('a2', attachedTo: 'base'),
        _row('top'),
      ];
      // The topmost attach row nudged one place up: still the group's.
      final up = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('a1'),
        insertAt: 3,
      )!;
      expect(up.attach.detachIds, isEmpty);
      expect(_ids(up.order), ['base', 'a2', 'a1', 'top']);
      // And one place down, past the base: attached still, other side.
      final down = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('a1'),
        insertAt: 0,
      )!;
      expect(down.attach.detachIds, isEmpty);
      expect(_ids(down.order), ['a1', 'base', 'a2', 'top']);
    });

    test('a LONE attach row can cross its base and stay attached — the base '
        'still reads as a base while its only rider is in the air', () {
      final stack = [_row('base'), _row('over', attachedTo: 'base')];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('over'),
        insertAt: 0,
      )!;
      expect(plan.attach.detachIds, isEmpty);
      expect(_ids(plan.order), ['over', 'base']);
    });

    test('an ORGANIZER folder carried out of the group detaches its MEMBERS, '
        'and carried within it does not', () {
      final stack = [
        _row('base'),
        _row('a1', attachedTo: 'base', folderId: 'ORG'),
        _row('ORG', kind: LayerKind.folder),
        _row('one'),
        _row('two'),
      ];
      final out = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('ORG'),
        insertAt: 5,
      )!;
      expect(out.attach.detachIds, {const LayerId('a1')});
      final within = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('ORG'),
        insertAt: 0,
      )!;
      expect(within.attach.detachIds, isEmpty);
      expect(_ids(within.order), ['a1', 'ORG', 'base', 'one', 'two']);
    });

    test('a BASE dragged away carries its group, so nothing detaches', () {
      final stack = [
        _row('base'),
        _row('over', attachedTo: 'base'),
        _row('one'),
      ];
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('base'),
        insertAt: 3,
      )!;
      expect(plan.attach.detachIds, isEmpty);
      expect(_ids(plan.order), ['one', 'base', 'over']);
    });
  });

  group('every slot at once', () {
    // A group with a rider on each side, and an ordinary row on each side of
    // it. Sweeping EVERY slot is the only way to see the answer table whole:
    // the P2b defect was an asymmetry that showed up in one direction only,
    // and hand-picked slots are how it survived.
    List<Layer> stack() => [
      _row('x'),
      _row('u', attachedTo: 'base', placement: AttachedPlacement.below),
      _row('base'),
      _row('o', attachedTo: 'base'),
      _row('y'),
    ];

    /// One letter per slot: `A`/`B` mount above/below, `a`/`b` a side change
    /// on a row that stays, `D` detach, `.` a plain move, `X` refused.
    String sweep(String movingId) {
      final out = StringBuffer();
      for (var slot = 0; slot <= stack().length; slot += 1) {
        final plan = resolveLayerDrop(
          stack: stack(),
          movingId: LayerId(movingId),
          insertAt: slot,
        );
        if (plan == null) {
          out.write('X');
          continue;
        }
        final mount = plan.attach.mount;
        final side = plan.attach.sideChange;
        if (mount != null) {
          out.write(mount.placement == AttachedPlacement.above ? 'A' : 'B');
        } else if (plan.attach.detachIds.isNotEmpty) {
          out.write('D');
        } else if (side != null) {
          out.write(side.placement == AttachedPlacement.above ? 'a' : 'b');
        } else {
          out.write('.');
        }
      }
      return out.toString();
    }

    test('a plain row mounts only in the two INNER slots, and never lands '
        'on its own two gaps', () {
      // slots:      0    1    2    3    4    5
      // rows:     x    u    base o    y
      //
      // ④: a row owns the gap above it AND the gap below it, and neither is
      // a landing — the X pair in each sweep is the moving row itself. It
      // used to read '.' there: a plan whose order was the order it started
      // with, which is what drew a caret the instant a drag began.
      expect(sweep('y'), '..BAXX');
      expect(sweep('x'), 'XXBA..');
    });

    test('an attach row stays while it touches the group, and says which '
        'side it is on', () {
      // 'o' rides ABOVE. The group's run starts at 'u', so slot 1 is the
      // group's bottom EDGE — an attach row keeps its base there and simply
      // changes sides; only slots 0 and 5 are clear of the group.
      expect(sweep('o'), 'DbbXXD');
      // 'u' rides BELOW and its own gaps are slots 1/2 — crossing the base
      // makes it an above row.
      expect(sweep('u'), 'DXXaaD');
    });

    test('a row that cannot ride anything is refused in the inner slots, '
        'never silently split', () {
      final withFolder = [...stack(), _row('F', kind: LayerKind.folder)];
      final answers = [
        for (var slot = 0; slot <= withFolder.length; slot += 1)
          resolveLayerDrop(
            stack: withFolder,
            movingId: const LayerId('F'),
            insertAt: slot,
          ) == null
              ? 'X'
              : '.',
      ].join();
      // The folder sits LAST, so its own two gaps are the final pair — X for
      // the same reason as above (④), not because a folder is refused there.
      expect(answers, '..XX.XX');
    });
  });

  group('the MENU detach\'s landing', () {
    test('is nothing when the row is already the outermost on its side', () {
      final stack = [
        _row('base'),
        _row('a1', attachedTo: 'base'),
        _row('a2', attachedTo: 'base'),
      ];
      expect(detachLandingIndex(stack, const LayerId('a2')), isNull);
      // a1 is buried INSIDE the run: leaving it there would cut the group.
      expect(detachLandingIndex(stack, const LayerId('a1')), 3);
    });

    test('is the group\'s edge on the row\'s own side', () {
      final stack = [
        _row('under', attachedTo: 'base', placement: AttachedPlacement.below),
        _row('base'),
        _row('a1', attachedTo: 'base'),
      ];
      expect(detachLandingIndex(stack, const LayerId('under')), isNull);
      final buried = [
        _row('u2', attachedTo: 'base', placement: AttachedPlacement.below),
        _row('u1', attachedTo: 'base', placement: AttachedPlacement.below),
        _row('base'),
      ];
      expect(detachLandingIndex(buried, const LayerId('u1')), 0);
    });

    test('always moves a row out of a 공정 ORGANIZER, even the outermost one '
        '— the folder\'s purity is the second reason to step', () {
      final stack = [
        _row('base'),
        _row('a1', attachedTo: 'base', folderId: 'ORG'),
        _row('ORG', kind: LayerKind.folder),
      ];
      expect(detachLandingIndex(stack, const LayerId('a1')), 3);
    });

    test('is nothing for a row that rides nothing, or whose base is gone', () {
      final stack = [_row('a'), _row('b', attachedTo: 'gone')];
      expect(detachLandingIndex(stack, const LayerId('a')), isNull);
      expect(detachLandingIndex(stack, const LayerId('b')), isNull);
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

  // R5 #15. A caret lives BETWEEN rows, and two intents have no gap to
  // live in: the inside of a folder with no members, and the first rider
  // on a base with no group. Both are "put the thing ON the thing", and
  // what the target IS decides which answer you get.
  group('dropping ON a row', () {
    Layer folder(String id, {String? parent}) =>
        createFolderLayer(id: LayerId(id), name: id).copyWith(
          folderId: parent == null ? null : LayerId(parent),
        );

    test('an EMPTY folder can be filled — the case a gap cannot reach', () {
      final stack = [_row('a'), _row('b'), folder('f')];
      final plan = resolveLayerDropOnRow(
        stack: stack,
        movingId: const LayerId('a'),
        targetId: const LayerId('f'),
      );

      expect(plan, isNotNull);
      expect(plan!.joinedFolderId, const LayerId('f'));
      expect(plan.folderIds, {const LayerId('a'): const LayerId('f')});
      // The folder invariant survives: members first, folder directly above.
      expect(_ids(plan.order), ['b', 'a', 'f']);
    });

    test('a folder with members takes the new row at the TOP of them', () {
      final stack = [
        _row('a'),
        _row('m', folderId: 'f'),
        folder('f'),
        _row('z'),
      ];
      final plan = resolveLayerDropOnRow(
        stack: stack,
        movingId: const LayerId('z'),
        targetId: const LayerId('f'),
      );

      expect(plan, isNotNull);
      expect(_ids(plan!.order), ['a', 'm', 'z', 'f']);
      expect(plan.folderIds, {const LayerId('z'): const LayerId('f')});
    });

    test('a folder dropped on ITS OWN member is refused — that is a cycle, '
        'and the run carries the member anyway', () {
      final stack = [_row('m', folderId: 'f'), folder('f'), _row('z')];
      expect(
        resolveLayerDropOnRow(
          stack: stack,
          movingId: const LayerId('f'),
          targetId: const LayerId('m'),
        ),
        isNull,
      );
      expect(
        resolveLayerDropOnRow(
          stack: stack,
          movingId: const LayerId('f'),
          targetId: const LayerId('f'),
        ),
        isNull,
      );
    });

    test('a DRAWING row takes the dropped row as its first rider, above it',
        () {
      final stack = [_row('base'), _row('rider')];
      final plan = resolveLayerDropOnRow(
        stack: stack,
        movingId: const LayerId('rider'),
        targetId: const LayerId('base'),
      );

      expect(plan, isNotNull);
      expect(plan!.attach.mount?.layerId, const LayerId('rider'));
      expect(plan.attach.mount?.baseId, const LayerId('base'));
      expect(plan.attach.mount?.placement, AttachedPlacement.above);
      expect(_ids(plan.order), ['base', 'rider']);
    });

    test('the mount rules still apply — a row that carries riders of its own '
        'cannot become one', () {
      final stack = [
        _row('base'),
        _row('carrier'),
        _row('its-rider', attachedTo: 'carrier'),
      ];
      expect(
        resolveLayerDropOnRow(
          stack: stack,
          movingId: const LayerId('carrier'),
          targetId: const LayerId('base'),
        ),
        isNull,
        reason: 'attach does not nest, and the group is unsplittable',
      );
    });

    test('a folder cannot be mounted on a drawing row', () {
      final stack = [_row('base'), _row('m', folderId: 'f'), folder('f')];
      expect(
        resolveLayerDropOnRow(
          stack: stack,
          movingId: const LayerId('f'),
          targetId: const LayerId('base'),
        ),
        isNull,
      );
    });

    test('a nested EMPTY folder is reachable too', () {
      final stack = [
        _row('a'),
        folder('inner', parent: 'outer'),
        folder('outer'),
      ];
      final plan = resolveLayerDropOnRow(
        stack: stack,
        movingId: const LayerId('a'),
        targetId: const LayerId('inner'),
      );

      expect(plan, isNotNull);
      expect(plan!.folderIds, {const LayerId('a'): const LayerId('inner')});
      expect(_ids(plan.order), ['a', 'inner', 'outer']);
    });
  });
}
