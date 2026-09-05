part of '../editor_session_manager.dart';

/// The TRANSITIONS — the spans a track carries between cuts, the display
/// layer they are drawn through, their instruction set and the warnings for
/// a cut edge that crosses one — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and eight
/// session members touched, `activeTrack` above all. It reaches the session
/// through `_session`.
class _Transitions {
  _Transitions(this._session);

  final EditorSessionManager _session;

  /// The active track's transition spans on the GLOBAL frame axis — the one
  /// reader for every surface that has to answer a transition question
  /// (the sheet's のりしろ, the cut view's read-only marks, the compositor's
  /// ramp). They are plain records so nobody downstream has to know a layer is
  /// behind them — start, length and the TERM'S MARK, which is what says
  /// whether the span moves both cuts or only its own.
  List<TransitionSpan> get activeTrackTransitionSpans => [
    for (final entry
        in _session.activeTrack.transitionLayer.instructions.entries)
      transitionSpanOf(entry),
  ];

  /// The track that owns [layerId] as its TRANSITION row, on any track.
  Track? trackTransitionOwner(LayerId layerId) {
    for (final track in _session._repository.requireProject().tracks) {
      if (track.transitionLayer.id == layerId) {
        return track;
      }
    }
    return null;
  }

  bool isTrackTransitionLayerId(LayerId layerId) =>
      trackTransitionOwner(layerId) != null;

  /// The track's TRANSITION row as a cut-local display clone — the camera
  /// section's read-only third row.
  ///
  /// 🚨 Unlike the SE clones this is a PROJECTION, not a window
  /// ([transitionMarkInCut]): a span that crosses this cut's boundary shows
  /// at its FULL length on the side it belongs to, because half a bowtie
  /// says nothing to whoever is reading the row. The clone therefore does
  /// NOT describe where the span really is — the global row does that, and
  /// the global row is the only one that may be edited.
  ///
  /// Cached on the same terms as the SE clones: same source layer + same
  /// window = the same instance back, so identity-keyed row memos hold.
  Layer get trackTransitionDisplayLayer {
    final source = _session.activeTrack.transitionLayer;
    final cutStart = _session.activeCutGlobalStartFrame;
    final duration = _session.activeCutOrNull?.duration ?? 0;
    final cached = _transitionDisplayClone;
    if (cached != null &&
        identical(cached.$1, source) &&
        cached.$2 == cutStart &&
        cached.$3 == duration) {
      return cached.$4;
    }
    final projected = SplayTreeMap<int, InstructionEvent>();
    // D26: the crossing answer is recorded under the PROJECTED key in the
    // same walk — the clone re-keys spans to cut-local starts, so a marker
    // bound by global key alone would miss or mis-mark projected blocks.
    final crossing = <int>{};
    for (final entry in source.instructions.entries) {
      final span = transitionSpanOf(entry);
      final mark = transitionMarkInCut(
        span: span,
        cutStart: cutStart,
        cutEnd: cutStart + duration,
      );
      if (mark == null) {
        continue;
      }
      projected[mark.start] = entry.value;
      if (oneSidedSpanCrossesOwnCut(
        span: span,
        cutStart: cutStart,
        cutEnd: cutStart + duration,
      )) {
        crossing.add(mark.start);
      }
    }
    final display = source.copyWith(instructions: projected);
    _transitionDisplayClone = (source, cutStart, duration, display, crossing);
    return display;
  }

  (Layer, int, int, Layer, Set<int>)? _transitionDisplayClone;

  /// D26: the crossing-fade warning for the CUT-VIEW transition row, by
  /// the display clone's projected local start key. The answer is computed
  /// in [trackTransitionDisplayLayer]'s own projection walk with the SAME
  /// predicate the apply gate reads ([oneSidedSpanCrossesOwnCut]) — the
  /// T25 one-sentence law: the refusal and the warning cannot drift.
  String? transitionCrossingWarningInCutAt(int projectedStartKey) {
    // Resolve the clone first so the cache always answers for the active
    // cut the row is actually showing.
    trackTransitionDisplayLayer;
    return (_transitionDisplayClone?.$5.contains(projectedStartKey) ?? false)
        ? AppText.strings.tlTransitionCrossingWarning
        : null;
  }

  /// D31 × D26: the transition row the printed SHEET consumes — the
  /// cut-view projection MINUS the spans the apply gate refuses (the
  /// same crossing set the warning reads, so refusal, warning and the
  /// sheet cannot drift). A crossing one-sided fade is 미적용: it fires
  /// nowhere and contributes no のりしろ, and a sheet that printed it
  /// would have material shot for a fade the compositor never runs. The
  /// cut-view ROW keeps drawing it — the red warning needs the block to
  /// sit on; the sheet has no warning channel, so it prints only what
  /// applies.
  Layer get trackTransitionSheetLayer {
    final display = trackTransitionDisplayLayer;
    final crossing = _transitionDisplayClone?.$5 ?? const <int>{};
    if (crossing.isEmpty) {
      return display;
    }
    final applied = SplayTreeMap<int, InstructionEvent>();
    for (final entry in display.instructions.entries) {
      if (!crossing.contains(entry.key)) {
        applied[entry.key] = entry.value;
      }
    }
    return display.copyWith(instructions: applied);
  }

