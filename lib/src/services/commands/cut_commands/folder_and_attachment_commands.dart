part of '../cut_command_coordinator.dart';

/// THE FOLDER AND ATTACHMENT COMMANDS — dissolving a folder and attaching
/// a layer to another — as their own object.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: three coordinator members
/// shared. It reaches the coordinator through `_coordinator`.
///
/// ↩️It made folders too — one from a layer's whole attach group, and an
/// attach organizer around one attach row — for the two menu verbs R5 #14
/// took away. A folder is made empty from Add Layer and filled by a drop
/// now (layer-menu-strings-outlive-their-entries-Q3).
class _FolderAndAttachmentCommands {
  _FolderAndAttachmentCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  /// 폴더 해산: releases members to the parent and removes the folder row
  /// (layers stay). Mirrors into 겸용 cuts.
  void dissolveFolder({required CutId cutId, required LayerId folderId}) {
    _coordinator.historyManager.execute(
      DissolveFolderCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        folderId: folderId,
      ),
    );
  }

  /// 어태치 장착·분리 as one undo step across the whole 겸용 link group.
  ///
  /// The RELATION and its MODE are structure, so they are one answer for the
  /// group. Everything derived from a timeline is not: the SYNCED links and
  /// the detach BAKE are computed per cut against THAT cut's base, because
  /// 겸용 cuts share the cel bank and re-expose it each their own way — one
  /// cut's baked timing dressed onto another is somebody else's rhythm.
  ///
  /// The MODE is decided by scanning every use at once (user 2026-08-07):
  ///
  /// > SYNCED only when the row's exposure shape matches the base's in EVERY
  /// > use; one cut disagreeing makes the whole mount FREE.
  ///
  /// That single line is what makes "an empty row mounts FREE" a consequence
  /// rather than a special case, and it errs only toward keeping work: a cut
  /// where the row has real timing of its own never has it replaced.
  List<Command> layerAttachmentCommands({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) {
    if (attach.isEmpty) {
      return const [];
    }
    final project = _coordinator.repository.requireProject();
    final commands = <Command>[];

    for (final layerId in attach.detachIds) {
      for (final use in _coordinator._links.linkedRowUses(
        project,
        cutId: cutId,
        rowId: layerId,
      )) {
        final cut = requireCut(project, use.cutId);
        final row = requireLayer(project, cutId: use.cutId, layerId: use.rowId);
        if (row.attachedToLayerId == null) {
          continue;
        }
        commands.add(
          SetLayerAttachmentCommand(
            repository: _coordinator.repository,
            layerId: use.rowId,
            attachment: LayerAttachment.of(
              detachedLayer(
                attached: row,
                // The counterpart's OWN base in its OWN cut — the pointer
                // is per-cut even though the relation is shared.
                base: attachedBaseOf(row, cut.layers),
                drawnFrameCount: cutDrawnFrameCount(project, cut.id)!,
              ),
            ),
            description: description,
          ),
        );
      }
    }

    for (final sideChange in attach.sideChanges) {
      // Same base, other side. Everything derived from the timing stays as
      // it is — this is a direction, not a re-mount.
      for (final use in _coordinator._links.linkedRowUses(
        project,
        cutId: cutId,
        rowId: sideChange.layerId,
      )) {
        final row = requireLayer(project, cutId: use.cutId, layerId: use.rowId);
        if (row.attachedToLayerId == null ||
            row.attachedPlacement == sideChange.placement) {
          continue;
        }
        commands.add(
          SetLayerAttachmentCommand(
            repository: _coordinator.repository,
            layerId: use.rowId,
            attachment: LayerAttachment(
              attachedToLayerId: row.attachedToLayerId,
              placement: sideChange.placement,
              mode: row.attachedMode,
              timeline: row.timeline,
              baseFrameLinks: row.baseFrameLinks,
            ),
            description: description,
          ),
        );
      }
    }

    // ⑦: a folder drop mounts every row it carries, so this is a loop now.
    // Each rider still decides its own MODE — the 겸용 scan is per relation,
    // and two members of one folder can legitimately differ.
    for (final mount in attach.mounts) {
      final uses = mountUses(
        project,
        cutId: cutId,
        rowId: mount.layerId,
        baseId: mount.baseId,
      );
      final mode = _coordinator._mountMode(uses);
      for (final use in uses) {
        commands.add(
          SetLayerAttachmentCommand(
            repository: _coordinator.repository,
            layerId: use.rowId,
            attachment: attachmentForMount(
              standaloneRow: use.standalone,
              base: use.base,
              placement: mount.placement,
              mode: mode,
            ),
            description: description,
          ),
        );
      }
    }
    return commands;
  }

  /// Every use of the relation being made: the cut asked plus each 겸용
  /// sibling where BOTH rows have counterparts, with the row in its
  /// STANDALONE form (what a mount measures — see [attachmentForMount]).
  List<({LayerId rowId, Layer standalone, Layer base})> mountUses(
    Project project, {
    required CutId cutId,
    required LayerId rowId,
    required LayerId baseId,
  }) {
    final uses = <({LayerId rowId, Layer standalone, Layer base})>[];
    for (final use in _coordinator._links.linkedRowUses(
      project,
      cutId: cutId,
      rowId: rowId,
    )) {
      final useBaseId = use.cutId == cutId
          ? baseId
          : linkCounterpartIn(
              project,
              cutId: cutId,
              layerId: baseId,
              targetCutId: use.cutId,
            );
      if (useBaseId == null) {
        // The base does not reach that cut, so the relation cannot exist
        // there at all — not a use, and not a vote on the mode either.
        continue;
      }
      final cut = requireCut(project, use.cutId);
      final base = cut.layers.byId(useBaseId);
      final row = cut.layers.byId(use.rowId);
      if (base == null || row == null) {
        continue;
      }
      uses.add((
        rowId: use.rowId,
        standalone: detachedLayer(
          attached: row,
          base: attachedBaseOf(row, cut.layers),
          drawnFrameCount: cutDrawnFrameCount(project, cut.id)!,
        ),
        base: base,
      ));
    }
    return uses;
  }

  /// Commits an attach change on its own — the Layer menu's 장착·해제, where
  /// no row is dragged. Its rows still change seats, so the default names
  /// follow them as a drag's do. Empty input is a no-op rather than an
  /// empty undo entry.
  void setLayerAttachment({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) {
    _coordinator._executeMovingSeats(
      cutId,
      description,
      layerAttachmentCommands(
        cutId: cutId,
        attach: attach,
        description: description,
      ),
    );
  }
}
