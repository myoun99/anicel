import 'package:collection/collection.dart' show IterableExtension;

import '../../services/editing/layer_standing_after_change.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/conte/conte_ink_keys.dart' show conteInkRowKey;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/new_row_placement.dart';
import '../../services/commands/link_mirror.dart' show linkedCutSiblings;
import '../../services/commands/track_se_layer_commands.dart';
import '../../services/project_lookup.dart'
    show cutWritingRow, projectLayersAnywhere;
import 'active_cut_controllers.dart';
import 'independent_clip_mint.dart'
    show carryBakedPictures, carryConteHandwriting;
import 'render_caches.dart';
import 'row_selection.dart';
import 'session_roles.dart';
import '../text/place_lines.dart' show linkPartnerLines;

/// The LAYER VERBS — deleting, duplicating, linking and unlinking,
/// renaming and copying a layer, and adding a row above the active one —
/// as their own object. Each is a command over the repository; the
/// session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own and sixteen
/// session members touched; the rest reads it in three places. It names
/// the roles it needs in its constructor.
class LayerVerbs {
  LayerVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required RenderCaches renderCaches,
    required RowSelection rowSelection,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _renderCaches = renderCaches,
       _rowSelection = rowSelection;

  final ProjectAccess _project;
  final SelectionAccess _selection;

  /// The rows a verb on the selection acts on
  /// ([RowSelection.selectedLayerIds]).
  final RowSelection _rowSelection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;

  /// Where a duplicate's pictures are.
  final RenderCaches _renderCaches;

  /// The selected rows that name a LAYER this cut may delete (⑨).
  ///
  /// A row's kind decides what the edit DOES, never whether the row could
  /// be selected (뿌리 A) — so lane rows, track rows and the floors' fixed
  /// rows simply contribute nothing here instead of being kept out of the
  /// selection. An fx header row's effect is the delete's other half
  /// (F-476, `EditorSessionManager.effectsToDeleteOfRows`).
  ///
  /// A row another selected row takes along ([rowsHeldBy]) is that row's:
  /// the one that holds it alone is deleted, and takes it along — a folder
  /// what it holds (F-305, 유저 2026-10-06: 「폴더/내용물 선택하고 삭제하는건
  /// 알아서 폴더만 삭제되도록 하는게 로직적으로 깔끔」), a base its attach
  /// rows (F-464, 유저 2026-10-25: 「법 다른거같으니 통일하면서 해결」).
  ///
  /// ↩️Only a folder's rows were left out until F-464. A base selected with
  /// its attach rows BELOW it went first (the delete walks top down), took
  /// them along, and the next delete asked for a row already gone: the
  /// throw skipped the refresh and lost the undo step — 「삭제해도
  /// 반응없음. 다른 레이어 이동하니까 삭제되있음」. Above it they went first,
  /// one by one, which is why that side worked.
  List<LayerId> deletableSelectedLayerIds() {
    final ids = selectedLayerIdsWhere(canDeleteLayer);
    final takenAlong = _takenAlongBy(ids);
    return [
      for (final id in ids)
        if (!takenAlong.contains(id)) id,
    ];
  }

  /// What a delete of [ids] takes BESIDES them, as the rail lists them —
  /// top first: every row a folder among them holds (F-305: 「내용물도
  /// 삭제리스트에 보여지게」), and the attach rows and organizer folders that
  /// go with a base (the coordinator's cascade — 「neither can stand
  /// alone」). A row named by [ids] itself is not repeated.
  ///
  /// ↩️A base's attach rows were left out until F-303: the window listed
  /// only what a FOLDER held, so a base went and took rows the list never
  /// showed — and the hand-off stood on one of them ([_standAfterDeleting]).
  List<Layer> rowsHeldBy(Iterable<LayerId> ids) {
    final named = ids.toSet();
    final takenAlong = _takenAlongBy(named);
    return [
      for (final row in _project.layers.reversed)
        if (!named.contains(row.id) && takenAlong.contains(row.id)) row,
    ];
  }