  /// D26: the same warning for the GLOBAL authoring row (the storyboard's
  /// transition row), by the span's global start key. Walks the cuts the
  /// storyboard's own way (gap, then duration) to find the owning cut; a
  /// gap-anchored fade has no owner, is already inert today, and stays
  /// quietly unmarked.
  String? transitionCrossingWarningAtGlobalKey(int globalStartKey) {
    final event =
        _session.activeTrack.transitionLayer.instructions[globalStartKey];
    if (event == null) {
      return null;
    }
    final span = transitionSpanOf(MapEntry(globalStartKey, event));
    if (transitionSidesOf(span.mark) == TransitionSides.both) {
      return null;
    }
    for (final placed in cutSpansOf(_session.activeTrack)) {
      if (oneSidedSpanOwnsCut(
        span: span,
        cutStart: placed.startFrame,
        cutEnd: placed.endFrame,
      )) {
        return oneSidedSpanCrossesOwnCut(
              span: span,
              cutStart: placed.startFrame,
              cutEnd: placed.endFrame,
            )
            ? AppText.strings.tlTransitionCrossingWarning
            : null;
      }
    }
    return null;
  }

  /// The terms a transition span may carry: F.I, F.O, W.I, W.O, O.L. The
  /// camera-work terms (PAN, T.U, …) stay on the cut's direction row.
  List<CameraInstructionDef> get transitionInstructionDefs => [
    for (final def in _session.cameraInstructionSet.defs)
      if (cameraInstructionIsTransition(def)) def,
  ];

  /// Whether a transition span can start at the playhead: there has to be a
  /// vocabulary to draw from and no span there already.
  ///
  /// The playhead is [_session.editingGlobalFrame] — the ONE track-global reader — and
  /// not "cut start + local index". A parked playhead sits in a GAP with no
  /// active cut, and a gap is a legitimate transition partner (a fade out to
  /// black, or the のりしろ an animator gets by opening a gap in front of the
  /// only cut they were given), so the arithmetic that needs a cut answers
  /// wrong in precisely the case this row exists for.
  /// 🚨★★ 유저 #17 (2026-08-15): 「스토리보드패널의 **트랜지션레이어**,
  /// 선택범위로 프레임생성누르면 **선택범위만큼 생성되는게 일반적인데 이
  /// 레이어만 다름.** 대체 왜? **왜 이렇게 규칙을 가끔가다 통일안하는거지?**」
  ///
  /// WHERE a new span starts and HOW LONG it is: the selection when the
  /// selection covers this row, the playhead and one frame otherwise. Null
  /// when there is nowhere to put one.
  ///
  /// ★One sentence, read by both the gate below and the verb under it (T25:
  /// 「버튼이 켜지는 근거와 눌렀을 때 도는 근거는 같은 문장 하나여야 한다.
  /// 둘이면 반드시 갈라진다」). The length hard-coded to 1 was this row's
  /// whole difference from every other row — everywhere else the count comes
  /// from the range, so this was a special case with no rule behind it.
  ///
  /// ⛔A long range is not refused when something is already in the way:
  /// [instructionMapWithEventAdded] clamps to the next span's start, so "the
  /// room ran out" answers with a shorter span, never with a lit button that
  /// does nothing.
  ({int startFrame, int length})? get transitionSpanCreationOrNull {
    if (transitionInstructionDefs.isEmpty) {
      return null;
    }
    final track = _session.activeTrack;
    final selection = _session.trackFrameRangeSelection.value;
    final overThisRow =
        selection != null &&
        selection.trackId == track.id &&
        selection.coversRow(LayerRowAddress(track.transitionLayer.id));
    final startFrame = overThisRow
        ? selection.startFrame
        : _session.editingGlobalFrame;
    final length = overThisRow ? selection.lengthFrames : 1;
    if (startFrame < 0 || length < 1) {
      return null;
    }
    final covering = instructionSpanCovering(
      track.transitionLayer.instructions,
      startFrame,
    );
    return covering == null ? (startFrame: startFrame, length: length) : null;
  }

  bool get canCreateTransitionSpanAtPlayhead =>
      transitionSpanCreationOrNull != null;

