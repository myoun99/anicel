part of '../cut_command_coordinator.dart';

/// THE LINK COMMANDS — linked cuts and linked layers: creating one,
/// converting to one, unlinking, and the rows a linked row is used by —
/// as their own object.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: six coordinator members
/// shared. It reaches the coordinator through `_coordinator`.
class _LinkCommands {
  _LinkCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  /// 겸용컷 생성 (L2): a new cut whose drawing layers share the source's
  /// cel banks with EMPTY timelines — the bank re-exposes to a new
  /// rhythm. One undo step; the new cut becomes active.
  void createLinkedCut({required CutId sourceCutId, String? name}) {
    final project = _coordinator.repository.requireProject();
    final sourceCut = requireCut(project, sourceCutId);
    final plan = planCreateLinkedCutCommandInput(
      project: project,
      sourceCut: sourceCut,
    );

    _coordinator.historyManager.execute(
      CreateLinkedCutCommand(
        repository: _coordinator.repository,
        editingSession: _coordinator.editingSession,
        sourceCutId: sourceCutId,
        newCutId: plan.newCutId,
        // A linked cut is inserted right after its source, so the source
        // is what it counts from.
        newName:
            name ??
            CutCommandCoordinator.nextCutNameAfter(project, sourceCut.name),
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
      ),
    );
  }

  /// 독립시키기 (L2): removes [layerId]'s whole attach group from its
  /// link groups and forks the shared pixels into the group's own cels.
  /// No-op when nothing in the group is linked. One undo step.
  void unlinkLayer({required CutId cutId, required LayerId layerId}) {
    final store = _coordinator.brushFrameStore;
    if (store == null) {
      throw StateError('unlinkLayer needs the brush frame store.');
    }
    final project = _coordinator.repository.requireProject();
    final cut = requireCut(project, cutId);
    final source = requireLayer(project, cutId: cutId, layerId: layerId);
    final anyLinked = attachedGroupSlice(
      attachBaseIdOf(source),
      cut.layers,
    ).any(
      (member) =>
          project.linkRegistry.groupOf(cutId: cutId, layerId: member.id) !=
          null,
    );
    if (!anyLinked) {
      return;
    }

    _coordinator.historyManager.execute(
      UnlinkLayerCommand(
        repository: _coordinator.repository,
        brushFrameStore: store,
        cutId: cutId,
        sourceLayerId: layerId,
      ),
    );
  }

  /// 겸용 변경 (L2b): links [targetCutId] to [originCutId] after both
  /// were drawn — name-matching, 원본 승리 conflicts, 완전 미러 union.
  /// [plan] previews the effect for the confirmation dialog; the caller
  /// shows it and only then invokes this. No-op when nothing would link.
  /// One undo step. Needs the brush frame store.
  /// 겸용 변경 (L2b): links [targetCutId] to [originCutId].
  ///
  /// ★A 겸용 GROUP SHARES ONE CANVAS SIZE, and linking is where that starts
  /// being true. 🗣️유저 2026-09-12: 「링크컷인데 컷 하나 캔버스크기 바꾸면
  /// 다른 링크된컷도 바뀌어야 하는데 안바뀌거든?」 — the RESIZE was never
  /// the broken half (`ResizeCutCanvasCommand` already fans out through
  /// `linkedCutSiblings`, measured both ways). This was: a convert left
  /// the two at whatever sizes they happened to have, and the dialog
  /// merely SAID the origin's size wins. A pair that starts out of step
  /// stays out of step, which is what reads as "the other cut does not
  /// change".
  ///
  /// ⛔The resize is not re-implemented here. [ResizeCutCanvasCommand]
  /// owns the whole motion — the model write, the one-pass raster
  /// adoption, the anchor, the exact undo — and it walks the 겸용 siblings
  /// itself, so COMPOSING it is what keeps ONE law. Composing also keeps
  /// the conversion one undo step, as [ConvertToLinkedCutCommand]'s own
  /// doc already promised.
  void convertCutToLinked({
    required CutId originCutId,
    required CutId targetCutId,
  }) {
    final store = _coordinator.brushFrameStore;
    if (store == null) {
      throw StateError('convertCutToLinked needs the brush frame store.');
    }
    final project = _coordinator.repository.requireProject();
    final originCut = requireCut(project, originCutId);
    final targetCut = requireCut(project, targetCutId);
    if (!convertToLinkedCutPreview(
      originCutId: originCutId,
      targetCutId: targetCutId,
    ).linksAnything) {
      return;
    }
    final plan = planConvertToLinkedCutCommandInput(
      project: project,
      originCut: originCut,
      targetCut: targetCut,
    );

    final commands = <Command>[
      if (targetCut.canvasSize != originCut.canvasSize)
        ResizeCutCanvasCommand(
          repository: _coordinator.repository,
          cutId: targetCutId,
          canvasSize: originCut.canvasSize,
          anchor: CanvasResizeAnchor.center,
          brushFrameStore: store,
        ),
      ConvertToLinkedCutCommand(
        repository: _coordinator.repository,
        brushFrameStore: store,
        originCutId: originCutId,
        targetCutId: targetCutId,
        unionLayerIdMap: plan.unionLayerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
      ),
    ];

    _coordinator.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Convert cut $targetCutId to link $originCutId',
              commands: commands,
            ),
    );
  }

  /// The 겸용 변경 preview for the confirmation dialog (링크 목록·교체
  /// 장수·합류 수·양측 고유 레이어) — pure, no mutation.
  ConvertToLinkedCutPlan convertToLinkedCutPreview({
    required CutId originCutId,
    required CutId targetCutId,
  }) {
    final project = _coordinator.repository.requireProject();
    return planConvertToLinkedCut(
      project: project,
      originCut: requireCut(project, originCutId),
      targetCut: requireCut(project, targetCutId),
    );
  }

  /// 링크 복제 (L2): duplicates [layerId]'s whole attach group as a free
  /// group sharing the originals' cel banks (same FrameIds — the store's
  /// canonical resolution makes the pictures one). One undo step.
  void linkDuplicateLayer({required CutId cutId, required LayerId layerId}) {
    final project = _coordinator.repository.requireProject();
    final cut = requireCut(project, cutId);
    _coordinator._requireLayer(cutId: cutId, layerId: layerId);
    final plan = planLinkDuplicateLayerCommandInput(
      project: project,
      cut: cut,
      sourceLayerId: layerId,
    );

    _coordinator.historyManager.execute(
      LinkDuplicateLayerCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        sourceLayerId: layerId,
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
      ),
    );
  }

  /// Every (cut, row) the same shared row reaches: this cut, plus the 겸용
  /// siblings holding a counterpart.
  List<({CutId cutId, LayerId rowId})> linkedRowUses(
    Project project, {
    required CutId cutId,
    required LayerId rowId,
  }) {
    final uses = <({CutId cutId, LayerId rowId})>[(cutId: cutId, rowId: rowId)];
    for (final siblingId in linkedCutSiblings(project, cutId: cutId)) {
      final counterpart = linkCounterpartIn(
        project,
        cutId: cutId,
        layerId: rowId,
        targetCutId: siblingId,
      );
      if (counterpart != null) {
        uses.add((cutId: siblingId, rowId: counterpart));
      }
    }
    return uses;
  }
}
