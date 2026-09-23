import '../../models/attached_layer_resolve.dart';
import '../../models/attached_mode.dart';
import '../../models/attached_layer_mount.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import '../timeline/layer_drop_policy.dart'
    show detachLandingIndex, resolveLayerDrop;
import '../text/app_strings.dart';
import '../widgets/cursor_notice.dart';
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'row_selection.dart';
import 'layer_id_mint.dart';
import 'session_roles.dart';

/// FOLDERS AND ATTACHMENTS — grouping the active layer or attach into a
/// folder, dissolving one, adding an attached layer, and the synced-attach
/// refusal — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads it in four places
/// (the block move and frame shift asking whether a row is a synced
/// attach).
class FoldersAndAttachments {
  FoldersAndAttachments({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required LayerIdMint layerIds,
    required ActiveCutEdits activeCut,
    required FoldHandOff handOffOnFold,
    required void Function({bool reveal}) keepStandingShown,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _layerIds = layerIds,
       _activeCut = activeCut,
       _handOffOnFold = handOffOnFold,
       _keepStandingShown = keepStandingShown;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final LayerIdMint _layerIds;
  final ActiveCutEdits _activeCut;
  final FoldHandOff _handOffOnFold;

  /// The standing law with its reveal — a new attach row is where you went
  /// (`Standing.keepStandingShown`).
  final void Function({bool reveal}) _keepStandingShown;

  /// Whether the active layer can carry (or already rides within) an
  /// attach group — the Add Attach Layer entrance's gate (W5).
  bool get canAddAttachedLayerToActive {
    final active = _selection.activeLayer;
    if (active == null) {
      return false;
    }
    if (isAttachedLayer(active)) {
      // Adding from an attach row targets ITS base (same group).
      return attachedBaseOf(active, _project.requireActiveCut.layers) != null;
    }
    return canCarryAttachedLayers(active);
  }

  /// Adds an ATTACH LAYER riding the active layer (or the active attach
  /// row's base): own cels/eye/opacity, the base's FX; [placement] picks
  /// above or below the base's picture. [mode] picks the timing contract
  /// (UI-R21 #3): synced = the W5 ghost mirror riding the base's
  /// exposures; free = authors its own timeline like a normal drawing
  /// layer. Selected on creation; excluded from the timesheet by default.
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) {
    if (!canAddAttachedLayerToActive) {
      return;
    }
    final active = _selection.activeLayer!;
    final cut = _project.requireActiveCut;
    final base = isAttachedLayer(active)
        ? attachedBaseOf(active, cut.layers)!
        : active;
    final layerId = _layerIds.mint();
    final baseIndex = cut.layers.indexWhere((layer) => layer.id == base.id);
    if (baseIndex == -1) {
      return;
    }
    // [below…, base, above…]: a new below goes bottommost (before the
    // existing belows and their organizer folders), a new above topmost
    // (past the group). The new row INHERITS the base's folderId — the
    // group shares the base's folder, and a null row inside a folder's
    // contiguous run would break the folder invariant.
    var insertionIndex = placement == AttachedPlacement.below
        ? attachedGroupStartIndex(base.id, cut.layers)
        : attachedGroupEndIndex(base.id, cut.layers);
    var folderId = base.folderId;
    // SIBLING rule: adding from an attach row that lives in an ORGANIZER
    // folder ([연출]/[작감]…) with the same placement joins that folder —
    // "add another part to this 공정" — landing right where the folder
    // row sits (which keeps the folder's member run contiguous).
    final activeOrganizer = cut.layers.folderById(active.folderId);
    if (activeOrganizer != null &&
        isAttachedLayer(active) &&
        active.attachedPlacement == placement &&
        attachOrganizerBaseOf(activeOrganizer, cut.layers) == base.id) {
      folderId = activeOrganizer.id;
      insertionIndex = cut.layers.indexWhere(
        (layer) => layer.id == activeOrganizer.id,
      );
    }
    // UI-R23 #7 v2: the row is added EMPTY — the repository's
    // always-mirror reconciliation fills one own cel + base link per base
    // cel in the same write (and keeps doing so live as the base gains
    // cels later), so every mirror cell is editable from the first frame.
    _controllers.layerController.addLayer(
      layer: Layer(
        id: layerId,
        name: nextAttachedLayerName(base, cut.layers, placement),
        frames: const [],
        timeline: const {},
        // An attach row exists to be DRAWN on (own cels riding the base's
        // FX) — a base kind that refuses the brush (text) must not pass
        // the refusal down. Mirrors the referenced-image behavior, where
        // the refusal lives in a non-inherited field and the attach row
        // is born drawable.
        kind: base.kind.acceptsBrushInput ? base.kind : LayerKind.animation,
        onTimesheet: false,
        attachedToLayerId: base.id,
        attachedPlacement: placement,
        attachedMode: mode,
        folderId: folderId,
        // F-133: made FROM the row you stand on, it starts with that row's
        // colour label — the door names its target ([LayerMark.inherited]).
        mark: active.mark.inherited,
      ),
      insertionIndex: insertionIndex,
    );
    // F-169 ②: made from a folded group's base, the new row opens its group.
    // ↩️It used to show that one row inside the shut group (the active attach
    // row's exemption, UI-R20 #9) — the exemption that also put a handed-off
    // row on the screen.
    _keepStandingShown(reveal: true);
    _changes.notifyChanged();
  }

  bool get canGroupActiveLayerIntoFolder =>
      _selection.activeLayer != null &&
      _selection.activeLayer!.kind == LayerKind.animation;

  /// 폴더 생성: folds the active layer's whole attach group into a new
  /// folder row (mirrors into 겸용 cuts through the coordinator).
  void groupActiveLayerIntoFolder() => _activeCut.onActiveLayer(
    when: canGroupActiveLayerIntoFolder,
    command: (cutId, layerId) => _project.cutCommandCoordinator
        .createFolderFromLayer(cutId: cutId, layerId: layerId),
  );

  /// Whether the active layer can be wrapped in an ATTACH-ORGANIZER
  /// folder ([연출]/[작감]… — 공정별 묶음): an attach row, and that is all.
  ///
  /// 🪦The second clause used to be 「and not already inside one」 —
  /// organizers were deliberately FLAT (#786, the brush groups' precedent).
  /// 유저 2026-08-29 lifted it: 「어태치 폴더 중첩도 허용하는 방향으로 가자
  /// … 어태치폴더랑 일반폴더랑 규칙다른것도 많을거같은데 … 싹 다 통일」.
  ///
  /// 🚨It had to go from HERE too, not only from the drag. The drop policy
  /// stopped refusing nested folders in the same round, so this gate was
  /// the same question answered two ways — the menu said no to what the
  /// drag said yes to. A plain folder's gate ([canGroupActiveLayerIntoFolder])
  /// never had the clause, which is the shape both now share.
  bool get canGroupActiveAttachIntoFolder {
    final active = _selection.activeLayer;
    return active != null && isAttachedLayer(active);
  }

  /// 공정 폴더 생성: wraps the active ATTACH row in an organizer folder
  /// inside its group. Siblings join via [addAttachedLayer]'s sibling
  /// rule; renaming is plain [LayerVerbs.renameLayer].
  void groupActiveAttachIntoFolder() => _activeCut.onActiveLayer(
    when: canGroupActiveAttachIntoFolder,
    command: (cutId, layerId) => _project.cutCommandCoordinator
        .createAttachOrganizerFolder(cutId: cutId, layerId: layerId),
  );

  void dissolveFolder(LayerId folderId) => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.dissolveFolder(
      cutId: cutId,
      folderId: folderId,
    ),
  );

