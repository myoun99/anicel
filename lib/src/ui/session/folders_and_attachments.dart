part of '../editor_session_manager.dart';

/// FOLDERS AND ATTACHMENTS — grouping the active layer or attach into a
/// folder, dissolving one, adding an attached layer, and the synced-attach
/// refusal — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads it in four places
/// (the block move and frame shift asking whether a row is a synced
/// attach).
class _FoldersAndAttachments {
  _FoldersAndAttachments(this._session);

  final EditorSessionManager _session;

  /// Whether the active layer can carry (or already rides within) an
  /// attach group — the Add Attach Layer entrance's gate (W5).
  bool get canAddAttachedLayerToActive {
    final active = _session.activeLayer;
    if (active == null) {
      return false;
    }
    if (isAttachedLayer(active)) {
      // Adding from an attach row targets ITS base (same group).
      return attachedBaseOf(active, _session.requireActiveCut.layers) != null;
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
    final active = _session.activeLayer!;
    final cut = _session.requireActiveCut;
    final base = isAttachedLayer(active)
        ? attachedBaseOf(active, cut.layers)!
        : active;
    final layerId = _session._mintLayerId();
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
    _session.layerController.addLayer(
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
        kind: layerKindAcceptsBrushInput(base.kind)
            ? base.kind
            : LayerKind.animation,
        onTimesheet: false,
        attachedToLayerId: base.id,
        attachedPlacement: placement,
        attachedMode: mode,
        folderId: folderId,
      ),
      insertionIndex: insertionIndex,
    );
    _session.notifyChanged();
  }

  bool get canGroupActiveLayerIntoFolder =>
      _session.activeLayer != null &&
      _session.activeLayer!.kind == LayerKind.animation;

  /// 폴더 생성: folds the active layer's whole attach group into a new
  /// folder row (mirrors into 겸용 cuts through the coordinator).
  void groupActiveLayerIntoFolder() {
    if (!canGroupActiveLayerIntoFolder) {
      return;
    }
    final activeLayerId = _session.activeLayer!.id;
    _session.cutCommandCoordinator.createFolderFromLayer(
      cutId: _session.requireActiveCut.id,
      layerId: activeLayerId,
    );
    _session.refreshAfterCutCommand(preferredActiveLayerId: activeLayerId);
    _session.notifyChanged();
  }

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
    final active = _session.activeLayer;
    return active != null && isAttachedLayer(active);
  }

  /// 공정 폴더 생성: wraps the active ATTACH row in an organizer folder
  /// inside its group. Siblings join via [addAttachedLayer]'s sibling
  /// rule; renaming is plain [_session.renameLayer].
  void groupActiveAttachIntoFolder() {
    if (!canGroupActiveAttachIntoFolder) {
      return;
    }
    final activeLayerId = _session.activeLayer!.id;
    _session.cutCommandCoordinator.createAttachOrganizerFolder(
      cutId: _session.requireActiveCut.id,
      layerId: activeLayerId,
    );
    _session.refreshAfterCutCommand(preferredActiveLayerId: activeLayerId);
    _session.notifyChanged();
  }

  void dissolveFolder(LayerId folderId) {
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session.cutCommandCoordinator.dissolveFolder(
      cutId: cutId,
      folderId: folderId,
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  /// The "edit the owner" cursor pill for a grab that landed on a SYNCED
  /// attach row: the synced-block UI makes those rows look like ordinary
  /// blocks, so a refused drag must SAY why instead of dying silently
  /// (the pre-block ghost rows never invited the drag in the first place).
  void _noticeSyncedAttachRefusal(LayerId layerId) {
    if (isSyncedAttachedLayerId(layerId)) {
      cursorNotices.show(AppText.strings.noticeEditAttachOwner);
    }
  }

  /// Whether [layerId] names one of the active cut's SYNCED attach rows —
  /// the timing standdowns key off THIS (free attach rows author their
  /// own timeline like any drawing layer, UI-R21 #3).
  bool isSyncedAttachedLayerId(LayerId layerId) {
    final cut = _session.activeCutOrNull;
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
