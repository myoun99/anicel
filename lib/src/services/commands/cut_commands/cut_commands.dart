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
    String? name,
    CanvasSize? canvasSize,
    // #18 — an EXPLICIT landing (gap parking, range selection): the index
    // to insert at, the walk-in distance into the gap as the new cut's
    // own leading gap, and an optional duration (a range names its own
    // length, the way the transition span's selection does). Null keeps
    // the classic anchor: right of the active cut, else the track's end.
    ({int? index, int leadingGapFrames, int? duration})? placement,
  }) {
    final project = _coordinator.repository.requireProject();
    final plan = planCreateCutCommandInput(project);
    final anchor = placement == null
        ? _insertionAnchorFor(project, trackId)
        : (
            index: placement.index,
            referenceName: _referenceNameAt(project, trackId, placement.index),
          );

    _coordinator.historyManager.execute(
      CreateCutCommand(
        repository: _coordinator.repository,
        editingSession: _coordinator.editingSession,
        trackId: trackId,
        cutId: plan.cutId,
        layerId: plan.layerId,
        name: name ?? nextCutNameAfter(project, anchor.referenceName),
        index: anchor.index,
        leadingGapFrames: placement?.leadingGapFrames ?? 0,
        duration: placement?.duration,
        canvasSize: canvasSize ?? defaultCutCanvasSize,
      ),
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

  void resizeCutCanvas({
    required CutId cutId,
    required CanvasSize canvasSize,
    CanvasResizeAnchor anchor = CanvasResizeAnchor.topLeft,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      throw ArgumentError.value(
        canvasSize,
        'canvasSize',
        'Canvas size must be positive.',
      );
    }

    _coordinator._executeIfChanged(
      subject: _coordinator._requireCut(cutId),
      value: canvasSize,
      read: (cut) => cut.canvasSize,
      command: (_) => ResizeCutCanvasCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        canvasSize: canvasSize,
        anchor: anchor,
        brushFrameStore: _coordinator.brushFrameStore,
      ),
    );
  }

  void renameCut({required CutId cutId, required String newName}) {
    _coordinator.historyManager.execute(
      RenameCutCommand(
        repository: _coordinator.repository,
        cutId: cutId,
        newName: newName,
      ),
    );
  }

  /// Commits a storyboard edge drag as one undoable step: durations (end
  /// trims) and leading gaps (start slides / gap consumption) together.
  /// The fade re-anchor rewrites are gone (R4: fade keys are TRACK data
  /// on the global axis — a trim moves none of them).
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

  void updateCutNote({required CutId cutId, required String note}) =>
      _coordinator._executeIfChanged(
        subject: _coordinator._requireCut(cutId),
        value: note,
        read: (cut) => cut.metadata.note,
        command: (_) => UpdateCutNoteCommand(
          repository: _coordinator.repository,
          cutId: cutId,
          note: note,
        ),
      );

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

  /// Pins the storyboard thumbnail to a cut-local frame (null = back to the
  /// first frame); one undo step.
  void updateCutThumbnailFrame({
    required CutId cutId,
    required int? frameIndex,
  }) => _coordinator._executeIfChanged(
    subject: _coordinator._requireCut(cutId),
    value: frameIndex,
    read: (cut) => cut.metadata.thumbnailFrameIndex,
    command: (_) => UpdateCutThumbnailFrameCommand(
      repository: _coordinator.repository,
      cutId: cutId,
      frameIndex: frameIndex,
    ),
  );

  /// Moves ONE cut to [newIndex] — the left/right nudge buttons' form of
  /// the order edit, stated as the resulting order so both forms share a
  /// command.
  void reorderCut({
    required TrackId trackId,
    required CutId cutId,
    required int newIndex,
  }) {
    final cuts = [
      for (final cut in _coordinator._tracks._requireTrack(trackId).cuts)
        cut.id,
    ];
    final oldIndex = cuts.indexOf(cutId);
    if (oldIndex == -1) {
      throw StateError('Cut not found in track $trackId: $cutId');
    }
    cuts.insert(newIndex, cuts.removeAt(oldIndex));
    setCutOrder(trackId: trackId, order: cuts);
  }

  /// Resequences a whole track — what a cut drag that reached into a
  /// neighbour commits (a run may carry several cuts across at once).
  void setCutOrder({required TrackId trackId, required List<CutId> order}) {
    _coordinator.historyManager.execute(
      SetCutOrderCommand(
        repository: _coordinator.repository,
        trackId: trackId,
        order: order,
      ),
    );
  }

  /// Commits a move drag's REORDER as one undo step: the track's new
  /// sequence plus the position gaps its cuts took over (the gaps stay
  /// with the position, R5 #13 — each cut carries its own leading gap, so
  /// a bare permutation would let the gaps travel with the cuts). On a
  /// packed track the gaps map is empty and this stays a plain
  /// [setCutOrder].
  void commitCutMoveReorder({
    required TrackId trackId,
    required List<CutId> order,
    required Map<CutId, int> beforeGaps,
    required Map<CutId, int> afterGaps,
  }) {
    if (afterGaps.isEmpty) {
      setCutOrder(trackId: trackId, order: order);
      return;
    }
    _coordinator.historyManager.execute(
      CompositeCommand(
        description: 'Move cut',
        commands: [
          SetCutOrderCommand(
            repository: _coordinator.repository,
            trackId: trackId,
            order: order,
          ),
          UpdateCutDurationsCommand(
            repository: _coordinator.repository,
            before: const {},
            after: const {},
            beforeGaps: beforeGaps,
            afterGaps: afterGaps,
          ),
        ],
      ),
    );
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
    if (cutIds.isEmpty) {
      return;
    }
    if (cutIds.length == 1) {
      deleteCut(cutId: cutIds.single);
      return;
    }

    _coordinator.historyManager.execute(
      CompositeCommand(
        description: 'Delete cuts',
        commands: [
          for (final cutId in cutIds)
            DeleteCutCommand(
              repository: _coordinator.repository,
              editingSession: _coordinator.editingSession,
              cutId: cutId,
              brushFrameStore: _coordinator.brushFrameStore,
            ),
        ],
      ),
    );
  }

  DuplicatedCut duplicateCut({
    required CutId sourceCutId,
    required TrackId targetTrackId,
    String? newName,
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
      ),
    );
    return (
      cutId: plan.newCutId,
      rows: plan.layerIdMap,
      minted: plan.frameIdMap,
    );
  }
}