  // --- 분리 by MENU (P3) --------------------------------------------------
  //
  // MOUNTING has no menu verb: the drag makes an attach by dropping a row
  // strictly INSIDE a group, and R5 #15 gave the one case a gap cannot
  // reach — the first rider on a base — its own landing, dropping ON the
  // row ([LayerRowDrag.updateLayerRowDropOnRow]). The pair of "장착 to the
  // neighbour" verbs that lived here were that door before it existed; R5
  // deleted them once they became a second answer to the same question.
  //
  // The release keeps its menu entry: the drag must not be a one-way door.

  bool get canDetachActiveLayer {
    final active = _selection.activeLayer;
    return active != null && isAttachedLayer(active);
  }

  /// 어태치 해제: the active row stops riding its base.
  ///
  /// The row also STEPS OUT of the group when it has to
  /// ([detachLandingIndex]) — a detached row left inside the run would cut
  /// the group in two. The move and the detach are one undo step: the menu
  /// named one intent.
  void detachActiveLayer() {
    final cut = _project.activeCutOrNull;
    final row = _selection.activeLayer;
    if (cut == null || row == null || !isAttachedLayer(row)) {
      return;
    }
    final attach = LayerAttachDrop(detachIds: {row.id});
    final landing = detachLandingIndex(cut.layers, row.id);
    final plan = landing == null
        ? null
        : resolveLayerDrop(
            stack: cut.layers,
            movingId: row.id,
            insertAt: landing,
          );
    if (plan == null) {
      _project.cutCommandCoordinator.setLayerAttachment(
        cutId: cut.id,
        attach: attach,
        description: 'Detach layer',
      );
    } else {
      // The MENU says the row is leaving; the drop policy supplies the
      // geometry (order + membership) for the landing. Its own edge rule —
      // where a DRAG keeps the attachment — is deliberately overridden here,
      // because a drag's own travel is what says "still in the group" and a
      // menu item has no travel.
      _project.cutCommandCoordinator.setLayerPlacement(
        cutId: cut.id,
        order: plan.order,
        folderIds: plan.folderIds,
        movedIds: {row.id},
        attach: attach,
        description: 'Detach layer',
      );
    }
    _changes.refreshAfterCutCommand(preferredActiveLayerId: row.id);
    _changes.notifyChanged();
  }

