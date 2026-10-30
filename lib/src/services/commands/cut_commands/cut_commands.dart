part of '../cut_command_coordinator.dart';

/// THE CUT COMMANDS — creating, naming, resizing, reordering, duplicating
/// and deleting a cut, its note, thumbnail frame and duration drag — as
/// their own object. Each is a command over the repository, recorded in
/// history; the coordinator stays the facade that names them.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: the repository, the
/// history manager and the cut lookup shared, nothing else. It reaches
/// the coordinator through `_coordinator`.
class _CutCommands {
  _CutCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  void createCut({
    required TrackId trackId,
    CanvasSize? canvasSize,
    // #18 — an EXPLICIT landing (gap parking, range selection): the index
    // to insert at, the walk-in distance into the gap as the new cut's
    // own leading gap, and an optional duration (a range names its own
    // length, the way the transition span's selection does). Null keeps
    // the classic anchor: right of the active cut, else the track's end.
    ({int? index, int leadingGapFrames, int? duration})? placement,
    CutId? cutId,
    String? name,
  }) => _coordinator.historyManager.execute(
    createCutCommand(
      trackId: trackId,
      canvasSize: canvasSize,
      placement: placement,
      cutId: cutId,
      name: name,
    ),
  );

  /// The command [createCut] runs, not run: its cut is the cut it makes.
  /// [cutId] names that cut ahead — the conte's next cut is drawn into
  /// before it exists (H44). [name] is the one the new cut window gave it
  /// (I-100); none takes the one where it lands ([nextCutNameAfter]).
  CreateCutCommand createCutCommand({
    required TrackId trackId,
    CanvasSize? canvasSize,
    ({int? index, int leadingGapFrames, int? duration})? placement,
    CutId? cutId,
    String? name,
  }) {
    final project = _coordinator.repository.requireProject();
    final anchor = placement == null
        ? _insertionAnchorFor(project, trackId)
        : (
            index: placement.index,
            referenceName: _referenceNameAt(project, trackId, placement.index),
          );
    return CreateCutCommand(
      repository: _coordinator.repository,
      editingSession: _coordinator.editingSession,
      trackId: trackId,
      // The run's own id, unless one was named ahead ([mintCutId] says why
      // not the project's first free one). ↩️A plan stood between, which
      // named a layer id as well — for the blank layer A a new cut was
      // born with. A new cut is bare now (F-211), and its id is all there
      // is to name.
      cutId: cutId ?? mintCutId(),
      name: name ?? nextCutNameAfter(project, anchor.referenceName),
      index: anchor.index,
      leadingGapFrames: placement?.leadingGapFrames ?? 0,
      duration: placement?.duration,
      canvasSize: canvasSize ?? defaultCutCanvasSize,
    );
  }

  /// The name an EXPLICIT landing counts from: the cut in front of it —
  /// the same "to the right of" reading the classic anchor gives.
  String? _referenceNameAt(Project project, TrackId trackId, int? index) {
    for (final track in project.tracks) {
      if (track.id != trackId) {
        continue;
      }
      if (track.cuts.isEmpty) {
        return null;
      }
      if (index == null || index > track.cuts.length) {
        return track.cuts.last.name;
      }
      return index == 0 ? null : track.cuts[index - 1].name;
    }
    return null;
  }

  /// Where a new cut lands on [trackId], and which name it counts from: to
  /// the RIGHT of the active cut when the active cut is on this track (the
  /// user's working position), the track's end otherwise.
  ({int? index, String? referenceName}) _insertionAnchorFor(
    Project project,
    TrackId trackId,
  ) {
    for (final track in project.tracks) {
      if (track.id != trackId) {
        continue;
      }
      final activeIndex = track.cuts.indexWhere(
        (cut) => cut.id == _coordinator.editingSession.activeCutId,
      );
      if (activeIndex != -1) {
        return (
          index: activeIndex + 1,
          referenceName: track.cuts[activeIndex].name,
        );
      }
      return (
        index: null,
        referenceName: track.cuts.isEmpty ? null : track.cuts.last.name,
      );
    }
    return (index: null, referenceName: null);
  }

