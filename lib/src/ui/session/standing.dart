part of '../editor_session_manager.dart';

/// WHERE THE USER STANDS — the cut, the row and the layer the next verb
/// is about: selecting a cut, standing on a row, selecting a layer, and
/// the row that a folded rail hands its standing to.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: three fields of
/// its own (the verb row, the timeline row, the last layer per cut) and
/// ten methods that are the only writers of them; the cut-switch rebuild
/// reads them five times from the session. It reaches the session through
/// `_session`.
class _Standing {
  _Standing(this._session);

  final EditorSessionManager _session;

  /// 🚨F-20 (유저 2026-08-24): 「새 레이어를 만들어도 내부 액티브 레이어가 안
  /// 바뀐다 — 그 상태에서 아래 화살표를 누르면 바로 밑이 아니라 밑의 밑이
  /// 선택된다. 🚨UI만 바꾸고 내부를 안 바꾸는 자리가 더 있는지 전수 점검」.
  ///
  /// [selectLayer] keeps `_verbRow` in step with the active layer, and it is
  /// not the only way the active layer moves: Add Layer seats one straight on
  /// the controller, and a controller REBUILD seats one through
  /// `initialActiveLayerId`. After either, the row was still the old layer's —
  /// so ↓ counted from there and landed a row further than it looked, and the
  /// flip counted the old row's blocks.
  ///
  /// ⛔It CANNOT be enforced at the read (the shape tried first). A row whose
  /// layer is not the active layer is legitimate: the storyboard's rails stand
  /// on a row WITHOUT taking the cut's drawing target (유저 2026-07-27,
  /// `takesLayerActive: false`), so an S row and the active cel layer disagree
  /// on purpose there — and overriding the read put the ring on the wrong row.
  /// The two writers say it instead, each where it moved the layer.
  void seatVerbRowOnActiveLayer() {
    final seated = _session._layerController.activeLayerId;
    if (seated == null || _verbRow == LayerRowAddress(seated)) {
      return;
    }
    _verbRow = LayerRowAddress(seated);
    _timelineRow = _verbRow;
    publishCurrentRow();
  }

  /// The row a frame-axis VERB acts on (R10 #13) — the rail's rows and the
  /// cut's layer rows alike, whichever the user last engaged.
  ///
  /// NOT the same thing as [selectedRow], and deliberately so. The user's
  /// correction when #13 was settled: a V row and a layer row are not
  /// siblings competing for one slot, they are a HIERARCHY — a V row is a
  /// cut, a layer row is a layer INSIDE a cut. So [selectedRow] keeps
  /// saying which row of the FILM is lit (and picking a layer still leaves
  /// it alone, the 2026-07-27 rule), while this says whose blocks the flip
  /// counts. Folding the two into one slot is what made picking a layer
  /// drop the rail's S-row highlight, which is not what either question
  /// was asking.
  TimelineRowAddress? _verbRow;

  /// The TIMELINE's own row, the way [_storyboardRow] is the rail's: the
  /// layer or property lane last engaged there. Kept so that returning to
  /// the timeline restores the row you were on rather than resetting to
  /// whatever the active layer happens to be.
  TimelineRowAddress? _timelineRow;

  /// The panel being worked in owns the frame-axis verbs (user, 2026-08-05:
  /// "마지막으로 무언가 액션이 있었던 패널을 기준으로"). Picking a row is
  /// no longer the only way to move the flip's subject — touching the
  /// panel at all is, because that is what "I am working here" looks like.
  ///
  /// Each panel claims the row IT remembers rather than a fresh one, so
  /// coming back to the timeline lands on the lane you left open instead
  /// of dropping to the layer row.
  ///
  /// A claim never NOTIFIES the session. It fires on pointer-DOWN, and a
  /// ruler drag's whole contract is that it stays silent per move and
  /// commits once on release. What the rails DRAW rides
  /// [_session.currentRowListenable] instead, so the row that moved repaints its
  /// own small cells and nothing else.
  void claimTimelineRow() {
    final layerId = _session.activeLayerId;
    final next =
        _timelineRow ?? (layerId == null ? null : LayerRowAddress(layerId));
    if (next != null) {
      _verbRow = next;
      publishCurrentRow();
    }
  }

  /// Defaults to the active layer's row, not the track's: with nothing
  /// picked yet the row you are on is the one you draw on. Only a cut with
  /// no layers at all falls through to the track row.
  TimelineRowAddress get currentRow {
    final stored = _verbRow;
    if (stored != null) {
      return stored;
    }
    final layerId = _session.activeLayerId;
    return layerId == null
        ? TrackRowAddress(_session.selectedTrackId)
        : LayerRowAddress(layerId);
  }

