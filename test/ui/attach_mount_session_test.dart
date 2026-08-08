import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject;

/// P3's MENU door: mounting onto the row next door, and 어태치 해제, which
/// has to leave the group's run and the 공정 folder behind it.

EditorSessionManager _session() =>
    EditorSessionManager(initialProject: createDefaultProject());

List<Layer> _rows(EditorSessionManager s) => s.requireActiveCut.layers;

/// One whole drag, landing [id] at model index [insertAt].
///
/// R5 #5 retired the step verbs, so the drag is how a row moves at all now.
/// Handing the MODEL order over as the display list makes the slot the
/// model insertion index, which is the term these tests already use.
void _dragTo(EditorSessionManager s, LayerId id, int insertAt) {
  s.beginLayerRowDrag(LayerRowSubject(id));
  s.updateLayerRowDrag(s.layers, insertAt);
  s.endLayerRowDrag();
}

Layer _row(EditorSessionManager s, LayerId id) =>
    _rows(s).firstWhere((layer) => layer.id == id);

/// The animation rows only — the default project also carries instruction and
/// camera fixtures, which live in their own sections.
List<String> _animationOrder(EditorSessionManager s) => [
  for (final layer in _rows(s))
    if (layer.kind == LayerKind.animation) layer.id.value,
];

