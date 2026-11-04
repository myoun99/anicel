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

  /// The 겸용 cut [createLinkedCut] makes of [sourceCutId] when it is told
  /// no name — what the new cut window offers for it (🗣️I-100-Q1): the
  /// name that counts on from its source's — it is inserted right after
  /// its source, so the source is what it counts from — and its source's
  /// canvas, whose pictures it shares.
  ({String name, CanvasSize canvasSize}) plannedLinkedCut({
    required CutId sourceCutId,
  }) {
    final project = _coordinator.repository.requireProject();
    final source = requireCut(project, sourceCutId);
    return (
      name: CutCommandCoordinator.nextCutNameAfter(project, source.name),
      canvasSize: source.canvasSize,
    );
  }

  /// 겸용컷 생성 (L2): a new cut whose drawing layers share the source's
  /// cel banks with EMPTY timelines — the bank re-exposes to a new
  /// rhythm. One undo step; the new cut becomes active, directly behind its
  /// source.
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
        newName: name ?? plannedLinkedCut(sourceCutId: sourceCutId).name,
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
        coveringFrameIdBySource: plan.coveringFrameIdBySource,
      ),
    );
  }

  /// A 겸용 cut of [sourceCutId] made AS IT STANDS: [copied] — a board's
  /// copy of it — put down on [landing] as a copy is ([_CutCommands
  /// .copyCut]), named as a linked paste is there, then made a 겸용 of the
  /// source ([convertCutToLinked]). [carry] hands the copy its pictures in
  /// between, told which of the copy's cels the conversion REPLACES with
  /// the source's namesakes — no row shows those after it. One undo step;
  /// the new cut becomes active.
  ///
  /// 🗣️F-555 (유저 2026-11-04): 「컷버튼의 겸용컷 작성은 지금처럼 빈
  /// 타임라인인채로 만드는거 ok. 다만 컷블록을 복사하고 링크붙여넣기할땐 같은
  /// 타임라인인채로」 · F-555-Q1: 「디렉션까지도 복사. 완전 글로벌인 se행만
  /// 복사안하는것임. 콘티도 물론 복사하는거고」 — the 「타이밍까지 통째 겸용 =
  /// 복제→변경」 path ([ConvertToLinkedCutCommand]) in one press: the
  /// length, the timing, the camera's keys and the direction rows are the
  /// copy's, and its pictures link by name — an unnamed one stays its own
  /// (F-278: 「이름이 없으면 독립적인 그림」).
  void createLinkedCutAsItStands(
    Cut copied, {
    required CutId sourceCutId,
    required CutLanding landing,
    required void Function(DuplicatedCut landed, Set<FrameId> replaced) carry,
  }) {
    final name = _nameWhere(landing, sourceCutId: sourceCutId);
    _coordinator.historyManager.runAsOneStep('Create linked cut $name', () {
      final landed = _coordinator._cuts.copyCut(
        copied,
        landing: landing,
        newName: name,
      );
      final plan = convertToLinkedCutPreview(
        originCutId: sourceCutId,
        targetCutId: landed.cutId,
      );
      carry(landed, {
        for (final cels in plan.replacedFrames.values) ...cels,
      });
      convertCutToLinked(originCutId: sourceCutId, targetCutId: landed.cutId);
    });
  }

  /// 동기컷 생성 (I-150-Q3): [sourceCutId] — a cut of another timeline —
  /// made a cut of the timeline open as well, the same cut, standing on
  /// [landing] and named as a linked paste is there (I-150-Q5 「지금대로」:
  /// counting on from the cut in front of it). One undo step; the new cut
  /// becomes active.
  void createSyncedCut({
    required CutId sourceCutId,
    required CutLanding landing,
  }) {
    final project = _coordinator.repository.requireProject();
    final plan = planCreateSyncedCutCommandInput(
      project: project,
      sourceCut: requireCut(project, sourceCutId),
    );
    _coordinator.historyManager.execute(
      CreateSyncedCutCommand(
        repository: _coordinator.repository,
        editingSession: _coordinator.editingSession,
        sourceCutId: sourceCutId,
        newCutId: plan.newCutId,
        newName: _nameWhere(landing, sourceCutId: sourceCutId),
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
        newSyncId: plan.newSyncId,
        landing: landing,
      ),
    );
  }

  /// The name a cut a linked paste puts down on [landing] takes: counting
  /// on from the cut in front of where it lands (I-150-Q5).
  String _nameWhere(CutLanding landing, {required CutId sourceCutId}) {
    final project = _coordinator.repository.requireProject();
    return CutCommandCoordinator.nextCutNameAfter(
      project,
      _coordinator._cuts._referenceNameAt(
        project,
        landing.trackId,
        landing.index,
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

  /// 동기 해제 (I-150-Q6, 유저 2026-11-04 「동기 해제 = 독립 컷」): [cutId]
  /// leaves its 동기컷 ([LeaveSyncCommand]) and then every link of its rows,
  /// each as 독립시키기 unlinks one — an independent cut, every picture and
  /// every sheet each part's own — and a 겸용 it had where it stood parts
  /// from the cuts it leaves ([PartLinksAcrossTimelinesCommand]). ONE undo
  /// step. Nothing for a cut of its own.
  void unsyncCut(CutId cutId) {
    final project = _coordinator.repository.requireProject();
    if (project.linkRegistry.syncOf(cutId) == null) {
      return;
    }
    final parting = PartLinksAcrossTimelinesCommand.forLeaving(
      repository: _coordinator.repository,
      brushFrameStore: _coordinator.brushFrameStore,
      leaving: {cutId},
    )!;
    _coordinator.historyManager.runAsOneStep('Leave sync', () {
      _coordinator.historyManager.execute(
        LeaveSyncCommand(
          repository: _coordinator.repository,
          sheetInkStores: _coordinator.sheetInkStores,
          cutId: cutId,
        ),
      );
      for (final layer in requireCut(project, cutId).layers) {
        unlinkLayer(cutId: cutId, layerId: layer.id);
      }
      _coordinator.historyManager.execute(parting);
    });
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

    _coordinator.historyManager.executeAsOneStep(
      'Convert cut $targetCutId to link $originCutId',
      [
        ?_convertResize(originCut, targetCut),
        ConvertToLinkedCutCommand(
          repository: _coordinator.repository,
          brushFrameStore: store,
          originCutId: originCutId,
          targetCutId: targetCutId,
          unionLayerIdMap: plan.unionLayerIdMap,
          newGroupIdBySource: plan.newGroupIdBySource,
          coveringFrameIdBySource: plan.coveringFrameIdBySource,
          siblingUnionLayerIdMap: plan.siblingUnionLayerIdMap,
          siblingCoveringFrameIds: plan.siblingCoveringFrameIds,
        ),
      ],
    );
  }

  /// What [convertCutToLinked] works out ahead: its resize's, the target's
  /// canvas taken to the origin's ([ResizeCutCanvasCommand.workAhead]) —
  /// null when the two canvases already agree.
  WorkAhead? convertCutToLinkedAhead({
    required CutId originCutId,
    required CutId targetCutId,
  }) {
    final project = _coordinator.repository.requireProject();
    return _convertResize(
      requireCut(project, originCutId),
      requireCut(project, targetCutId),
    )?.workAhead(undo: false);
  }

  /// The resize a conversion of [targetCut] to link [originCut] starts with
  /// — none when their canvases already agree.
  ResizeCutCanvasCommand? _convertResize(Cut originCut, Cut targetCut) =>
      targetCut.canvasSize == originCut.canvasSize
      ? null
      : ResizeCutCanvasCommand(
          repository: _coordinator.repository,
          cutId: targetCut.id,
          canvasSize: originCut.canvasSize,
          contentOffset: CanvasResizeAnchor.center.contentOffset(
            from: targetCut.canvasSize,
            to: originCut.canvasSize,
          ),
          brushFrameStore: _coordinator.brushFrameStore,
        );

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
  /// canonical resolution makes the pictures one), aimed at the stack seat
  /// [insertionIndex] — in [intoFolder] when one is named. One undo step.
  /// Answers [layerId]'s own copy.
  LayerId linkDuplicateLayer({
    required CutId cutId,
    required LayerId layerId,
    required int insertionIndex,
    LayerId? intoFolder,
  }) {
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
        insertionIndex: insertionIndex,
        intoFolder: intoFolder,
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
        siblings: plan.siblings,
      ),
    );
    return plan.layerIdMap[layerId]!;
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