  /// The row's twirl. R27 #24: FOLDING a folder that holds the active
  /// layer moves the selection to the folder row itself — otherwise the
  /// fold simply wouldn't look folded (the member row would have to stay
  /// on screen to keep something selected).
  void toggleLayerCollapsed(LayerId layerId) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final wasCollapsed = cut.layers.folderById(layerId)?.collapsed ?? false;
    _controllers.layerController.toggleLayerCollapsed(layerId);
    // H6: the fold law's selection half, on the FOLDER fold too — every
    // row inside a folder that just shut is off the screen, and the band
    // must not go on drawing over them ([RowSelection.foldRowSelection]).
    // The active layer's own hand-off below is the standing-row half of
    // the same law.
    if (!wasCollapsed) {
      // ↩️Both halves go through the fold law's one body since F-81
      // ([Standing.handOffOnFold]) — the standing half was
      // `layerController.selectLayer` here, beside the lane fold's own copy
      // and the attach fold's.
      bool insideThisFolder(LayerId? id) =>
          id != null &&
          cut.layers.isInsideFolder(cut.layers.byId(id)?.folderId, layerId);
      _handOffOnFold(
        swallower: LayerRowAddress(layerId),
        vanished: (address) => switch (address) {
          LayerRowAddress(:final layerId) => insideThisFolder(layerId),
          LaneRowAddress(:final layerId) => insideThisFolder(layerId),
          _ => false,
        },
      );
    }
    _changes.notifyChanged();
  }

  /// The "edit the owner" cursor pill for a grab that landed on a SYNCED
  /// attach row: the synced-block UI makes those rows look like ordinary
  /// blocks, so a refused drag must SAY why instead of dying silently
  /// (the pre-block ghost rows never invited the drag in the first place).
  void noticeSyncedAttachRefusal(LayerId layerId) {
    if (isSyncedAttachedLayerId(layerId)) {
      cursorNotices.show(AppText.strings.noticeEditAttachOwner);
    }
  }

  /// Whether [layerId] names one of the active cut's SYNCED attach rows —
  /// the timing standdowns key off THIS (free attach rows author their
  /// own timeline like any drawing layer, UI-R21 #3).
  bool isSyncedAttachedLayerId(LayerId layerId) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    for (final layer in cut.layers) {
      if (layer.id == layerId) {
        return isSyncedAttachedLayer(layer);
      }
    }
    return false;
  }
}
