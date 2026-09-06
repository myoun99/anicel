part of '../cut_command_coordinator.dart';

/// THE FOLDER AND ATTACHMENT COMMANDS — a folder from a layer, the
/// organizer folder an attach lives in, dissolving one, and attaching a
/// layer to another — as their own object.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: three coordinator members
/// shared. It reaches the coordinator through `_coordinator`.
class _FolderAndAttachmentCommands {
  _FolderAndAttachmentCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  /// 폴더 생성: folds [layerId]'s whole attach group into a new folder ROW
  /// inserted directly above the group (attach groups never split across a
  /// folder boundary; the group is a contiguous stack run — belows and
  /// their organizer folder rows included). Only the slice's TOP-LEVEL
  /// rows re-folder: attach rows inside an ORGANIZER ([연출]/[작감]…) keep
  /// their organizer, which is itself a member — inner structure survives
  /// the fold. Mirrors into 겸용 cuts. Returns the new folder layer's id
  /// in [cutId], null when the layer can't fold (non-drawing kinds).
  ///
  /// Renaming the folder afterwards is just [_coordinator.renameLayer] — a folder is a
  /// layer, so it needs no command of its own.
  LayerId? createFolderFromLayer({
    required CutId cutId,
    required LayerId layerId,
    String? name,
  }) {
    final project = _coordinator.repository.requireProject();
    final cut = requireCut(project, cutId);
    final source = requireLayer(project, cutId: cutId, layerId: layerId);
    if (source.kind != LayerKind.animation) {
      return null;
    }
    final baseId = attachBaseIdOf(source);
    final base = requireLayer(project, cutId: cutId, layerId: baseId);
    final slice = attachedGroupSlice(baseId, cut.layers);
    final memberIds = [
      for (final layer in slice)
        if (layer.folderId == base.folderId) layer.id,
    ];
    final plan = planCreateFolderCommandInput(
      project: project,
      cutId: cutId,
      memberLayerIds: memberIds,
    );

    _coordinator.historyManager.execute(
      CreateFolderCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        name: name ?? nextFolderName(cut),
        memberLayerIds: memberIds,
        folderIdByCut: plan.folderIdByCut,
        groupId: plan.folderGroupId,
      ),
    );
    return plan.folderIdByCut[cutId];
  }

  /// 공정 폴더 생성: wraps ONE attach row in an ORGANIZER folder
  /// ([연출]/[작감]…) INSIDE its attach group. The attach relation stays
  /// direct to the base — the folder organizes and display-controls only.
  /// Siblings join through [EditorSessionManager.addAttachedLayer]'s
  /// sibling rule (adding from a row inside an organizer lands next to
  /// it).
  ///
  /// 🪦It used to add 「Organizers are FLAT: a row already inside one
  /// refuses (null)」 — #786's own rule, lifted by 유저 2026-08-29
  /// (「어태치 폴더 중첩도 허용하는 방향으로 가자 … 싹 다 통일」). The
  /// refusal is gone from the verb as well as from the gate: a menu that
  /// greys out is a different bug from a verb that silently returns null,
  /// and leaving one of the two behind is how the rule comes back.
  ///
  /// Still deliberately PER-CUT — no 겸용 mirror, no link-group membership.
  /// ⚠️The flat rule was one of two reasons given for that and is no longer
  /// available; the standing one is that an unlinked folder row keeps
  /// deletes and dissolves from fanning out into other cuts' structures.
  LayerId? createAttachOrganizerFolder({
    required CutId cutId,
    required LayerId layerId,
    String? name,
  }) {
    final project = _coordinator.repository.requireProject();
    final cut = requireCut(project, cutId);
    final source = requireLayer(project, cutId: cutId, layerId: layerId);
    if (!isAttachedLayer(source)) {
      return null;
    }
    final memberIds = [source.id];
    final plan = planCreateFolderCommandInput(
      project: project,
      cutId: cutId,
      memberLayerIds: memberIds,
    );
    final folderId = plan.folderIdByCut[cutId]!;
    _coordinator.historyManager.execute(
      CreateFolderCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        name: name ?? nextFolderName(cut),
        memberLayerIds: memberIds,
        // Origin cut only: mirror cuts are deliberately excluded (see
        // the doc above) — the command skips any cut absent from this
        // map.
        folderIdByCut: {cutId: folderId},
        groupId: plan.folderGroupId,
      ),
    );
    return folderId;
  }

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
                cutFrameCount: cut.duration,
              ),
            ),
            description: description,
          ),
        );
      }
    }

    final sideChange = attach.sideChange;
    if (sideChange != null) {
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
              runBehaviors: row.runBehaviors,
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
          cutFrameCount: cut.duration,
        ),
        base: base,
      ));
    }
    return uses;
  }

  /// Commits an attach change on its own — the Layer menu's 장착·해제, where
  /// no row moves. Empty input is a no-op rather than an empty undo entry.
  void setLayerAttachment({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) {
    final commands = layerAttachmentCommands(
      cutId: cutId,
      attach: attach,
      description: description,
    );
    if (commands.isEmpty) {
      return;
    }
    _coordinator.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
    );
  }
}