  /// 🚨T4 — STANDING ON A ROW, as one verb.
  ///
  /// 유저 2026-08-13: 「선택된게 풀리는거, **어떤 행이든 액티브 바꾸면
  /// 풀리도록.** 지금 레이어 액티브 바꾸면 풀리는데 **트랜스폼 멤버 행
  /// 액티브로하면 안풀림**」.
  ///
  /// ★The law was right and its ADDRESS was wrong. 「클릭하면 선택이
  /// 사라진다」 was hung on the timeline host's `onSelectLayer` callback — a
  /// wrapper — so it covered the doors that happened to go through that
  /// wrapper and missed the ones that call the session directly. Standing on
  /// a property lane was one of those, and it will not be the last: a wrapper
  /// is a place, and every new door has to be told about it.
  ///
  /// A verb cannot be walked around. Every surface that means 「여기 서라」
  /// says it here, and what standing DOES is decided once.
  ///
  /// [row] is the address stood on; [frameIndex] seeks as well, for the
  /// surfaces where standing and seeking are one gesture (a lane band's
  /// cells). A label press leaves it null — a label names a ROW, and the
  /// frame stays where it was.
  /// [globalFrameIndex] is the same seek stated on the TRACK's global axis
  /// — the storyboard's rows press in global frames (C6 2026-08-17: their
  /// lane bands stand through THIS verb now instead of a hand-rolled
  /// clear-and-seek that restated the law without the T10 guard). At most
  /// one of the two frames is passed.
  /// [takesLayerActive] is false on the STORYBOARD's rails, where the row you
  /// stand on and the layer you draw on are separate states (유저
  /// 2026-07-27). It is a parameter rather than a second verb because the
  /// clearing law is the same on both panels — only the active layer differs,
  /// and stating that difference once here beats restating the law at each
  /// call site, which is the mistake T4 was.
  void standOnRow(
    TimelineRowAddress row, {
    int? frameIndex,
    int? globalFrameIndex,
    bool takesLayerActive = true,
  }) {
    // 🚨T10. T4's law is untouched by this: the clearing still lives INSIDE
    // the verb rather than at its call sites — scattering it was T4's whole
    // bug. What changed is that the verb now asks a question first.
    //
    // A press that lands inside the current selection stands WITHOUT
    // clearing, because that press is most likely the start of a move.
    // Measured, not assumed: with this unconditional, turning the press-pick
    // on made an SE row move stop committing — the pick wiped the very rows
    // the move was about to carry.
    //
    // ⚠️A caller that names no frame is standing on the row AT THE
    // PLAYHEAD, so that is the cell the question is about. Falling back to
    // it rather than to "no cell" is what lets the guard see a cell range
    // at all: the surfaces reach this verb through a `ValueChanged<LayerId>`
    // that carries no frame, and a null there would make the guard blind to
    // exactly the selection it exists to protect.
    if (globalFrameIndex != null
        ? !_session.standingInsideSelection(row, globalFrameIndex, true)
        : !_session.standingInsideSelection(
            row,
            frameIndex ?? _session.currentFrameIndex,
          )) {
      _session.clearAllSelections();
    }
    switch (row) {
      case LayerRowAddress(:final layerId):
        if (takesLayerActive) {
          selectLayer(layerId);
        } else {
          selectRow(row);
        }
      case LaneRowAddress(:final layerId):
        // A LANE also becomes the verb's subject, so Add keys that property
        // instead of adding a cel (R10 #19). `selectLayer` moves the verb row
        // to the LAYER, which is why the lane is claimed after it — and why a
        // layer row needs nothing more.
        if (takesLayerActive) {
          selectLayer(layerId);
        }
        selectRow(row);
      case TrackRowAddress():
        // A track row has no layer to make active either way.
        selectRow(row);
    }
    if (frameIndex != null) {
      _session.selectFrameIndex(frameIndex);
    }
    if (globalFrameIndex != null) {
      _session.selectGlobalFrame(globalFrameIndex);
    }
  }

  /// Re-publishes [currentRow]. Idempotent and cheap: call it after
  /// anything that could move the answer rather than reasoning about which
  /// writer was the one that did.
  ///
  /// Stands down while the answer would need a TRACK it cannot have (no
  /// row engaged, no active layer, and a project that may hold no tracks
  /// yet) — there is nothing to light in that state, and asking would
  /// throw.
  void publishCurrentRow() {
    if (_session._disposed ||
        (_verbRow == null && _session.activeLayerId == null)) {
      return;
    }
    _session.currentRowListenable.value = currentRow;
  }