void main() {
  test('the menu mounts the active row on the neighbour the drag cannot '
      'reach — a base with no attach rows yet', () {
    final s = _session();
    final base = s.activeLayer!;
    s.createDrawingAtCurrentFrame();
    s.addLayerOfKind(LayerKind.animation);
    final row = s.activeLayer!;
    expect(
      _rows(s).indexWhere((layer) => layer.id == row.id),
      _rows(s).indexWhere((layer) => layer.id == base.id) + 1,
      reason: 'the new row lands directly above the base',
    );

    // Nothing rides the base yet, so no slot is "inside" it: the drag has
    // no way to make this attach, and this is the door that does.
    expect(s.attachNeighbourForActiveLayer(above: false)?.id, base.id);
    expect(s.attachNeighbourForActiveLayer(above: true), isNull);

    s.attachActiveLayerToNeighbour(above: false);

    final mounted = _row(s, row.id);
    expect(mounted.attachedToLayerId, base.id);
    // The base is below, so the row draws ABOVE it.
    expect(mounted.attachedPlacement, AttachedPlacement.above);
    // The base has a cel and the row has none: their shapes disagree, so the
    // mount is FREE and the row keeps authoring its own timing.
    expect(mounted.attachedMode, AttachedMode.free);
    expect(folderStructureProblem(_rows(s)), isNull);

    s.undo();
    expect(_row(s, row.id).attachedToLayerId, isNull);
  });

  test('an attach row is not offered as a base, and neither is a folder', () {
    final s = _session();
    s.createDrawingAtCurrentFrame();
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;
    s.addLayerOfKind(LayerKind.animation);

    // The row directly below the new layer is the ATTACH row: attaches do
    // not nest, so no offer.
    expect(
      _rows(s)[_rows(s).indexWhere((l) => l.id == s.activeLayer!.id) - 1].id,
      attachId,
    );
    expect(s.attachNeighbourForActiveLayer(above: false), isNull);
  });

  test('어태치 해제 bakes the timing, and STEPS OUT of the group so the run '
      'stays whole', () {
    final s = _session();
    final base = s.activeLayer!;
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(0);
    s.addAttachedLayer(AttachedPlacement.above);
    final firstId = s.activeLayer!.id;
    // A second attach row above it, so the first one is BURIED in the run.
    s.addAttachedLayer(AttachedPlacement.above);
    final secondId = s.activeLayer!.id;
    s.selectLayer(firstId);

    expect(s.canDetachActiveLayer, isTrue);
    final displayed = s.layers.firstWhere((layer) => layer.id == firstId);
    final shownBlocks = [
      for (final entry in displayed.timeline.entries)
        if (!entry.value.ghost)
          (entry.key, entry.value.length!, entry.value.frameId!.value),
    ];
    expect(shownBlocks, hasLength(2), reason: 'it mirrors the base\'s two cels');

    s.detachActiveLayer();

    final detached = _row(s, firstId);
    expect(detached.attachedToLayerId, isNull);
    expect(detached.baseFrameLinks, isEmpty);
    // The timing it was showing is now its own.
    expect(
      [
        for (final entry in detached.timeline.entries)
          if (!entry.value.ghost)
            (entry.key, entry.value.length!, entry.value.frameId!.value),
      ],
      shownBlocks,
    );
    // It stepped past the group, so the group's run is still contiguous —
    // the remaining attach row sits directly above its base.
    final rows = _rows(s);
    final baseIndex = rows.indexWhere((layer) => layer.id == base.id);
    expect(rows[baseIndex + 1].id, secondId);
    expect(
      attachedGroupEndIndex(base.id, rows),
      baseIndex + 2,
      reason: 'the detached row is outside the span',
    );
    expect(folderStructureProblem(rows), isNull);

    s.undo();
    final back = _row(s, firstId);
    expect(back.attachedToLayerId, base.id);
    expect(back.timeline, isEmpty);
    expect(back.baseFrameLinks, hasLength(2));
  });

  test('어태치 해제 leaves the 공정 ORGANIZER folder too — its purity is what '
      'keeps the fx lanes off the group', () {
    final s = _session();
    s.createDrawingAtCurrentFrame();
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;
    s.groupActiveAttachIntoFolder();
    final organizerId = _rows(s)
        .firstWhere((layer) => layer.kind == LayerKind.folder)
        .id;
    s.selectLayer(attachId);
    expect(_row(s, attachId).folderId, organizerId);
    expect(
      attachOrganizerBaseOf(_row(s, organizerId), _rows(s)),
      isNotNull,
      reason: 'the fixture is a real organizer',
    );

    s.detachActiveLayer();

    expect(_row(s, attachId).attachedToLayerId, isNull);
    expect(_row(s, attachId).folderId, isNot(organizerId));
    // THE oracle: a detached row left inside the organizer would have made
    // the folder mix an ordinary row in with attaches.
    expect(folderStructureProblem(_rows(s)), isNull);
  });

  test('crossing the base changes the row\'s SIDE, so its arrow keeps '
      'telling the truth', () {
    final s = _session();
    final base = s.activeLayer!;
    s.createDrawingAtCurrentFrame();
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;
    final before = _row(s, attachId);
    expect(before.attachedPlacement, AttachedPlacement.above);
    expect(before.attachedMode, AttachedMode.synced);
    expect(before.baseFrameLinks, hasLength(1));

    // Dragging it below the base takes it past the base's picture.
    _dragTo(s, attachId, _rows(s).indexWhere((row) => row.id == base.id));

    final rows = _rows(s);
    expect(
      rows.indexWhere((layer) => layer.id == attachId),
      lessThan(rows.indexWhere((layer) => layer.id == base.id)),
    );
    final after = _row(s, attachId);
    expect(after.attachedToLayerId, base.id);
    expect(after.attachedPlacement, AttachedPlacement.below);
    expect(attachArrowPlacement(after, rows), AttachedPlacement.below);
    // A re-order is NOT a re-mount: the timing contract, the links and the
    // stored timeline are untouched, so nothing about the picture moves.
    expect(after.attachedMode, before.attachedMode);
    expect(after.baseFrameLinks, before.baseFrameLinks);
    expect(after.timeline, before.timeline);

    s.undo();
    expect(_row(s, attachId).attachedPlacement, AttachedPlacement.above);
  });

  test('a DROP that lands inside a group mounts — one policy, one verb '
      'now', () {
    final s = _session();
    final base = s.activeLayer!;
    s.addAttachedLayer(AttachedPlacement.above);
    s.addLayerOfKind(LayerKind.animation);
    final loose = s.activeLayer!.id;
    // Stack: base, attach, loose. One step DOWN puts it between them.
    expect(_animationOrder(s).last, loose.value);

    _dragTo(s, loose, _rows(s).indexWhere((row) => row.id == base.id) + 1);

    expect(_row(s, loose).attachedToLayerId, base.id);
    expect(_row(s, loose).attachedMode, AttachedMode.synced);

    s.undo();
    expect(_row(s, loose).attachedToLayerId, isNull);
    expect(_animationOrder(s).last, loose.value);
  });
}
