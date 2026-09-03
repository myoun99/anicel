part of '../editor_session_manager.dart';

/// The LAYER VERBS — deleting, duplicating, linking and unlinking,
/// renaming and copying a layer, and adding a row above the active one —
/// as their own object. Each is a command over the repository; the
/// session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own and sixteen
/// session members touched; the rest reads it in three places. It reaches
/// the session through `_session`.
class _LayerVerbs {
  _LayerVerbs(this._session);

  final EditorSessionManager _session;

  void copyActiveLayer() => _session._clipboard.copyActiveLayer();

  bool get canDeleteActiveLayer {
    final activeLayer = _session.activeLayer;
    return activeLayer != null && canDeleteLayer(activeLayer);
  }

  /// Whether [activeLayer] may be deleted at all — the FLOORS, asked of any
  /// row rather than only of the active one (⑨ needs it per selected row).
  ///
  /// The parameter keeps its name so the body below reads unchanged: this
  /// was [canDeleteActiveLayer]'s own text, lifted so two askers cannot
  /// drift apart ([[predicates-before-new-kind]]).
  bool canDeleteLayer(Layer activeLayer) {
    // Read-only where a cut can see it: the transition row is deleted (and
    // moved) on the global axis, never from inside a cut.
    if (layerKindIsReadOnlyInCut(activeLayer.kind)) {
      return false;
    }
    // Attach rows are accessories: always deletable, never counted toward
    // the drawing floor (deleting a BASE cascades over its attach rows).
    if (isAttachedLayer(activeLayer)) {
      return true;
    }
    final cut = _session.activeCutOrNull;
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
      LayerKind.se => _session.activeTrack.seLayers.length > 2,
      LayerKind.instruction =>
        layers.where((layer) => layer.kind == LayerKind.instruction).length > 1,
      // R28 #14: NO drawing floor. The action section may stand empty —
      // the last action layer is deletable ("액션 레이어가 1개도 없는상황
      // 허용"). The global track is the thing that has to exist, not any
      // particular row inside a cut, and every drawing path already
      // handles "no editable cel" (that is the R26 #35 refusal notice).
      // A folder row deletes by DISSOLVING (the coordinator routes it) —
      // its members are rows of their own and survive.
      // An ADJUSTMENT row has no floor either: deleting it just stops the
      // stack below being filtered.
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.image ||
      LayerKind.text ||
      LayerKind.folder ||
      LayerKind.adjustment => true,
    };
  }

  /// ⑨: every selected row duplicated, in ONE undo — the rename's twin.
  void duplicateSelectedLayers() {
    final cut = _session.activeCutOrNull;
    final ids = _session.duplicatableSelectedLayerIds();
    if (cut == null || ids.isEmpty) {
      return;
    }
    LayerId? landed;
    _session._historyManager.runAsOneStep('Duplicate rows', () {
      for (final layerId in ids) {
        landed = _session._cutCommandCoordinator.duplicateLayer(
          cutId: cut.id,
          sourceLayerId: layerId,
        );
      }
    });
    _session._refreshAfterCutCommand(preferredActiveLayerId: landed);
    _session._notifyChanged();
  }

  /// ⑰'s law, applied to 복사: the verb asks WHAT IS SELECTED first and
  /// falls back to the row you are standing on. Every caller — the pill
  /// button, a shortcut — inherits that without asking twice.
  void duplicateActiveLayer() {
    if (_session.duplicatableSelectedLayerIds().isNotEmpty) {
      duplicateSelectedLayers();
      return;
    }
    final activeLayer = _session.activeLayer;
    // Track-owned SE rows: duplication stands down (same clipboard-shape
    // reason as copyActiveLayer); attach rows too (v1 — a duplicate would
    // double-link the same base cels).
    if (activeLayer == null ||
        !layerKindIsClipboardCopyable(activeLayer.kind) ||
        // R9 #7: the copy lands in the same cut — always the second one.
        layerKindIsSingletonPerCut(activeLayer.kind) ||
        isAttachedLayer(activeLayer)) {
      return;
    }

    final duplicatedLayerId = _session._cutCommandCoordinator.duplicateLayer(
      // A non-null active layer implies an active cut (gap state has no
      // rows at all).
      cutId: _session.requireActiveCut.id,
      sourceLayerId: activeLayer.id,
    );
    _session._refreshAfterCutCommand(preferredActiveLayerId: duplicatedLayerId);
    _session._notifyChanged();
  }

  /// Whether the layer is a member of a link group in the ACTIVE cut
  /// (drives the link badge on its label).
  bool isLayerLinked(LayerId layerId) {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return _session._repository.requireProject().linkRegistry.useCountOf(
          cutId: cut.id,
          layerId: layerId,
        ) >
        1;
  }

  bool get canLinkDuplicateActiveLayer {
    final activeLayer = _session.activeLayer;
    // Same stand-downs as plain duplication; an attach row's LINK
    // duplicate is reached through its base (the group goes whole).
    return activeLayer != null &&
        layerKindIsClipboardCopyable(activeLayer.kind) &&
        // R9 #7: a duplicate lands in the SAME cut, so a singleton kind's
        // copy would always be the second one.
        !layerKindIsSingletonPerCut(activeLayer.kind) &&
        !isAttachedLayer(activeLayer);
  }

  /// 링크 복제: duplicates the active layer's whole attach group SHARING
  /// the originals' pictures (the store routes both to one cel bank).
  void linkDuplicateActiveLayer() {
    if (!canLinkDuplicateActiveLayer) {
      return;
    }
    final activeLayer = _session.activeLayer!;
    _session._cutCommandCoordinator.linkDuplicateLayer(
      cutId: _session.requireActiveCut.id,
      layerId: activeLayer.id,
    );
    _session._refreshAfterCutCommand(preferredActiveLayerId: activeLayer.id);
    _session._notifyChanged();
  }

  bool get canUnlinkActiveLayer {
    final activeLayer = _session.activeLayer;
    final cut = _session.activeCutOrNull;
    if (activeLayer == null || cut == null) {
      return false;
    }
    // The verb unlinks the whole attach group; it is offered when ANY
    // member is linked (mirrors the coordinator's own guard).
    final baseId = activeLayer.attachedToLayerId ?? activeLayer.id;
    final registry = _session._repository.requireProject().linkRegistry;
    return cut.layers.any(
      (layer) =>
          (layer.id == baseId || layer.attachedToLayerId == baseId) &&
          registry.useCountOf(cutId: cut.id, layerId: layer.id) > 1,
    );
  }

  /// 독립시키기: forks the active layer's group out of its links — the
  /// pictures stay identical but stop being shared from here on.
  void unlinkActiveLayer() {
    if (!canUnlinkActiveLayer) {
      return;
    }
    final activeLayer = _session.activeLayer!;
    _session._cutCommandCoordinator.unlinkLayer(
      cutId: _session.requireActiveCut.id,
      layerId: activeLayer.id,
    );
    _session._refreshAfterCutCommand(preferredActiveLayerId: activeLayer.id);
    _session._notifyChanged();
  }

  /// Deletes the active layer. Callers should confirm via dialog first and check
  /// [canDeleteActiveLayer]; this is a no-op when deletion is not allowed.
  void deleteActiveLayer() {
    final activeLayer = _session.activeLayer;
    if (activeLayer == null || !canDeleteActiveLayer) {
      return;
    }

    if (activeLayer.kind == LayerKind.se) {
      final beforeSe = _session.activeTrack.seLayers;
      final nextActiveLayerId = stableLayerIdAfterDeleting(
        beforeLayers: beforeSe,
        deletedLayerId: activeLayer.id,
      );
      _session._historyManager.execute(
        RemoveTrackSeLayerCommand(
          repository: _session._repository,
          trackId: _session.selectedTrackId,
          layerId: activeLayer.id,
        ),
      );
      _session._refreshAfterCutCommand(
        preferredActiveLayerId: nextActiveLayerId,
      );
      _session._notifyChanged();
      return;
    }

    final beforeLayers = List<Layer>.of(_session.requireActiveCut.layers);
    final nextActiveLayerId = stableLayerIdAfterDeleting(
      beforeLayers: beforeLayers,
      deletedLayerId: activeLayer.id,
    );

    _session._cutCommandCoordinator.deleteLayer(
      cutId: _session.requireActiveCut.id,
      layerId: activeLayer.id,
    );
    _session._refreshAfterCutCommand(preferredActiveLayerId: nextActiveLayerId);
    _session._notifyChanged();
  }

  /// ⑨: deletes every selected row that names a deletable layer, as ONE
  /// undo step — the gesture selected them together, so it undoes together.
  ///
  /// Deleting from the TOP down keeps each removal's own bookkeeping (the
  /// stable next-active pick, an attach cascade) reading the stack it was
  /// written against: taking a lower row out first would shift the ones
  /// above it under the loop's feet.
  void deleteSelectedLayers() {
    final ids = _session.deletableSelectedLayerIds();
    if (ids.isEmpty) {
      return;
    }
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final order = {
      for (var index = 0; index < cut.layers.length; index += 1)
        cut.layers[index].id: index,
    };
    final ordered = [...ids]
      ..sort((a, b) => (order[b] ?? -1).compareTo(order[a] ?? -1));
    final nextActiveLayerId = stableLayerIdAfterDeleting(
      beforeLayers: List<Layer>.of(cut.layers),
      deletedLayerId: ordered.last,
    );
    _session._historyManager.runAsOneStep('Delete rows', () {
      for (final layerId in ordered) {
        _session._cutCommandCoordinator.deleteLayer(
          cutId: cut.id,
          layerId: layerId,
        );
      }
    });
    _session.clearRowSelection();
    _session._refreshAfterCutCommand(preferredActiveLayerId: nextActiveLayerId);
    _session._notifyChanged();
  }

  void renameActiveLayer(String name) {
    final activeLayer = _session.activeLayer;
    if (activeLayer == null) {
      return;
    }
    _session.renameLayer(activeLayer.id, name);
  }

  /// Inserts a NEW ROW the way one joins the stack above the active layer.
  ///
  /// Two structural rules, and they used to live inside the drawing-kind
  /// arm where every later kind had to remember them:
  /// - an attach group is INDIVISIBLE (R26 #36): the row lands past the
  ///   whole group, never between a base and its attach rows — whether the
  ///   active row is the base or one of its attaches. BOTH sides count: a
  ///   below-only group used to slip through an above-only check.
  /// - the row INHERITS the active row's folder. A row inserted into a
  ///   folder's contiguous member run without belonging to it breaks the
  ///   folder invariant and composites in the wrong scope; for R6b's
  ///   adjustment that meant filtering nothing at all, silently.
  void addRowAboveActive(Layer Function(Cut cut) build) {
    final cut = _session.requireActiveCut;
    final active = _session.activeLayer;
    final built = build(cut);
    final layer = active?.folderId == null
        ? built
        : built.copyWith(folderId: active!.folderId);
    final baseId = active == null
        ? null
        : isAttachedLayer(active)
        ? active.attachedToLayerId
        : active.id;
    if (baseId != null) {
      final groupEnd = attachedGroupEndIndex(baseId, cut.layers);
      final groupStart = attachedGroupStartIndex(baseId, cut.layers);
      if (groupEnd - groupStart > 1) {
        _session._layerController.addLayer(
          layer: layer,
          insertionIndex: groupEnd,
        );
        return;
      }
    }
    _session._layerController.addLayer(layer: layer);
  }
}