  /// Starts a transition span on the GLOBAL axis, where and as long as
  /// [transitionSpanCreationOrNull] says.
  ///
  /// Dialog-free like its direction-row twin (UI-R25 #2): it takes the first
  /// transition term and the Edit Instance dialog changes it afterwards. The
  /// grips own the length from then on — and a span only DOES anything once
  /// it has been dragged across a cut boundary, which is the rule the
  /// geometry enforces rather than this verb.
  void createTransitionSpanAtPlayhead() {
    final plan = transitionSpanCreationOrNull;
    if (plan == null) {
      return;
    }
    final track = _session.activeTrack;
    final before = track.transitionLayer;
    final next = instructionMapWithEventAdded(
      before.instructions,
      startIndex: plan.startFrame,
      event: InstructionEvent(
        instructionId: transitionInstructionDefs.first.id,
        length: plan.length,
      ),
    );
    if (next == null) {
      return;
    }
    _session._historyManager.execute(
      UpdateTrackTransitionLayerCommand(
        repository: _session._repository,
        trackId: track.id,
        before: before,
        after: before.copyWith(instructions: next),
        debugLabel: 'Add transition',
      ),
    );
    _transitionDisplayClone = null;
    _session._notifyChanged();
  }

  /// Replaces the whole transition span map in one undo step — the writer
  /// behind the edge grips and the edit dialog.
  void updateTransitionInstructions(
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit transition',
  }) {
    final track = _session.activeTrack;
    final before = track.transitionLayer;
    _session._historyManager.execute(
      UpdateTrackTransitionLayerCommand(
        repository: _session._repository,
        trackId: track.id,
        before: before,
        after: before.copyWith(
          instructions: SplayTreeMap<int, InstructionEvent>.from(instructions),
        ),
        debugLabel: description,
      ),
    );
    _transitionDisplayClone = null;
    _session._notifyChanged();
  }

  /// The vocabulary a transition dialog picks from — the same set object the
  /// picker already takes, holding only the 場面転換 terms. The vocabulary
  /// EDITOR is not offered from here: it commits the whole set, so editing a
  /// filtered copy would delete every camera-work term.
  CameraInstructionSet get transitionInstructionSet =>
      CameraInstructionSet(defs: transitionInstructionDefs);

  /// The transition span covering [globalFrame] on the active track, as
  /// (startIndex, event); null on an empty cell. Frames are GLOBAL — this
  /// row's axis is the track's.
  MapEntry<int, InstructionEvent>? transitionSpanAt(int globalFrame) =>
      instructionSpanCovering(
        _session.activeTrack.transitionLayer.instructions,
        globalFrame,
      );

  /// Replaces the event of the span covering [globalFrame], keeping its start
  /// and length (the grips own those). No-op on an empty cell — creation is
  /// [createTransitionSpanAtPlayhead]'s job, so the dialog can never move a
  /// span by re-picking its term.
  void replaceTransitionEventAt(int globalFrame, InstructionEvent event) {
    final covering = transitionSpanAt(globalFrame);
    if (covering == null) {
      return;
    }
    final next = instructionMapWithEventReplaced(
      _session.activeTrack.transitionLayer.instructions,
      spanStartIndex: covering.key,
      event: event,
    );
    if (next == null) {
      return;
    }
    updateTransitionInstructions(next, description: 'Edit transition');
  }

  /// Removes the transition span covering [globalFrame]; one undo step.
  void removeTransitionSpanAt(int globalFrame) {
    final covering = transitionSpanAt(globalFrame);
    if (covering == null) {
      return;
    }
    final next = instructionMapWithEventRemoved(
      _session.activeTrack.transitionLayer.instructions,
      spanStartIndex: covering.key,
    );
    if (next == null) {
      return;
    }
    updateTransitionInstructions(next, description: 'Delete transition');
  }

  /// One track's transition spans on its own global axis. Falls back to no
  /// spans for a track id the project no longer holds.
  ///
  /// A hidden transition row contributes NOTHING (B5③ 2026-08-17: 「비지블
  /// = 해당 합성 반영/미반영」) — the composite plan's own visibility law,
  /// said of the one row whose contribution is fades instead of pixels.
  /// The row still draws its spans; only playback stops fading. Asked as
  /// `rowVisible` (the hidden-folder law's one door, ratcheted by
  /// `hidden_folder_is_hidden_test`); the fixture lives in no folder, so
  /// the singleton stack it stands in is its own.
  List<TransitionSpan> transitionSpansOfTrack(TrackId trackId) {
    for (final track in _session._repository.requireProject().tracks) {
      if (track.id == trackId) {
        final transition = track.transitionLayer;
        if (!<Layer>[transition].rowVisible(transition)) {
          return const [];
        }
        return [
          for (final entry in transition.instructions.entries)
            transitionSpanOf(entry),
        ];
      }
    }
    return const [];
  }

  /// One instruction event as a geometry span, WITH its term's mark.
  ///
  /// 🚨The mark is what tells O.L from F.O downstream. Dropping it here — which
  /// this used to do — made `cutOpacityAt` treat every span as a symmetric
  /// cross-dissolve, so an F.O faded the next cut IN and behaved as an O.L
  /// (user 2026-08-11). An id the vocabulary no longer holds falls back to the
  /// bowtie, which is the shape a file from another build most likely meant.
  TransitionSpan transitionSpanOf(MapEntry<int, InstructionEvent> entry) => (
    start: entry.key,
    length: entry.value.length,
    mark:
        _session.cameraInstructionSet
            .defById(entry.value.instructionId)
            ?.markType ??
        CameraInstructionMarkType.ol,
  );
}
