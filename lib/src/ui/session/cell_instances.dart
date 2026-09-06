part of '../editor_session_manager.dart';

/// The CELL INSTANCES — creating instances for a selection, whether the
/// active cell holds one, and the subject an instance edit acts on — as
/// their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class _CellInstances {
  _CellInstances(this._session);

  final EditorSessionManager _session;

  /// UI-R25 #3: Add with a LIVE selection fills the WHOLE selection —
  /// wherever creation is possible, kind by kind (the rule: anywhere
  /// selectable creates). Returns true when a selection owned the press.
  ///
  /// - Cell selection: every spanned row fills its EMPTY gaps inside the
  ///   range — drawing/SE rows with a new cel per gap (exposure = gap,
  ///   ONE undo across all rows), instruction rows with a default-
  ///   vocabulary event per gap (one undo per row), the camera row with a
  ///   pose key frozen on every unkeyed frame (one undo).
  /// - Lane selection: the lane freezes a key on every unkeyed frame of
  ///   the range (one undo) — the navigator toggle's range form.
  bool createInstancesForSelection() {
    // #16 — THE TRACK RANGE SPEAKS FIRST, like it does for delete and
    // edit (유저: 「스토리보드패널에서 S행의 프레임생성이 안됨」). The S-row
    // drag writes trackFrameRangeSelection and its claim CLEARS the
    // cut-local selection this verb used to read, so creation fell
    // through to the stale active layer — the wrong row entirely. The
    // ladder rung was simply missing.
    final trackRange = _session.trackFrameRangeSelection.value;
    if (trackRange != null &&
        _session._trackSe.createTrackSeEntriesForRange(trackRange)) {
      return true;
    }
    // R10 #19: a live lane SPAN, or the property row you are STANDING on
    // as a one-frame span at the playhead — one verb either way, which is
    // what makes a group HEADER key its whole member set and an effect
    // lane key its chain without a second code path (the user's
    // "카메라레이어랑 같은 동작이지? 로직 통일화해서").
    final lane = _session._laneVerbs.laneVerbRange;
    if (lane != null) {
      _session._laneVerbs.createLaneKeysForSelection(lane);
      return true;
    }
    final selection = _session.frameRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final displayById = {for (final layer in _session.layers) layer.id: layer};
    final fills =
        <
          LayerId,
          List<({int startIndex, int length, FrameId frameId, String? name})>
        >{};
    // R26 #1: every row of the selection composes into ONE undo step.
    // Camera goes FIRST — its undo restores a whole-project snapshot, so it
    // must be the last command undone (CompositeCommand undoes in reverse).
    final cameraCommands = <Command>[];
    final instructionCommands = <Command>[];
    for (final layerId in selection.spanLayerIds) {
      final layer = displayById[layerId];
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final command = _session._camera.cameraKeysCommandForRange(selection);
        if (command != null) {
          cameraCommands.add(command);
        }
        continue;
      }
      if (layer.kind == LayerKind.instruction) {
        final command = _session._instructions.instructionEventsCommandForRange(
          layer,
          selection,
        );
        if (command != null) {
          instructionCommands.add(command);
        }
        continue;
      }
      final layerFills = _authoredFillsFor(layer, selection);
      if (layerFills.isNotEmpty) {
        fills[layer.id] = layerFills;
      }
    }
    final commands = <Command>[
      ...cameraCommands,
      ...instructionCommands,
      if (fills.isNotEmpty)
        ..._session.timelineController.drawingFramesCommandsForLayers(fills),
    ];
    if (commands.isNotEmpty) {
      _session.historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Create selected cells',
                commands: commands,
              ),
      );
      if (cameraCommands.isNotEmpty || instructionCommands.isNotEmpty) {
        _session.refreshAfterCutCommand();
      }
    }
    _session.notifyChanged();
    return true;
  }

  /// The blank cels [selection] authors on [layer]: one per empty gap,
  /// each with a fresh frame id — none on a row that takes no authored
  /// cels, a synced mirror, or a covering row.
  List<({int startIndex, int length, FrameId frameId, String? name})>
  _authoredFillsFor(Layer layer, TimelineFrameRangeSelection selection) {
    if (!layerKindTakesAuthoredCels(layer.kind) ||
        isSyncedAttachedLayer(layer)) {
      return const []; // Synced mirrors follow their base; nothing to author.
    }
    // R9 #9: a COVERING row is one cel edge to edge — there is no "add a
    // frame" in its world, so a selection that happens to span it must
    // pass over it rather than author into it. Until now nothing happened
    // by luck (the covering normalization leaves no empty gap to fill),
    // and #1 is about to put folders — and so their image members — into
    // range selections on purpose. Say it instead of relying on it.
    if (layerKindCoversWithoutGaps(layer.kind)) {
      return const [];
    }
    final layerFills =
        <({int startIndex, int length, FrameId frameId, String? name})>[];
    for (final gap in _session._emptyGapsInRange(layer, selection)) {
      _session._frameSequence += 1;
      layerFills.add((
        startIndex: gap.startIndex,
        length: gap.length,
        frameId: FrameId(_session.nextFrameId(layer.id)),
        name: null,
      ));
    }
    return layerFills;
  }

  /// #16 — creation on the TRACK axis: the S rows the range names get one
  /// blank dialogue entry per uncovered run, in one undo step. Returns
  /// false when the range names no track SE row (a cut-row range is the
  /// cut pill's business, #18) — the verb then falls down its ladder.
  ///
  /// Track SE timelines are GLOBAL-keyed, and the fills carry explicit
  /// indexes, so no cut-start lens is involved — the same reason the
  /// storyboard could never reach these rows through the cut-local
  /// selection object.
  /// #17 잔여 — THE CREATE BUTTON'S ONE SENTENCE (T25). Mirrors
  /// [createActiveInstance]'s ladder rung for rung: the selection rungs
  /// first (track S rows → lane span → cut-local range), then the
  /// current-frame capability the kind dispatch actually has.
  ///
  /// The toolbar used to keep its OWN switch, and it disagreed with the
  /// dispatch in both directions: it did not know the selection rungs
  /// (the S-row range #16 just taught the verb), and its `_ => true` arm
  /// lit the button on folder/adjustment/transition rows whose dispatch
  /// is a documented no-op — the #18 lie, one pill over.
  bool get canCreateInstance {
    if (canCreateInstanceForSelection) {
      return true;
    }
    final layer = _session.activeLayer;
    if (layer == null || !_session.hasActiveNonNegativeCell) {
      return false;
    }
    return switch (layer.kind) {
      LayerKind.se => _session.canCreateDrawingAtCurrentFrame,
      LayerKind.folder || LayerKind.adjustment || LayerKind.transition => false,
      _ => true,
    };
  }

  /// 🚨★★★I-9: whether the ACTIVE CELL already holds something.
  ///
  /// 유저 확정 2026-08-29 (I-9-Q2 = `all-kinds`): 「빈 칸 더블클릭 = 만들기」
  /// on EVERY row kind, each through the create verb it already has. So one
  /// gesture carries two meanings, and this is the fork: an empty cell
  /// CREATES ([createActiveInstance]), a filled one OPENS its editor.
  ///
  /// ⚠️Deliberately NOT [canCreateInstance] and not `!canCreate…`. Those
  /// ask 「is there room to make one」, which on a drawing row is true on a
  /// FILLED cell too (an exposure can always be cut). This asks the only
  /// question the fork needs: 「is something here」.
  ///
  /// The switch is exhaustive on purpose — a new [LayerKind] stops the
  /// compiler here rather than silently landing in a default arm, which is
  /// the guard that keeps this and [createActiveInstance] from drifting.
  bool get activeCellHoldsAnInstance {
    final layer = _session.activeLayer;
    if (layer == null || !_session.hasActiveNonNegativeCell) {
      // No cell at all is not an empty cell: there is nowhere to create.
      return true;
    }
    final frameIndex = _session.timelineController.currentFrameIndex;
    return switch (layer.kind) {
      LayerKind.camera =>
        _session.activeCutOrNull?.camera.keyframeAt(frameIndex) != null,
      LayerKind.instruction =>
        _session.instructionSpanAt(layer.id, frameIndex) != null,
      // ⛔Read-only inside a cut and nothing to author on a row that holds
      // no cel of its own: reporting FULL keeps the fork from offering a
      // creation their own verbs already refuse.
      LayerKind.transition || LayerKind.folder || LayerKind.adjustment => true,
      LayerKind.se ||
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.image ||
      LayerKind.text => _session.selectedFrame != null,
    };
  }

  /// The SELECTION rungs of [canCreateInstance], alone — the panel-shared
  /// half (B8). [createInstancesForSelection] is their dispatch, rung for
  /// rung; the storyboard's toolbar context reads THIS and then asks its
  /// own standing row, where the timeline falls to the active layer.
  bool get canCreateInstanceForSelection {
    final trackRange = _session.trackFrameRangeSelection.value;
    if (trackRange != null &&
        _session._trackSe.trackSeCreationGaps(trackRange).isNotEmpty) {
      return true;
    }
    if (_session._laneVerbs.laneVerbRange != null) {
      return true;
    }
    return _session.frameRangeSelection.value != null;
  }

  /// 🚨T25 — whether the CELL under the playhead has an instance editor.
  ///
  /// ⚠️Kind-aware, because 「인스턴스」 is not one thing: a drawing cell's is
  /// its NAME, a camera or direction cell's is the key/event dialog, an SE
  /// cell's is the entry — or the creation of one. This lived in the
  /// toolbar as a private getter while the button was hard-wired to cells;
  /// [editInstanceSubject] asked [_session.canRenameFrameAtCurrentFrame] instead, and
  /// the two disagreed for every non-drawing kind. The button stayed lit and
  /// the press did nothing, which is the worst of the three possible
  /// answers. One question, one getter.
  ///
  /// ⛔The HOST's answer is deliberately not folded in: the storyboard's
  /// standing row is separate state from its drawing target (유저
  /// 2026-07-27), so no session getter can see it.
  bool get canEditCellInstanceAtCurrentFrame {
    // A live band CLAIMS this press exactly as it claims Delete's — the
    // two are documented as ONE ladder ([editInstanceSubject]), so a band
    // that leaves Delete with nothing must not leave Rename pointed at
    // the active row instead. There is no selection-wide rename to route
    // to, so a claiming band whose rows hold no editable block simply
    // ends the ladder.
    if (_session.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _session.activeLayer;
    if (layer == null) {
      return false;
    }
    // Standing on a LANE row, the instance is that lane's KEY — which the
    // owning layer's kind cannot answer.
    if (_session.canNameLaneKeys) {
      return true;
    }
    return switch (layer.kind) {
      LayerKind.camera ||
      LayerKind.instruction => _session.hasActiveNonNegativeCell,
      LayerKind.se =>
        _session.selectedFrame != null ||
            _session.canCreateDrawingAtCurrentFrame,
      _ => _session.canRenameFrameAtCurrentFrame,
    };
  }

  /// 🚨T25 — WHAT the one Edit Instance button would rename right now.
  ///
  /// 유저 확정 2026-08-14: 「인스턴스 편집 버튼도 공통버튼으로 이동. 그래서
  /// **선택범위 통해 동사통일화** 가능하게.」
  ///
  /// ★Deliberately the SAME ladder as [_session.deleteSubject], in the same order and
  /// for the same reason. Two shared-pill verbs that both ask 「지금 무엇이
  /// 선택됐나」 and answer it differently would be a rule the user has to
  /// hold two versions of.
  ///
  /// ⚠️Where the two DIFFER is only in the predicate each rung uses:
  /// deleting asks what is deletable, renaming asks what is renameable, and
  /// those are not the same set (a camera row selects and renames but does
  /// not delete).
  EditInstanceSubject get editInstanceSubject =>
      editInstanceSubjectFor(cutsAreThisPanels: true);

  /// [editInstanceSubject], asked of a PANEL.
  ///
  /// 🚨R5q1 (유저 2026-08-25, 답 1번): 「삭제·편집도 패널을 따라 대상을
  /// 바꾼다 — 스토리보드에서는 스토리보드의 것을, 타임라인에서는 타임라인의
  /// 것을 지운다」, matching the law D28 already gave 커서·코마·＋.
  ///
  /// ⚠️This narrows ⑰ (2026-08-12), which said the verb asks WHAT IS
  /// SELECTED and never which button was pressed. It still does — what the
  /// panel decides is which selections are ITS nouns, and CUTS are the
  /// storyboard's. The two later rulings (D28, then this) win on the
  /// repo's own tie-break: 확정이 둘이면 나중 것이 이긴다.
  EditInstanceSubject editInstanceSubjectFor({
    required bool cutsAreThisPanels,
  }) {
    if (cutsAreThisPanels && _session.trackFrameRangeSelection.value != null) {
      return EditInstanceSubject.cuts;
    }
    if (_session.renameableSelectedLayerIds().isNotEmpty) {
      return EditInstanceSubject.layers;
    }
    return canEditCellInstanceAtCurrentFrame
        ? EditInstanceSubject.cells
        : EditInstanceSubject.nothing;
  }
}