  /// THE FOLD LAW (R5 #11): what disappears never keeps the selection.
  /// Folding something you are standing INSIDE hands the standing row to
  /// whatever swallowed it.
  ///
  /// Two folds already obeyed this, each in its own place and its own
  /// words — a folder taking the selection off a member
  /// ([_session.toggleLayerCollapsed], R27 #24) and an attach base taking it off an
  /// attach row (the workspace's group fold, UI-R24 #4). The fx twirl and
  /// the lane-GROUP twirl did not, so closing a Transform group left you
  /// standing on a row that was no longer on screen, and the canvas went on
  /// refusing strokes for a lane nobody could see. Four folds, one rule,
  /// one place.
  ///
  /// [laneId] null means the whole twirl-down is closing (every lane of the
  /// layer goes), so the LAYER's own row is what swallows it. A non-null
  /// [laneId] is a GROUP header closing, and it swallows its members alone
  /// — the header itself stays on screen and is where you land.
  void handOffCurrentRowOnFold(LayerId layerId, {String? laneId}) {
    final row = currentRow;
    if (laneId == null) {
      _session._rowSelection.foldRowSelection(
        vanished: (address) =>
            address is LaneRowAddress && address.layerId == layerId,
        swallower: LayerRowAddress(layerId),
      );
      if (row is LaneRowAddress && row.layerId == layerId) {
        selectLayer(layerId);
      }
      return;
    }
    _session._rowSelection.foldRowSelection(
      vanished: (address) => currentRowIsInsideGroup(address, layerId, laneId),
      swallower: LaneRowAddress(layerId, laneId),
    );
    if (currentRowIsInsideGroup(row, layerId, laneId)) {
      selectRow(LaneRowAddress(layerId, laneId));
    }
  }

  /// Selects a row of the storyboard's rail by ADDRESS — the rail taps and
  /// the cells press come through here. A track row additionally promotes
  /// that track's cut under the playhead (UI-R18 #6); a layer row has no
  /// landing verb of its own, because the drawing target is not this
  /// selection's business.
  void selectRow(TimelineRowAddress row) {
    switch (row) {
      case LayerRowAddress(:final layerId):
        if (_session.editingInteractionBusy) {
          return;
        }
        // The row lives on a track, so picking it picks that track too —
        // the rail's row selection and the track selection must not
        // disagree (the range drag that follows a press resolves its rows
        // against the SELECTED track's rail).
        final owner = _session._trackSe.trackOwnedRailOwner(layerId);
        var trackMoved = false;
        if (owner != null && _session.selectedTrackId != owner.id) {
          _session._editingSession.setSelectedTrackId(owner.id);
          trackMoved = true;
        }
        if (_session._storyboardRows.storeStoryboardRow(row) || trackMoved) {
          _session._notifyChanged();
        }
      case LaneRowAddress():
        // R10 #19: a property row is a row you can be ON. The rail's own
        // highlight resolves it to the containing V row, like any other
        // in-cut row; what moves is the verb's subject.
        //
        // A lane lives in the TIMELINE, so it is the timeline's row to
        // remember: coming back to that panel restores the lane rather
        // than dropping to the layer it hangs under.
        //
        // R5 #12: and the CELL range goes. A frame range is drawn on a
        // LAYER row, so standing on a property is always leaving the row
        // it belongs to — but `selectLayer` runs first on this path and
        // keeps a range whose layer has not changed, which left the band
        // sitting on the cells while the subject was a lane. Nothing draws
        // a frame range from a lane, so this can never drop one mid-drag.
        _session.clearFrameRangeSelection();
        _timelineRow = row;
        if (_session._storyboardRows.storeStoryboardRow(row)) {
          _session._notifyChanged();
        }
      case TrackRowAddress(:final trackId):
        _session.selectTrackCutAtPlayhead(trackId);
    }
    // Every arm can move the drawn row, and the track arm does it through
    // a path of its own — publishing once here beats three call sites that
    // must each remember.
    publishCurrentRow();
  }

  /// The row each cut was last worked on, replayed on the way back in
  /// (user request 2026-07-26). SESSION view state on purpose: hanging it
  /// on the Cut would make picking a layer a document edit — an undo entry
  /// and a dirty file per click.
  final Map<CutId, LayerId> _lastLayerByCut = <CutId, LayerId>{};