  /// The name a new cut takes when it lands after [referenceName].
  ///
  /// The cut NAME is the cut number (UI-R7 #3: bare numbers, the sheet
  /// convention) — a free string the user may rename to anything, so this
  /// never computes a number, it OFFERS candidates and takes the first one
  /// nobody holds:
  ///
  /// 1. the reference's trailing digits, incremented (`39A` → `40`);
  /// 2. failing that — which is exactly the moment a cut is being slipped
  ///    BETWEEN two numbered ones — a letter suffix on the reference
  ///    (`39` → `39A` → `39B`), the split-cut convention Japanese sheets
  ///    use and Storyboard Pro's naming preferences generate;
  /// 3. past `Z`, the suffix takes a number (`39Z` → `39A1`).
  ///
  /// Offering candidates rather than computing is what keeps hand-written
  /// names (`39ハ`, `オープニング`) from breaking it: a name the rule cannot
  /// read is simply not a candidate it would have proposed.
  static String nextCutNameAfter(Project project, String? referenceName) {
    final taken = <String>{
      for (final track in project.tracks)
        for (final cut in track.cuts) cut.name.trim(),
    };

    final reference = referenceName?.trim() ?? '';

    // The number is the reference's FIRST digit run; whatever trails it is
    // a split marker, not part of the count ('39A' counts as 39).
    final number = RegExp(r'^(\D*)(\d+)').firstMatch(reference);
    if (number != null) {
      final candidate = '${number.group(1)!}${int.parse(number.group(2)!) + 1}';
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }

    if (reference.isEmpty) {
      // Nothing to hang a suffix on (an empty track): count up from 1.
      for (var next = 1; ; next += 1) {
        final candidate = '$next';
        if (!taken.contains(candidate)) {
          return candidate;
        }
      }
    }

    // The number is spoken for, so this is a split: suffix the reference.
    // A reference that already carries a single-letter suffix continues
    // ITS series ('39A' → '39B') rather than growing a second one.
    final suffixed = RegExp(r'^(.*?)([A-Za-z])$').firstMatch(reference);
    final root = suffixed?.group(1) ?? reference;
    final firstLetter = suffixed == null
        ? 0
        : suffixed.group(2)!.toUpperCase().codeUnitAt(0) - 64;

    for (var letter = firstLetter; letter < 26; letter += 1) {
      final candidate = '$root${String.fromCharCode(65 + letter)}';
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }
    // Past Z the suffix takes a number, the way Storyboard Pro's Auto
    // suffix cycles into numbered variants.
    for (var round = 1; ; round += 1) {
      for (var letter = 0; letter < 26; letter += 1) {
        final candidate = '$root${String.fromCharCode(65 + letter)}$round';
        if (!taken.contains(candidate)) {
          return candidate;
        }
      }
    }
  }

  /// [cutId]'s canvas at [canvasSize], the picture kept to [anchor] — one
  /// way of saying [placeCutCanvas]'s offset.
  void resizeCutCanvas({
    required CutId cutId,
    required CanvasSize canvasSize,
    CanvasResizeAnchor anchor = CanvasResizeAnchor.topLeft,
  }) {
    _requirePositive(canvasSize);
    placeCutCanvas(
      cutId: cutId,
      canvasSize: canvasSize,
      contentOffset: _anchored(cutId, canvasSize, anchor),
    );
  }

  /// What [resizeCutCanvas] will make of the pictures kept in files, worked
  /// out ahead ([placeCutCanvasAhead]).
  Future<void> resizeCutCanvasAhead({
    required CutId cutId,
    required CanvasSize canvasSize,
    CanvasResizeAnchor anchor = CanvasResizeAnchor.topLeft,
    void Function(double done)? report,
  }) => placeCutCanvasAhead(
    cutId: cutId,
    canvasSize: canvasSize,
    contentOffset: _anchored(cutId, canvasSize, anchor),
    report: report,
  );

  ({double dx, double dy}) _anchored(
    CutId cutId,
    CanvasSize canvasSize,
    CanvasResizeAnchor anchor,
  ) => anchor.contentOffset(
    from: _coordinator._requireCut(cutId).canvasSize,
    to: canvasSize,
  );

  /// [cutId]'s canvas at [canvasSize], the picture moved by [contentOffset]
  /// ([ResizeCutCanvasCommand.contentOffset]) — no step when neither
  /// changes anything.
  ///
  /// ⚠️The offset is part of the question: a canvas whose edges were
  /// dragged can keep its size and still move the picture.
  void placeCutCanvas({
    required CutId cutId,
    required CanvasSize canvasSize,
    required ({double dx, double dy}) contentOffset,
  }) {
    _requirePositive(canvasSize);
    _coordinator._executeIfChanged(
      subject: _coordinator._requireCut(cutId),
      value: _placing(canvasSize, contentOffset),
      read: _placed,
      command: (_) => _resize(cutId, canvasSize, contentOffset),
    );
  }

