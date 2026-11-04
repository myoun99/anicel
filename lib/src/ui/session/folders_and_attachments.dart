import '../../models/attached_layer_resolve.dart';
import '../../models/attached_mode.dart';
import '../../models/attached_layer_mount.dart';
import '../../models/attached_placement.dart';
import '../../models/conte_group.dart' show ridesTheConte;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../services/project_lookup.dart' show layerAnywhereOrNull;
import '../timeline/timeline_section_policy.dart' show sectionedLayerOrder;
import '../timeline/layer_drop_policy.dart'
    show detachLandingIndex, resolveLayerDrop;
import '../text/app_strings.dart';
import '../widgets/cursor_notice.dart';
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'rail_view.dart' show StandingLaw;
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
    required void Function(LayerId folderId) handOffOnFolderFold,
    required StandingLaw keepStandingShown,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _layerIds = layerIds,
       _activeCut = activeCut,
       _handOffOnFolderFold = handOffOnFolderFold,
       _keepStandingShown = keepStandingShown;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final LayerIdMint _layerIds;
  final ActiveCutEdits _activeCut;
  final void Function(LayerId folderId) _handOffOnFolderFold;

  /// The standing law with its reveal — a new attach row is where you went
  /// (`Standing.keepStandingShown`).
  final StandingLaw _keepStandingShown;

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
  /// row's base): own cels/eye/opacity, the base's FX; [side] picks above
  /// or below the row stood on, which it stands beside
  /// ([newAttachedRowBeside], I-159). [mode] picks the timing contract
  /// (UI-R21 #3): synced = the W5 ghost mirror riding the base's
  /// exposures; free = authors its own timeline like a normal drawing
  /// layer. Selected on creation; excluded from the timesheet by default.
  void addAttachedLayer(
    AttachedPlacement side, {
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
    // The folder comes with the seat: a row with none inside a folder's
    // contiguous run would break the folder invariant.
    final seat = newAttachedRowBeside(active, cut.layers, side);
    // UI-R23 #7 v2: the row is added EMPTY — the repository's
    // always-mirror reconciliation fills one own cel + base link per base
    // cel in the same write (and keeps doing so live as the base gains
    // cels later), so every mirror cell is editable from the first frame.
    _project.cutCommandCoordinator.addAttachedLayer(
      cutId: cut.id,
      layer: Layer(
        id: layerId,
        name: nextAttachedLayerName(base, cut.layers, seat.placement),
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
        attachedPlacement: seat.placement,
        attachedMode: mode,
        folderId: seat.folderId,
        // F-133: made FROM the row you stand on, it starts with that row's
        // colour label — the door names its target ([LayerMark.inherited]).
        mark: active.mark.inherited,
      ),
      insertionIndex: seat.index,
    );
    _controllers.layerController.selectLayer(layerId);
    // F-169 ②: made from a folded group's base, the new row opens its group.
    // ↩️It used to show that one row inside the shut group (the active attach
    // row's exemption, UI-R20 #9) — the exemption that also put a handed-off
    // row on the screen.
    _keepStandingShown(reveal: true);
    _changes.notifyChanged();
  }

  // ↩️폴더 생성 · 공정 폴더 생성 stood here — the active row (or attach
  // row) wrapped in a new folder. R5 #14 took their menu entries: a folder
  // is made EMPTY from Add Layer and filled by dropping rows on it, and
  // the drop makes an organizer too (F-139). The verbs outlived their
  // doors and went in layer-menu-strings-outlive-their-entries-Q3.

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

  /// …except a row riding the conte, which is never let go
  /// ([ridesTheConte], I-73-one-head-Q1).
  bool get canDetachActiveLayer {
    final active = _selection.activeLayer;
    final cut = _project.activeCutOrNull;
    return active != null &&
        isAttachedLayer(active) &&
        !(cut != null && ridesTheConte(active, cut.layers));
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
    if (cut == null || row == null || !canDetachActiveLayer) {
      return;
    }
    final attach = LayerAttachDrop(detachIds: {row.id});
    // As the drag reads it ([RowOrderDrag]'s landings, F-538).
    final stack = sectionedLayerOrder(cut.layers);
    final landing = detachLandingIndex(stack, row.id);
    final plan = landing == null
        ? null
        : resolveLayerDrop(
            stack: stack,
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
    // Found wherever it is: the conte panel presses a folder of the conte
    // in hand, which need not be the cut stood in (I-99).
    final folder = layerAnywhereOrNull(
      _project.repository.requireProject(),
      layerId,
    );
    if (folder == null) {
      return;
    }
    _controllers.layerController.toggleLayerCollapsed(layerId);
    // H6: the fold law's selection half, on the FOLDER fold too — every
    // row inside a folder that just shut is off the screen, and the band
    // must not go on drawing over them ([RowSelection.foldRowSelection]).
    // The active layer's own hand-off is the standing-row half of the same
    // law.
    if (!folder.collapsed) {
      // ↩️Both halves go through the fold law's one body since F-81
      // ([Standing.handOffOnFold]) — the standing half was
      // `layerController.selectLayer` here, beside the lane fold's own copy
      // and the attach fold's — and through the group fold's since I-99,
      // which hands the storyboard on as well.
      _handOffOnFolderFold(layerId);
    }
    _changes.notifyChanged();
  }

  /// A base's ATTACH GROUP folded or opened: the base's own `collapsed`,
  /// written as a folder's is — one control, one field (F-360). The fold's
  /// hand-off is the caller's, made before the group shuts
  /// (`Standing.handOffCurrentRowOnAttachFold`). ⚠️No session notify: the
  /// rails read the fold off the document ([RailView.readFolds]), which
  /// every history change re-reads.
  void toggleAttachGroup(LayerId baseId) =>
      _controllers.layerController.toggleLayerCollapsed(baseId);

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
