import 'dart:collection' show SplayTreeMap;
import '../../models/camera_instruction.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/transition_geometry.dart';
import '../text/app_strings.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../services/commands/track_transition_commands.dart';
import '../timeline/instruction_span_editing.dart';
import 'session_roles.dart';
import 'camera.dart';

/// The TRANSITIONS — the spans a track carries between cuts, the display
/// layer they are drawn through, their instruction set and the warnings for
/// a cut edge that crosses one — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and eight
/// session members touched, `activeTrack` above all. It names the roles
/// it needs in its constructor.
class Transitions {
  Transitions({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required Camera camera,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _camera = camera;

  final Camera _camera;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;

  /// The two forms a drag of the transition row previews, in the track-SE
  /// rows' shape (`TrackSe.previewFormsOf`): [row] projected onto the active
  /// cut for the cut's rows, as [trackTransitionDisplayLayer] projects the
  /// committed one, and [row] itself for the storyboard's strip. Both ride
  /// the one drag-preview channel, so a mark follows the hand on either
  /// surface and the release commits once.
  ///
  /// ↩️The row had a channel of its own, global form only, and the cut's
  /// row stayed off the shared one because a global-keyed entry there
  /// would have leaked into its projection. The SE rows had already
  /// answered that with the second form (유저 2026-09-26: 「se블록이랑
  /// 똑같이 글로벌이 주인인 상태랑 똑같지않나? 그거 그대로 법 통일해서
  /// 적용해도 문제되나?」).
  ({Layer shown, Layer? global}) previewFormsOf(Layer row) => (
    shown: _projectOntoCut(
      row,
      cutStart: _project.activeCutGlobalStartFrame,
      duration: _project.activeCutOrNull?.duration ?? 0,
    ).display,
    global: row,
  );

  /// The active track's transition spans on the GLOBAL frame axis — the one
  /// reader for every surface that has to answer a transition question
  /// (the sheet's のりしろ, the cut view's marks, the compositor's
  /// ramp). They are plain records so nobody downstream has to know a layer is
  /// behind them — start, length and the TERM'S MARK, which is what says
  /// whether the span moves both cuts or only its own.
  List<TransitionSpan> get activeTrackTransitionSpans => [
    for (final entry
        in _selection.activeTrack.transitionLayer.instructions.entries)
      transitionSpanOf(entry),
  ];

  /// The track that owns [layerId] as its TRANSITION row, on any track.
  Track? trackTransitionOwner(LayerId layerId) {
    for (final track in _project.repository.requireProject().tracks) {
      if (track.transitionLayer.id == layerId) {
        return track;
      }
    }
    return null;
  }

  bool isTrackTransitionLayerId(LayerId layerId) =>
      trackTransitionOwner(layerId) != null;

  /// The track's TRANSITION row as a cut-local display clone — the camera
  /// section's third row.
  ///
  /// 🚨 Unlike the SE clones this is a PROJECTION, not a window
  /// ([transitionMarkInCut]): a span that crosses this cut's boundary shows
  /// at its FULL length on the side it belongs to, because half a bowtie
  /// says nothing to whoever is reading the row. The clone therefore does
  /// NOT describe where the span really is — the global row does that, and
  /// an edit made on this row is written THERE, to the span the mark was
  /// drawn from ([transitionSpanStartShownInCutAt]).
  ///
  /// Cached on the same terms as the SE clones: same source layer + same
  /// window = the same instance back, so identity-keyed row memos hold.
  Layer get trackTransitionDisplayLayer {
    final source = _selection.activeTrack.transitionLayer;
    final cutStart = _project.activeCutGlobalStartFrame;
    final duration = _project.activeCutOrNull?.duration ?? 0;
    final cached = _transitionDisplayClone;
    if (cached != null &&
        identical(cached.source, source) &&
        cached.cutStart == cutStart &&
        cached.duration == duration) {
      return cached.display;
    }
    final walk = _projectOntoCut(
      source,
      cutStart: cutStart,
      duration: duration,
    );
    _transitionDisplayClone = (
      source: source,
      cutStart: cutStart,
      duration: duration,
      display: walk.display,
      crossing: walk.crossing,
      origins: walk.origins,
    );
    return walk.display;
  }

  /// The projection walk onto the cut whose frames are `[cutStart,
  /// cutStart + duration)`, with the projected keys of the one-sided spans
  /// that cross it, and where each projected mark came from — its span's
  /// GLOBAL start, by projected key.
  ({Layer display, Set<int> crossing, Map<int, int> origins}) _projectOntoCut(
    Layer source, {
    required int cutStart,
    required int duration,
  }) {
    final projected = SplayTreeMap<int, InstructionEvent>();
    // D26: the crossing answer is recorded under the PROJECTED key in the
    // same walk — the clone re-keys spans to cut-local starts, so a marker
    // bound by global key alone would miss or mis-mark projected blocks.
    final crossing = <int>{};
    final origins = <int, int>{};
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
      origins[mark.start] = entry.key;
      if (oneSidedSpanCrossesOwnCut(
        span: span,
        cutStart: cutStart,
        cutEnd: cutStart + duration,
      )) {
        crossing.add(mark.start);
      }
    }
    return (
      display: source.copyWith(instructions: projected),
      crossing: crossing,
      origins: origins,
    );
  }

  ({
    Layer source,
    int cutStart,
    int duration,
    Layer display,
    Set<int> crossing,
    Map<int, int> origins,
  })?
  _transitionDisplayClone;

  /// The transition row in the SE rows' spill-in map
  /// (`TrackSe.trackSeSpillInLeadFrames`): its id, with how far into its
  /// span the cut starts, when the mark drawn at the cut's frame 0 is a span
  /// that began in an earlier cut.
  ///
  /// UI-R7 #6 is the SE rows' law for that block, and it is this mark's
  /// too: its head lives in the earlier cut, so its start grip stands down
  /// here (유저 2026-09-26: 「애초에 넘어온쪽 표시엔 머리그립이 없을텐데.
  /// se행이 그럴텐데」). The head is edited on the storyboard, the axis the
  /// span lives on — the earlier cut does not draw a fade that is not its
  /// own.
  Map<LayerId, int> get transitionSpillInLeadFrames {
    final row = trackTransitionDisplayLayer;
    final start = _transitionDisplayClone?.origins[0];
    final cutStart = _project.activeCutGlobalStartFrame;
    return start == null || start >= cutStart
        ? const {}
        : {row.id: cutStart - start};
  }

  /// D26: the crossing-fade warning for the CUT-VIEW transition row, by
  /// the display clone's projected local start key. The answer is computed
  /// in [trackTransitionDisplayLayer]'s own projection walk with the SAME
  /// predicate the apply gate reads ([oneSidedSpanCrossesOwnCut]) — the
  /// T25 one-sentence law: the refusal and the warning cannot drift.
  String? transitionCrossingWarningInCutAt(int projectedStartKey) {
    // Resolve the clone first so the cache always answers for the active
    // cut the row is actually showing.
    trackTransitionDisplayLayer;
    return (_transitionDisplayClone?.crossing.contains(projectedStartKey) ??
            false)
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
  ///
  /// F-90: for the cut the sheet PRINTS — a scrub over another cut makes it
  /// a different one from the cut open for editing.
  Layer trackTransitionSheetLayerFor({
    required int cutStart,
    required int duration,
  }) {
    final (:display, :crossing, origins: _) = _projectOntoCut(
      _selection.activeTrack.transitionLayer,
      cutStart: cutStart,
      duration: duration,
    );
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
        _selection.activeTrack.transitionLayer.instructions[globalStartKey];
    if (event == null) {
      return null;
    }
    final span = transitionSpanOf(MapEntry(globalStartKey, event));
    if (transitionSidesOf(span.mark) == TransitionSides.both) {
      return null;
    }
    for (final placed in cutSpansOf(_selection.activeTrack)) {
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
    for (final def in _camera.cameraInstructionSet.defs)
      if (cameraInstructionIsTransition(def)) def,
  ];

  /// Whether a transition span can start at the playhead: there has to be a
  /// vocabulary to draw from and no span there already.
  ///
  /// The playhead is [_selection.editingGlobalFrame] — the ONE track-global reader — and
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
    final track = _selection.activeTrack;
    final row = LayerRowAddress(track.transitionLayer.id);
    final onTrack = _selection.trackFrameRangeSelection.value;
    final inCut = _selection.frameRangeSelection.value;
    // The cut view's own range counts too (F-180): a cut-local range over
    // the row's projection starts where its first cell stands globally.
    final ({int startFrame, int length}) wanted;
    if (onTrack != null &&
        onTrack.trackId == track.id &&
        onTrack.coversRow(row)) {
      wanted = (startFrame: onTrack.startFrame, length: onTrack.lengthFrames);
    } else if (inCut != null && inCut.coversRow(row)) {
      wanted = (
        startFrame: _project.activeCutGlobalStartFrame + inCut.startIndex,
        length: inCut.endIndexExclusive - inCut.startIndex,
      );
    } else {
      wanted = (startFrame: _selection.editingGlobalFrame, length: 1);
    }
    if (wanted.startFrame < 0 || wanted.length < 1) {
      return null;
    }
    final covering = instructionSpanCovering(
      track.transitionLayer.instructions,
      wanted.startFrame,
    );
    return covering == null ? wanted : null;
  }

  bool get canCreateTransitionSpanAtPlayhead =>
      transitionSpanCreationOrNull != null;

  /// [transitionSpanCreationOrNull] as the CUT VIEW asks it: the same plan,
  /// refused where the cut's own row already SHOWS a mark.
  ///
  /// 🚨F-180 (유저 2026-09-25): 「타임라인패널에서 트랜지션레이어에
  /// 서있을떄 +버튼이 활성화안되서 생성안됨. 스토리보드만 됨 …
  /// 타임라인패널(로컬)에서도 가능하도록」 — and I-9 had asked the same of the
  /// double tap on 08-29 (「타임라인의 se행이랑 트랜지션행 … 새로만들자」).
  /// The cut row was read-only by the 08-09 law 「글로벌 ↔ 로컬은 다르게
  /// 보인다, 로컬은 읽기 전용 — 그립 없음, 엣지 편집 없음」, whose reason is
  /// moving positions and edges from inside a later cut. Creating moves
  /// neither: it writes the global row at a global frame, through the verb
  /// the storyboard's ＋ presses. The rest of that law went the same day
  /// (transition-row-open-in-the-cut — see
  /// [transitionSpanStartShownInCutAt]).
  ///
  /// ⚠️The extra refusal is the projection's ([transitionMarkInCut]): a
  /// span crossing into this cut is drawn from local 0 at its full length,
  /// so its mark can stand over frames the global row has free. A ＋ lit
  /// there would stack a second span under a mark the user is looking at.
  ({int startFrame, int length})? get transitionSpanCreationInCutOrNull {
    final plan = transitionSpanCreationOrNull;
    if (plan == null) {
      return null;
    }
    final local = plan.startFrame - _project.activeCutGlobalStartFrame;
    return transitionShownInCutAt(local) ? null : plan;
  }

  /// Whether the cut's transition row SHOWS a mark on [localFrame] — the
  /// cell as the cut view draws it, which is what 「empty」 means to a
  /// double tap there.
  bool transitionShownInCutAt(int localFrame) =>
      transitionSpanStartShownInCutAt(localFrame) != null;

  /// The GLOBAL start of the span whose mark the cut's row shows on
  /// [localFrame], or null where it shows none — the one way back from the
  /// projection to the span it draws.
  ///
  /// 🚨transition-row-open-in-the-cut (유저 2026-09-25): 「편집은 동일하게
  /// 타임라인에서 다 할수있고, 원본 데이터는 글로벌에서 가지고있음. 일방적인
  /// 투영만 하되 편집은 가능하게」. Every edit the cut view makes of a mark
  /// — open it, delete it, drag its edges — is an edit of THIS span, on the
  /// global row, through the verb the storyboard presses. ⚠️Not
  /// `cutStart + localFrame`: a span crossing in from the cut before is
  /// drawn from this cut's frame 0 at its full length, so the frame under
  /// the hand need not be one of its own.
  int? transitionSpanStartShownInCutAt(int localFrame) {
    final shown = instructionSpanCovering(
      trackTransitionDisplayLayer.instructions,
      localFrame,
    );
    return shown == null ? null : _transitionDisplayClone?.origins[shown.key];
  }

  /// [transitionSpanStartShownInCutAt] for the verbs that EDIT — open, delete,
  /// drag an edge: null on an O.L's mark, which the cut draws but does not
  /// edit ([transitionEditableInCut], 유저 2026-09-26).
  ///
  /// ⚠️Not the question [transitionShownInCutAt] answers. A ＋ and a double
  /// tap ask whether a mark stands there at all — an O.L's does, so nothing
  /// is made under it — and those two keep asking that.
  int? transitionSpanStartEditableInCutAt(int localFrame) {
    final start = transitionSpanStartShownInCutAt(localFrame);
    final event = start == null
        ? null
        : _selection.activeTrack.transitionLayer.instructions[start];
    return event != null &&
            transitionEditableInCut(
              transitionSpanOf(MapEntry(start!, event)).mark,
            )
        ? start
        : null;
  }

  /// Starts a transition span on the GLOBAL axis, where and as long as
  /// [transitionSpanCreationOrNull] says.
  ///
  /// Dialog-free like its direction-row twin (UI-R25 #2): it takes the first
  /// transition term and the Edit Instance dialog changes it afterwards. The
  /// grips own the length from then on — and a span only DOES anything once
  /// it has been dragged across a cut boundary, which is the rule the
  /// geometry enforces rather than this verb.
  void createTransitionSpanAtPlayhead() =>
      _execute(_spanCreationCommand(transitionSpanCreationOrNull));

  /// The cut view's ＋ — [createTransitionSpanAtPlayhead] on
  /// [transitionSpanCreationInCutOrNull]'s plan.
  void createTransitionSpanInCut() =>
      _execute(transitionSpanCreationInCutCommand());

  /// The cut view's span as a command, for a caller that composes it into
  /// a larger step (a cut-local range fills every row it spans at once).
  UpdateTrackTransitionLayerCommand? transitionSpanCreationInCutCommand() =>
      _spanCreationCommand(transitionSpanCreationInCutOrNull);

  UpdateTrackTransitionLayerCommand? _spanCreationCommand(
    ({int startFrame, int length})? plan,
  ) {
    if (plan == null) {
      return null;
    }
    final track = _selection.activeTrack;
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
      return null;
    }
    return UpdateTrackTransitionLayerCommand(
      repository: _project.repository,
      trackId: track.id,
      before: before,
      after: before.copyWith(instructions: next),
      debugLabel: 'Add transition',
    );
  }

  void _execute(UpdateTrackTransitionLayerCommand? command) {
    if (command == null) {
      return;
    }
    _project.historyManager.execute(command);
    _transitionDisplayClone = null;
    _changes.notifyChanged();
  }

  /// Replaces the whole transition span map in one undo step — the writer
  /// behind the edge grips and the edit dialog.
  void updateTransitionInstructions(
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit transition',
  }) {
    final track = _selection.activeTrack;
    final before = track.transitionLayer;
    _project.historyManager.execute(
      UpdateTrackTransitionLayerCommand(
        repository: _project.repository,
        trackId: track.id,
        before: before,
        after: before.copyWith(
          instructions: SplayTreeMap<int, InstructionEvent>.from(instructions),
        ),
        debugLabel: description,
      ),
    );
    _transitionDisplayClone = null;
    _changes.notifyChanged();
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
        _selection.activeTrack.transitionLayer.instructions,
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
      _selection.activeTrack.transitionLayer.instructions,
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
      _selection.activeTrack.transitionLayer.instructions,
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
    for (final track in _project.repository.requireProject().tracks) {
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
  /// bowtie ([transitionMarkOf]).
  TransitionSpan transitionSpanOf(MapEntry<int, InstructionEvent> entry) => (
    start: entry.key,
    length: entry.value.length,
    mark: transitionMarkOf(
      _camera.cameraInstructionSet.defById(entry.value.instructionId),
    ),
  );
}