  /// What [placeCutCanvas] will make of the cut's pictures, worked out ahead
  /// — the very work its redo has ahead of it
  /// ([ResizeCutCanvasCommand.workAhead]): for a wait window to hold up
  /// while it runs, hearing through [report] how much is done — nothing
  /// where the place changes nothing, as no step is taken there.
  Future<void> placeCutCanvasAhead({
    required CutId cutId,
    required CanvasSize canvasSize,
    required ({double dx, double dy}) contentOffset,
    void Function(double done)? report,
  }) async {
    final placing = _placing(canvasSize, contentOffset);
    if (_placed(_coordinator._requireCut(cutId)) == placing) {
      return;
    }
    final ahead = _resize(cutId, canvasSize, contentOffset).workAhead(
      undo: false,
    );
    await ahead?.run(report ?? (_) {});
  }

  /// The step [placeCutCanvas] takes — and asks what it works out ahead.
  ResizeCutCanvasCommand _resize(
    CutId cutId,
    CanvasSize canvasSize,
    ({double dx, double dy}) contentOffset,
  ) => ResizeCutCanvasCommand(
    repository: _coordinator.repository,
    cutId: cutId,
    canvasSize: canvasSize,
    contentOffset: contentOffset,
    brushFrameStore: _coordinator.brushFrameStore,
  );

  /// What [placeCutCanvas] asks of a cut, in whole pixels — and [_placed],
  /// what a cut already answers: the step is taken where the two differ.
  static _CanvasPlace _placing(
    CanvasSize canvasSize,
    ({double dx, double dy}) contentOffset,
  ) => (
    size: canvasSize,
    dx: contentOffset.dx.roundToDouble(),
    dy: contentOffset.dy.roundToDouble(),
  );

  static _CanvasPlace _placed(Cut cut) =>
      (size: cut.canvasSize, dx: 0.0, dy: 0.0);