  /// The rows a delete of [ids] takes along, each by ANOTHER row that goes —
  /// one of [ids] too, when another of them takes it: what a folder among
  /// them holds, and the attach rows and organizer folders of a base that
  /// goes.
  Set<LayerId> _takenAlongBy(Iterable<LayerId> ids) {
    final named = ids.toSet();
    final rows = _project.layers;
    final inAFolderThatGoes = {
      for (final row in rows)
        if (named.any((id) => rows.isInsideFolder(row.folderId, id))) row.id,
    };
    final going = {...named, ...inAFolderThatGoes};
    return {
      ...inAFolderThatGoes,
      for (final row in rows)
        if (going.contains(
          row.attachedToLayerId ?? attachOrganizerBaseOf(row, rows),
        ))
          row.id,
    };
  }

  /// Whether a delete of [layer] takes it ALONE: it may go, and nothing goes
  /// with it ([rowsHeldBy]) — what a 잘라내기 may lift, its board holding the
  /// row and nothing besides (I-123: a base's attach rows are no copy's).
  bool deletesAlone(Layer layer) =>
      canDeleteLayer(layer) && rowsHeldBy([layer.id]).isEmpty;

  /// The selected rows that may be DUPLICATED (⑨'s 복사).
  ///
  /// The stand-downs are [duplicateActiveLayer]'s, read off the same
  /// predicate rather than restated ([layerTakesACopyBesideIt]): a
  /// track-owned SE row has no clipboard shape, a per-cut singleton cannot
  /// have a second, and an attach row's copy would double-link its base's
  /// cels.
  List<LayerId> duplicatableSelectedLayerIds() =>
      selectedLayerIdsWhere(layerTakesACopyBesideIt);

  /// The selected rows whose NAME may be edited (⑨).
  ///
  /// A track's fixture row is the exception ([LayerKind.isTrackFixture]),
  /// and it is the one [canDeleteLayer] refuses for the same reason: it has
  /// no row verbs of its own on any surface.
  List<LayerId> renameableSelectedLayerIds() =>
      selectedLayerIdsWhere(_nameIsEditable);

  /// Of [ids] — the layers a press acted on
  /// ([RowSelection.layersActedOnBy]) — the ones whose NAME may be edited,
  /// by [renameableSelectedLayerIds]'s rule (I-48's double click), wherever
  /// [renameRows] can write it ([_cutWriting]): a storyboard projection
  /// row's lands in any cut (F-322: 「더블클릭으로 레이어 이름바꾸는거 …
  /// 통일」). ↩️Only the active cut's rows were looked at.
  List<LayerId> renameableOf(Iterable<LayerId> ids) => _layerIdsWhere(
    [
      for (final id in ids)
        if (_cutWriting(id) != null) id,
    ],
    _nameIsEditable,
    among: projectLayersAnywhere(_project.repository.requireProject()),
  );

  static bool _nameIsEditable(Layer layer) => !layer.kind.isTrackFixture;

  /// The selected LAYER rows whose layer passes [keep], in selection order,
  /// once each — the one walk behind [deletableSelectedLayerIds] and
  /// [renameableSelectedLayerIds] (the audit's clone scan, 2026-09-03).
  ///
  /// Public for the one asker outside this object: 자동 이름 지정's ROWS
  /// rung (I-18, `BlockNaming`), which names its own predicate rather than
  /// walking the selection a second time.
  List<LayerId> selectedLayerIdsWhere(bool Function(Layer layer) keep) =>
      _layerIdsWhere(_rowSelection.selectedLayerIds, keep);

  /// Of [ids], the layers of the cut — or [among] — that pass [keep], in
  /// order, once each.
  List<LayerId> _layerIdsWhere(
    Iterable<LayerId> ids,
    bool Function(Layer layer) keep, {
    Iterable<Layer>? among,
  }) {
    final byId = {
      for (final layer in among ?? _project.layers) layer.id: layer,
    };
    final kept = <LayerId>[];
    for (final id in ids) {
      final layer = byId[id];
      if (layer != null && !kept.contains(id) && keep(layer)) {
        kept.add(id);
      }
    }
    return kept;
  }