  /// Records the layer a cut is being LEFT on — one funnel instead of a
  /// hook on every path that can move the active layer. Stale ids need no
  /// cleanup: [_session._activeCutHasLayer] already drops a layer the cut no longer
  /// has, and the rebuild falls back to the top row.
  ///
  /// SE rows are recorded like any other: what the timeline shows for them
  /// is a cut-local PROJECTION of the track layer, so "the row this cut was
  /// left on" can name one, and the id is the same in every cut — a cut
  /// left on S1 comes back on S1 for free.
  void rememberActiveLayerForCut() {
    final cutId = _session._editingSession.activeCutId;
    final layerId = _session.activeLayerId;
    if (cutId != null && layerId != null) {
      _lastLayerByCut[cutId] = layerId;
    }
  }

  void selectCut(CutId cutId) {
    if (cutId == _session._editingSession.activeCutId) {
      return;
    }
    // R15-⑤: never switch cuts under a live editing interaction.
    if (_session.editingInteractionBusy) {
      return;
    }
    rememberActiveLayerForCut();
    final nextActiveLayerId = _lastLayerByCut[cutId];

    final fromGap =
        _session._gapGlobalFrame != null ||
        _session._editingSession.activeCutId == null;
    // The visibility solo is cut-scoped: restore the eyes before leaving.
    if (_session._solo._layerVisibilitySoloEnabled) {
      _session._solo.exitVisibilitySolo();
    }
    _session._editingSession.setActiveCutId(cutId);
    // Keep the pair reconciled at the seam instead of only at read time:
    // selecting a cut selects its track, so the stored selection is right
    // the moment the cut is dropped (a gap park) rather than falling back.
    _session._editingSession.setSelectedTrackId(
      trackIdOfCut(_session._repository.requireProject(), cutId) ??
          _session._editingSession.selectedTrackId,
    );
    _session._clipboard._copiedFrame = null;
    _session.clearFrameRangeSelection();
    // The cut comes back on the row it was left on; never visited (or the
    // layer is gone — the rebuild's own guard) falls back to the top row.
    _session._rebuildActiveCutControllers(
      preferredActiveLayerId: nextActiveLayerId,
    );
    if (fromGap) {
      // Activating a cut FROM the gap lands on ITS first frame (UI-R10
      // #14): the stale gap-global cursor never leaks into the new cut
      // (selectFrameIndex also clears the parking).
      _session.selectFrameIndex(0);
    }
    // Yield the warm window first, exactly as a frame seek does. A cut
    // switch used to warm immediately, which was fine while switching was
    // a click — but the V row's flip switches cuts once per press, so a
    // run of them queued a full-canvas warm per step and the run stuttered
    // on work it was about to invalidate anyway.
    _session.prerenderScheduler.notifyEditActivity();
    _session._warmActiveCut();
    _session._notifyChanged();
  }

  /// Selects the CUT's row — the active layer, which is the drawing target
  /// and what the timeline's rail highlights. It does not touch the
  /// storyboard rail's own [_session.selectedRow]: the two row selections are
  /// separate (user decision 2026-07-27).
  void selectLayer(LayerId layerId) {
    var changed = false;
    // A frame-range selection is single-layer (UI-R8): moving to another
    // row drops it. The lane selection follows the same rule.
    if (_session.frameRangeSelection.value != null &&
        _session.frameRangeSelection.value!.layerId != layerId) {
      _session.clearFrameRangeSelection();
      changed = true;
    }
    if (_session.laneRangeSelection.value != null &&
        _session.laneRangeSelection.value!.layerId != layerId) {
      _session.clearLaneRangeSelection();
      changed = true;
    }
    // ALREADY-ACTIVE IS FREE. Every timeline cell tap calls this before it
    // seeks — `select()` sends the layer and the frame — and the seek itself
    // is deliberately notify-free (it rides the cursor notifier). This was
    // not: clicking a second cell in the row you are already on announced
    // app-wide and rebuilt the whole panel, which is what made cell
    // selection feel like it lagged behind the pointer.
    if (_session.activeLayerId != layerId) {
      _session._layerController.selectLayer(layerId);
      // The solo mode FOLLOWS the active layer (R4 #7) — nothing to follow
      // when the layer did not move, and re-applying it is what would have
      // fought a manual visibility toggle on every click.
      _session._solo.syncVisibilitySolo();
      changed = true;
    }
    // R10 #13: picking a layer moves the VERB's row, so the flip counts
    // this layer's blocks from here. It does NOT touch the rail's row —
    // that stays where the user put it (2026-07-27), and it is a different
    // question: which row of the FILM is lit.
    _verbRow = LayerRowAddress(layerId);
    _timelineRow = _verbRow;
    // The drawn row rides its own notifier, so leaving a property lane for
    // its layer row repaints the rail even when nothing else changed —
    // "already active is free" stays true for the session notify.
    publishCurrentRow();
    if (changed) {
      _session._notifyChanged();
    }
  }
}