  static void _requirePositive(CanvasSize canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      throw ArgumentError.value(
        canvasSize,
        'canvasSize',
        'Canvas size must be positive.',
      );
    }
  }

  /// Names each cut of [names] as ONE undo step — the rename's one body,
  /// which 자동 이름 지정 (I-18) hands a whole run of cuts. A cut already
  /// wearing its name adds nothing, and a press that changes nothing adds
  /// no step ([HistoryManager.executeAsOneStep]).
  void renameCuts(Map<CutId, String> names) =>
      _coordinator.historyManager.executeAsOneStep('Rename cuts', [
        for (final MapEntry(key: cutId, value: name) in names.entries)
          ?_renameOf(cutId, name),
      ]);

  /// [cutId]'s scene, as ONE undo step — none where it is already that.
  void setCutScene({required CutId cutId, required String scene}) =>
      _coordinator.historyManager.executeAsOneStep('Set cut scene', [
        ?_sceneOf(cutId, scene),
      ]);

  /// [cutId] named [name] — and, from the cut rename window (F-291), put in
  /// scene [scene] — as ONE undo step, each only where it changed.
  void nameCut({required CutId cutId, required String name, String? scene}) =>
      _coordinator.historyManager.executeAsOneStep('Name cut', [
        ?_renameOf(cutId, name),
        if (scene != null) ?_sceneOf(cutId, scene),
      ]);

  Command? _renameOf(CutId cutId, String name) =>
      _coordinator._requireCut(cutId).name == name
      ? null
      : RenameCutCommand(
          repository: _coordinator.repository,
          cutId: cutId,
          newName: name,
        );

  Command? _sceneOf(CutId cutId, String scene) =>
      _coordinator._requireCut(cutId).metadata.scene == scene
      ? null
      : UpdateCutSceneCommand(
          repository: _coordinator.repository,
          cutId: cutId,
          scene: scene,
        );

  /// Commits a storyboard edge drag as one undoable step: durations (end
  /// trims) and leading gaps (start slides / gap consumption) together.
  /// The fade re-anchor rewrites are gone (R4: the V lanes' keys are TRACK
  /// data on the global axis — a trim moves none of them). The transition
  /// row's spans ride their front cut inside the command itself
  /// ([UpdateCutDurationsCommand]).
  void commitCutDurationDrag({
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
    Map<CutId, int> beforeGaps = const {},
    Map<CutId, int> afterGaps = const {},
  }) {
    _coordinator.historyManager.execute(
      UpdateCutDurationsCommand(
        repository: _coordinator.repository,
        before: beforeDurations,
        after: afterDurations,
        beforeGaps: beforeGaps,
        afterGaps: afterGaps,
      ),
    );
  }

  void updateCutNote({
    required CutId cutId,
    required int page,
    required String note,
  }) => _coordinator._executeIfChanged(
    subject: _coordinator._requireCut(cutId),
    value: note,
    read: (cut) => cut.metadata.noteOf(page),
    command: (_) => UpdateCutNoteCommand(
      repository: _coordinator.repository,
      cutId: cutId,
      page: page,
      note: note,
    ),
  );

  /// 컷 설정: each stage of [names] named on [cutIds] and their 겸용
  /// siblings, as ONE undo step — the stages it does not name keep each
  /// cut's own, and a stage every cut already has so is no step at all —
  /// with, where the window was saved with them, the folds it opens on
  /// ([openFolds], F-291-Q4: each of [cutIds]' own).
  void saveCutSettings({
    required List<CutId> cutIds,
    required Map<LayerMark, String> names,
    Set<LayerProcess>? openFolds,
  }) {
    final project = _coordinator.repository.requireProject();
    final cuts = [
      for (final cutId in LinkedCutFieldCommand.linkedCutsOf(project, cutIds))
        requireCut(project, cutId),
    ];
    _coordinator.historyManager.executeAsOneStep('Set cut staff', [
      for (final MapEntry(key: mark, value: name) in names.entries)
        if (cuts.any((cut) => cut.metadata.staffNameFor(mark) != name))
          UpdateCutStaffNameCommand(
            repository: _coordinator.repository,
            cutIds: cutIds,
            mark: mark,
            name: name,
          ),
      if (openFolds != null &&
          cutIds.any(
            (cutId) => !setEquals(
              requireCut(project, cutId).metadata.openStaffFolds,
              openFolds,
            ),
          ))
        UpdateCutStaffFoldsCommand(
          repository: _coordinator.repository,
          cutIds: cutIds,
          open: openFolds,
        ),
    ]);
  }

  /// The 타임시트 서식 window's save: the work's sheet format and the paper
  /// of the cut the sheet shows ([cutId]; none in the gap) — each only if
  /// it changed, ONE undo step together ([HistoryManager.runAsOneStep]).
  void setTimesheetFormat({
    required TimesheetInfo info,
    CutId? cutId,
    TimesheetSheetKind? kind,
  }) {
    final repository = _coordinator.repository;
    final history = _coordinator.historyManager;
    final project = repository.requireProject();
    history.runAsOneStep('Set timesheet format', () {
      if (project.timesheetInfo != info) {
        history.execute(
          UpdateTimesheetInfoCommand(repository: repository, info: info),
        );
      }
      if (cutId != null &&
          kind != null &&
          LinkedCutFieldCommand.linkedCutsOf(project, [cutId]).any(
            (id) => requireCut(project, id).metadata.sheetKind != kind,
          )) {
        history.execute(
          UpdateCutSheetKindCommand(
            repository: repository,
            cutIds: [cutId],
            kind: kind,
          ),
        );
      }
    });
  }

  /// The 콘티 용지 서식 window's save: the work's format and, where one was
  /// picked, the room [cutIds]' conte cells take ([cameraRoom] — its `to`
  /// null for the format's, I-82-Q1), on the 겸용 pair as one — each only
  /// if it changed, ONE undo step together.
  void setConteFormat({
    required TimesheetInfo info,
    required List<CutId> cutIds,
    ({ConteCameraRoom? to})? cameraRoom,
  }) {
    final repository = _coordinator.repository;
    final history = _coordinator.historyManager;
    final project = repository.requireProject();
    history.runAsOneStep('Set conte format', () {
      if (project.timesheetInfo != info) {
        history.execute(
          UpdateTimesheetInfoCommand(repository: repository, info: info),
        );
      }
      if (cameraRoom case (:final to)
          when LinkedCutFieldCommand.linkedCutsOf(project, cutIds).any(
            (id) => requireCut(project, id).metadata.conteCameraRoom != to,
          )) {
        history.execute(
          UpdateCutConteCameraRoomCommand(
            repository: repository,
            cutIds: cutIds,
            room: to,
          ),
        );
      }
    });
  }

  /// Sets the 색 라벨 of [cutIds] — and of each one's 겸용 siblings — as ONE
  /// undo step ([UpdateCutMarkCommand]); nothing at all when every one of
  /// them already wears [mark].
  void setCutMark({required List<CutId> cutIds, required LayerMark mark}) {
    final project = _coordinator.repository.requireProject();
    if (LinkedCutFieldCommand.linkedCutsOf(project, cutIds).every(
      (cutId) => requireCut(project, cutId).metadata.mark == mark,
    )) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateCutMarkCommand(
        repository: _coordinator.repository,
        cutIds: cutIds,
        mark: mark,
      ),
    );
  }

  /// Commits a move drag's REORDER as one undo step: the track's new
  /// sequence plus the position gaps its cuts took over (the gaps stay
  /// with the position, R5 #13 — each cut carries its own leading gap, so
  /// a bare permutation would let the gaps travel with the cuts). On a
  /// packed track the gaps map is empty and the step is the order alone.
  /// A drag that reached into a neighbour commits here (a run may carry
  /// several cuts across at once).
  void commitCutMoveReorder({
    required TrackId trackId,
    required List<CutId> order,
    required Map<CutId, int> beforeGaps,
    required Map<CutId, int> afterGaps,
  }) {
    _coordinator.historyManager.executeAsOneStep('Move cut', [
      SetCutOrderCommand(
        repository: _coordinator.repository,
        trackId: trackId,
        order: order,
      ),
      if (afterGaps.isNotEmpty)
        UpdateCutDurationsCommand(
          repository: _coordinator.repository,
          before: const {},
          after: const {},
          beforeGaps: beforeGaps,
          afterGaps: afterGaps,
        ),
    ]);
  }

  /// R28 #14: deleting the LAST cut leaves the track empty rather than
  /// conjuring a replacement.
  ///
  /// "컷도 1개도 없는 상황 허용" — the empty track is the same state the
  /// editor already shows over a storyboard GAP (no active cut): the
  /// canvas paints its blank paper and every `requireActiveCut` consumer
  /// is behind a guard. Auto-replacing meant a delete could not actually
  /// clear the track, and the replacement was indistinguishable from a
  /// real cut in the undo stack.
  void deleteCut({required CutId cutId}) {
    _coordinator.historyManager.execute(
      DeleteCutCommand(
        repository: _coordinator.repository,
        editingSession: _coordinator.editingSession,
        cutId: cutId,
        brushFrameStore: _coordinator.brushFrameStore,
      ),
    );
  }

  /// Deletes a batch of cuts as ONE undo step; emptying the track is
  /// allowed (R28 #14).
  void deleteCuts({required List<CutId> cutIds}) {
    _coordinator.historyManager.executeAsOneStep('Delete cuts', [
      for (final cutId in cutIds)
        DeleteCutCommand(
          repository: _coordinator.repository,
          editingSession: _coordinator.editingSession,
          cutId: cutId,
          brushFrameStore: _coordinator.brushFrameStore,
        ),
    ]);
  }

  /// Copies [sourceCutId] into [targetTrackId] at [index] — the track's end
  /// when null.
  DuplicatedCut duplicateCut({
    required CutId sourceCutId,
    required TrackId targetTrackId,
    String? newName,
    int? index,
  }) {
    final project = _coordinator.repository.requireProject();
    final sourceCut = _coordinator._requireCut(sourceCutId);
    final plan = planDuplicateCutCommandInput(
      project: project,
      sourceCut: sourceCut,
    );

    _coordinator.historyManager.execute(
      DuplicateCutCommand(
        repository: _coordinator.repository,
        editingSession: _coordinator.editingSession,
        sourceCutId: sourceCutId,
        targetTrackId: targetTrackId,
        newCutId: plan.newCutId,
        newName: newName ?? '${sourceCut.name} Copy',
        layerIdMap: plan.layerIdMap,
        frameIdMap: plan.frameIdMap,
        index: index,
      ),
    );
    return (
      cutId: plan.newCutId,
      rows: plan.layerIdMap,
      minted: plan.frameIdMap,
    );
  }
}

/// A cut's canvas size and how far its picture is moved on it, in whole
/// pixels ([_CutCommands.placeCutCanvas]).
typedef _CanvasPlace = ({CanvasSize size, double dx, double dy});