  bool get canDeleteActiveLayer {
    final activeLayer = _selection.activeLayer;
    return activeLayer != null && canDeleteLayer(activeLayer);
  }

  /// Whether [activeLayer] may be deleted at all — the FLOORS, asked of any
  /// row rather than only of the active one (⑨ needs it per selected row).
  ///
  /// The parameter keeps its name so the body below reads unchanged: this
  /// was [canDeleteActiveLayer]'s own text, lifted so two askers cannot
  /// drift apart ([[predicates-before-new-kind]]).
  bool canDeleteLayer(Layer activeLayer) {
    // A track's fixture (the transition row) goes with its track, from no
    // surface on its own — its SPANS are what a delete there removes.
    if (activeLayer.kind.isTrackFixture) {
      return false;
    }
    // Attach rows are accessories: always deletable, never counted toward
    // the drawing floor (deleting a BASE cascades over its attach rows).
    if (isAttachedLayer(activeLayer)) {
      return true;
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    final layers = cut.layers;
    return switch (activeLayer.kind) {
      LayerKind.camera => false,
      // The TRANSITION row is a track fixture like the camera: exactly one,
      // never deleted from inside a cut.
      LayerKind.transition => false,
      // The sheet's fixture floors: at least two SE rows (S1·S2, now
      // track-owned) and one instruction row survive.
      LayerKind.se => _selection.activeTrack.seLayers.length > 2,
      LayerKind.instruction =>
        layers.where((layer) => layer.kind == LayerKind.instruction).length > 1,
      // R28 #14: NO drawing floor. The action section may stand empty —
      // the last action layer is deletable ("액션 레이어가 1개도 없는상황
      // 허용"). The global track is the thing that has to exist, not any
      // particular row inside a cut, and every drawing path already
      // handles "no editable cel" (that is the R26 #35 refusal notice).
      // A folder row goes WITH what it holds (F-305, the coordinator
      // routes it) — ↩️it used to dissolve, its members surviving.
      // An ADJUSTMENT row has no floor either: deleting it just stops the
      // stack below being filtered.
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.image ||
      LayerKind.folder ||
      LayerKind.adjustment => true,
    };
  }

  /// ⑨'s row verbs, ONE undo step over [ids] in the active cut: [command]
  /// per row, then the refresh — standing on the row the last [command]
  /// answered with, or on the first of [ids] when none answers.
  ///
  /// ★Written once when the THIRD verb of this shape arrived (the link-
  /// independent button, I-45): duplicate, rename and unlink each spelled
  /// it out, and the clone ratchet named the pair the third one made.
  void _eachRowAsOneStep(
    List<LayerId> ids,
    String description,
    LayerId? Function(CutId cutId, LayerId layerId) command,
  ) {
    final rows = [
      for (final layerId in ids)
        if (_cutWriting(layerId) case final cutId?)
          (cutId: cutId, layerId: layerId),
    ];
    if (rows.isEmpty) {
      return;
    }
    LayerId? stand;
    _project.historyManager.runAsOneStep(description, () {
      for (final row in rows) {
        stand = command(row.cutId, row.layerId) ?? stand;
      }
    });
    _changes.refreshAfterCutCommand(preferredActiveLayerId: stand ?? ids.first);
    _changes.notifyChanged();
  }

  /// The cut a row verb writes [layerId] in ([cutWritingRow]): the one
  /// HOLDING it, the active one for a track's own row.
  CutId? _cutWriting(LayerId layerId) => cutWritingRow(
    _project.repository.requireProject(),
    layerId,
    standing: _project.activeCutId,
  );

  /// ⑨: every selected row duplicated, in ONE undo — the rename's twin —
  /// as ONE block over the topmost of them, in the order they stand,
  /// standing on the top copy.
  ///
  /// 🗣️F-455 (유저 2026-10-23): 「레이어는 지금 여러개 복제시 각자 선택한
  /// 레이어의 위에 생기는데, 그게아니라 선택한 레이어들 포함해서 그 위에
  /// 생기도록. 사이사이에 생기지 않게」 — a paste's block ([seatAboveRow]),
  /// each copy over the one before it. ↩️Each copy went right above its own
  /// source, in the order the rows were picked.
  void duplicateSelectedLayers() {
    final ids = duplicatableSelectedLayerIds().toSet();
    final stack = [
      for (final layer in _project.activeCutOrNull?.layers ?? const <Layer>[])
        if (ids.contains(layer.id)) layer.id,
    ];
    if (stack.isEmpty) {
      return;
    }
    var over = stack.last;
    _eachRowAsOneStep(
      stack,
      'Duplicate rows',
      (cutId, layerId) => over = _duplicate(cutId, layerId, over: over),
    );
  }

  /// Duplicates [layerId] in [cutId] — right above it, or over the row
  /// [over] names — and brings its pictures over: the copy mints every cel
  /// afresh, and a picture lives under its cel's id (F-62's law at the
  /// layer's scale). ↩️Nothing did until 2026-09-26 — a duplicated row came
  /// out with no drawing at all (measured; card
  /// `duplicates-lose-their-pictures`).
  LayerId _duplicate(CutId cutId, LayerId layerId, {LayerId? over}) {
    final copy = _project.cutCommandCoordinator.duplicateLayer(
      cutId: cutId,
      sourceLayerId: layerId,
      insertionIndex: over == null
          ? null
          : seatAboveRow(_project.requireActiveCut.layers, over),
    );
    final cut = _project.requireActiveCut;
    final store = _renderCaches.brushFrameStore;
    carryBakedPictures(
      project: _project,
      store: store,
      cut: cut,
      to: copy.layerId,
      minted: copy.minted,
      pictureOf: (source) => store.bakedSurfaceOrNull(
        _project.brushFrameKeyForCut(cut, layerId, source),
      ),
    );
    final ink = _renderCaches.conteInkRowStore;
    carryConteHandwriting(
      store: ink,
      cut: cut.id,
      copies: copy.handwriting,
      handwritingOf: (inkId) =>
          ink.bakedSurfaceOrNull(conteInkRowKey(cut.id, inkId)),
    );
    return copy.layerId;
  }

  /// Whether [duplicateActiveLayer] has a row to copy — its gate, asked the
  /// way the verb asks: the selected rows, else the row you stand on.
  bool get canDuplicateActiveLayer =>
      duplicatableSelectedLayerIds().isNotEmpty ||
      _activeLayerTakesACopy;

  /// Track-owned SE rows: duplication stands down (same clipboard-shape
  /// reason as the board's copy); attach rows too (v1 — a duplicate would
  /// double-link the same base cels); and R9 #7: the copy lands in the
  /// same cut — always the second one.
  bool get _activeLayerTakesACopy {
    final activeLayer = _selection.activeLayer;
    return activeLayer != null && layerTakesACopyBesideIt(activeLayer);
  }

  /// ⑰'s law, applied to 복사: the verb asks WHAT IS SELECTED first and
  /// falls back to the row you are standing on. Every caller — the pill
  /// button, a shortcut — inherits that without asking twice.
  void duplicateActiveLayer() {
    if (duplicatableSelectedLayerIds().isNotEmpty) {
      duplicateSelectedLayers();
      return;
    }
    if (!_activeLayerTakesACopy) {
      return;
    }
    final activeLayer = _selection.activeLayer!;

    final duplicatedLayerId = _duplicate(
      // A non-null active layer implies an active cut (gap state has no
      // rows at all).
      _project.requireActiveCut.id,
      activeLayer.id,
    );
    _changes.refreshAfterCutCommand(preferredActiveLayerId: duplicatedLayerId);
    _changes.notifyChanged();
  }

  /// Whether the layer is a member of a link group in the ACTIVE cut
  /// (drives the link badge on its label).
  bool isLayerLinked(LayerId layerId) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return _project.repository.requireProject().linkRegistry.isLinked(
      cutId: cut.id,
      layerId: layerId,
    );
  }

  /// The rows the layer shares its pictures with, in the ACTIVE cut
  /// ([linkPartnerLines]) — what the link badge names. Empty when it is not
  /// linked.
  List<String> linkPartnersOf(LayerId layerId) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return linkPartnerLines(
      _project.repository.requireProject(),
      cutId: cut.id,
      layerId: layerId,
    );
  }

  // ↩️「링크 복제」 of the ACTIVE row stood here (`linkDuplicateActiveLayer`),
  // behind the layer menu's 「링크해서 복제」. 🗣️I-77 (유저 2026-10-06):
  // 「링크해서 복제도 필요없어지니 삭제」 — the shared pill's copy and its
  // linked paste make that copy now, of every selected row
  // (`LayerClipboard.pasteRowsLinked`).

  /// Whether [layer]'s attach group shares its pictures through a link —
  /// the one question 독립시키기 answers, from the layer menu and from the
  /// shared pill alike.
  ///
  /// The verb unlinks the WHOLE attach group, so it is offered when ANY
  /// member is linked (mirrors the coordinator's own guard).
  bool groupIsLinked(Layer layer, Cut cut) {
    final baseId = attachBaseIdOf(layer);
    final registry = _project.repository.requireProject().linkRegistry;
    return cut.layers.any(
      (member) =>
          (member.id == baseId || member.attachedToLayerId == baseId) &&
          registry.isLinked(cutId: cut.id, layerId: member.id),
    );
  }

  /// The selected rows whose attach group is linked — the ROWS rung of the
  /// shared pill's link-independent button (I-45).
  List<LayerId> linkedSelectedLayerIds() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return selectedLayerIdsWhere((layer) => groupIsLinked(layer, cut));
  }

  /// 독립시키기 for every selected linked row, as ONE undo step.
  void unlinkSelectedLayers() => unlinkLayers(linkedSelectedLayerIds());

  /// 독립시키기 for each of [layerIds] whose group is linked, as ONE undo
  /// step. Two rows of one attach group unlink once: the second finds its
  /// group already forked, and the coordinator's own guard makes it a no-op.
  ///
  /// The link window's button (I-25) presses this with the rows a press acts
  /// on (`RowSelection.rowsActedOnBy`), the pill with the selection.
  void unlinkLayers(Iterable<LayerId> layerIds) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    _eachRowAsOneStep(
      [
        for (final id in layerIds)
          if (cut.layers.firstWhereOrNull((layer) => layer.id == id)
              case final layer? when groupIsLinked(layer, cut))
            id,
      ],
      'Unlink rows',
      (cutId, layerId) {
        _project.cutCommandCoordinator.unlinkLayer(
          cutId: cutId,
          layerId: layerId,
        );
        return null;
      },
    );
  }

  /// Whether the ACTIVE cut is a linked cut (겸용 — its linked rows all have
  /// counterparts in another cut, [linkedCutSiblings]): its rows then share
  /// their pictures as the cut does, and one row cannot leave alone.
  ///
  /// 🗣️I-25 (유저 2026-09-14): 「레이어도 똑같이 버튼누르면 링크 대상 리스트
  /// 표시. 여기서 링크컷일경우엔 링크해제버튼 비활성화하고 툴팁으로 링크컷이기
  /// 때문에 불가능하다고 띄움. 링크컷아니면 해제해도 되니까 해제버튼 활성화」.
  bool get activeCutIsLinkedCut {
    final cut = _project.activeCutOrNull;
    return cut != null &&
        linkedCutSiblings(
          _project.repository.requireProject(),
          cutId: cut.id,
        ).isNotEmpty;
  }

  /// Where to stand once [ids] — top first, as they are deleted — are gone
  /// with what they hold: [stableLayerIdAfterDeleting]'s hand-off from the
  /// LOWEST of them, over the rows that stay.
  ///
  /// ↩️The hand-off was made over the whole stack, as if that one row were
  /// all that went. A folder takes its rows along now (F-305), and the row
  /// next to it in the stack is one of them.
  LayerId? _standAfterDeleting(List<LayerId> ids) {
    final from = ids.last;
    final gone = {...ids, for (final row in rowsHeldBy(ids)) row.id}
      ..remove(from);
    return stableLayerIdAfterDeleting(
      beforeLayers: [
        for (final layer in _project.requireActiveCut.layers)
          if (!gone.contains(layer.id)) layer,
      ],
      deletedLayerId: from,
    );
  }

  /// One row's delete, where the row lives: an S row off its TRACK — while
  /// the track keeps more than its floor of two, asked again at each one so
  /// a multi-row delete stops there — any other row in [cutId], whose
  /// floors the coordinator asks ([CutCommandCoordinator.deleteLayer]).
  ///
  /// 🗣️F-359 (유저 2026-10-14): 「s행은 삭제창통해 삭제해도 삭제가안됨」.
  /// ↩️Only the active row's delete took an S row off its track; the
  /// selection's — the one the delete window commits — handed it to the
  /// cut's, which holds no S row and refused it.
  void _deleteRow(CutId cutId, LayerId layerId) {
    final track = _selection.activeTrack;
    if (!track.seLayers.any((row) => row.id == layerId)) {
      _project.cutCommandCoordinator.deleteLayer(
        cutId: cutId,
        layerId: layerId,
      );
      return;
    }
    if (track.seLayers.length > 2) {
      _project.historyManager.execute(
        RemoveTrackSeLayerCommand(
          repository: _project.repository,
          trackId: _selection.selectedTrackId,
          layerId: layerId,
        ),
      );
    }
  }

  /// Deletes the active layer. Callers should confirm via dialog first and check
  /// [canDeleteActiveLayer]; this is a no-op when deletion is not allowed.
  void deleteActiveLayer() {
    final activeLayer = _selection.activeLayer;
    if (activeLayer == null || !canDeleteActiveLayer) {
      return;
    }

    if (activeLayer.kind == LayerKind.se) {
      final beforeSe = _selection.activeTrack.seLayers;
      final nextActiveLayerId = stableLayerIdAfterDeleting(
        beforeLayers: beforeSe,
        deletedLayerId: activeLayer.id,
      );
      _deleteRow(_project.requireActiveCut.id, activeLayer.id);
      _changes.refreshAfterCutCommand(
        preferredActiveLayerId: nextActiveLayerId,
        filterSparesStanding: false,
      );
      _changes.notifyChanged();
      return;
    }

    final nextActiveLayerId = _standAfterDeleting([activeLayer.id]);

    _project.cutCommandCoordinator.deleteLayer(
      cutId: _project.requireActiveCut.id,
      layerId: activeLayer.id,
    );
    // F-169: the row you stood on is gone and the walk picked this one — a
    // hand-off, which the filter's exemption must not put on the screen.
    _changes.refreshAfterCutCommand(
      preferredActiveLayerId: nextActiveLayerId,
      filterSparesStanding: false,
    );
    _changes.notifyChanged();
  }

  /// ⑨: deletes every selected row that names a deletable layer, as ONE
  /// undo step — the gesture selected them together, so it undoes together.
  void deleteSelectedLayers() =>
      deleteLayers(deletableSelectedLayerIds(), step: 'Delete rows');

  /// Deletes the rows [ids] name as ONE undo step called [step], and stands
  /// on the row the lowest of them hands off to — the selection's delete,
  /// and the 잘라내기 that lifts the rows its copy took (I-123,
  /// `LayerClipboard.cutSelectedRows`).
  ///
  /// Deleting from the TOP down keeps each removal's own bookkeeping (the
  /// stable next-active pick) reading the stack it was written against:
  /// taking a lower row out first would shift the ones above it under the
  /// loop's feet.
  ///
  /// No row named here is one another of them takes along — the selection's
  /// delete leaves those out ([deletableSelectedLayerIds]) and a 잘라내기
  /// lifts only rows that go alone ([deletesAlone]) — so no removal finds
  /// its row already gone. ↩️The order was thought to answer that too, for
  /// an attach cascade; it did only while the attach rows stood above their
  /// base (F-464).
  void deleteLayers(List<LayerId> ids, {required String step}) {
    if (ids.isEmpty) {
      return;
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final order = {
      for (var index = 0; index < cut.layers.length; index += 1)
        cut.layers[index].id: index,
    };
    final ordered = [...ids]
      ..sort((a, b) => (order[b] ?? -1).compareTo(order[a] ?? -1));
    final nextActiveLayerId = _standAfterDeleting(ordered);
    _project.historyManager.runAsOneStep(step, () {
      for (final layerId in ordered) {
        _deleteRow(cut.id, layerId);
      }
    });
    _selection.clearRowSelection();
    _changes.refreshAfterCutCommand(
      preferredActiveLayerId: nextActiveLayerId,
      filterSparesStanding: false,
    );
    _changes.notifyChanged();
  }

  void renameActiveLayer(String name) {
    final activeLayer = _selection.activeLayer;
    if (activeLayer == null) {
      return;
    }
    renameLayer(activeLayer.id, name);
  }

  /// ⑨: 「이름편집은 선택된 편집가능 레이어 전부를 같은 이름으로 일괄 변경」.
  ///
  /// One undo step, and the SAME name on every row — the user's words are
  /// "all of them to the same name", not "a numbered series", so nothing
  /// here invents suffixes.
  void renameSelectedLayers(String name) =>
      renameRows(renameableSelectedLayerIds(), name);

  /// [ids] renamed to [name] as ONE undo step — the selection's rename
  /// above, and I-48's double click, whose rows are the ones its first
  /// press acted on.
  void renameRows(List<LayerId> ids, String name) => _eachRowAsOneStep(
    ids,
    'Rename rows',
    (cutId, layerId) {
      _project.cutCommandCoordinator.renameLayer(
        cutId: cutId,
        layerId: layerId,
        name: name,
      );
      return null;
    },
  );

  /// Renames any row by id — folders included, because a folder is a row.
  void renameLayer(LayerId layerId, String name) {
    final cutId = _cutWriting(layerId);
    if (cutId == null) {
      return;
    }
    _project.cutCommandCoordinator.renameLayer(
      cutId: cutId,
      layerId: layerId,
      name: name,
    );
    _changes.refreshAfterCutCommand(preferredActiveLayerId: layerId);
    _changes.notifyChanged();
  }

  /// Inserts a NEW ROW the way one joins the stack above the active layer:
  /// aimed at the slot above it — inside it, where it is a folder — and
  /// placed by [newRowPlacement], the one answer every door that makes a
  /// row takes — Add Layer, a file let go on the canvas, a file let go
  /// between two rail rows. Its structural rules (an attach group is
  /// indivisible; a new row joins the folder of the row below it, or the
  /// folder stood on) are written there, with why.
  void addRowAboveActive(Layer Function(Cut cut) build) =>
      addRow(build, placementAboveActive);

  /// Where [addRowAboveActive] places a new row in [stack]
  /// ([newRowPlacementOn]).
  ({int index, LayerId? folderId}) placementAboveActive(List<Layer> stack) =>
      newRowPlacementOn(stack, _controllers.layerController.activeLayerId);

  /// Inserts a NEW ROW in the active cut where [placeIn] places it in the
  /// cut's stack — above the active layer ([placementAboveActive]), or at
  /// a cut's conte row's birthplace (`conteRowPlacement`, F-369).
  ///
  /// The new row is stood on — or, made inside the folder stood on, that
  /// folder still ([rowStoodOnAfterMaking]).
  void addRow(
    Layer Function(Cut cut) build,
    ({int index, LayerId? folderId}) Function(List<Layer> stack) placeIn,
  ) {
    final cut = _project.requireActiveCut;
    final standing = _controllers.layerController.activeLayerId;
    final placement = placeIn(cut.layers);
    final built = build(cut);
    _controllers.layerController.addLayer(
      layer: placement.folderId == null
          ? built
          : built.copyWith(folderId: placement.folderId),
      insertionIndex: placement.index,
    );
    _controllers.layerController.selectLayer(
      rowStoodOnAfterMaking(
        _project.requireActiveCut.layers,
        made: built.id,
        standing: standing,
      ),
    );
  }
}
