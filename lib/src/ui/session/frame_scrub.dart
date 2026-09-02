part of '../editor_session_manager.dart';

/// The FRAME SCRUB — dragging the playhead: the preview it shows while the
/// finger is down, the territory it touched, and the commit or abandon when
/// it lifts — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and thirteen
/// session members touched (the scrub flags stay on the session — the UI
/// reads them). It reaches the session through `_session`.
class _FrameScrub {
  _FrameScrub(this._session);

  final EditorSessionManager _session;

  /// Global scrub: rides the cursor path inside the active cut's
  /// territory; EVERY out-of-territory move — a gap OR another cut's
  /// frames — parks the exact global PER MOVE (UI-R7 #9) and commits
  /// NOTHING. The parking notifier drives the storyboard playhead and the
  /// track-stack preview live, while the active cut and its controllers
  /// stay untouched for the whole drag: the old per-move escalation to
  /// [_session.selectGlobalFrame] on a boundary cross ran selectCut + a committed
  /// seek per move, rebuilding every visible panel — the cut-boundary
  /// crossing lag — and the gap branch's immediate deselect was the same
  /// hitch on gap entry. [_session._followPlaybackCut] keeps playback's crossings
  /// quiet for exactly this reason; the release ([commitFrameScrub])
  /// lands the ONE full seek, where cut activation and gap deselection
  /// now both live (UI-R10 #13's live empty-out moved there on purpose).
  void scrubGlobalFrame(int globalFrame) {
    if (_session.editingInteractionBusy) {
      return;
    }
    final axis = _session.trackFrameAxis();
    if (axis.isEmpty) {
      return;
    }
    final owner = axis.ownerOf(globalFrame);
    if (axis.isGap(globalFrame) ||
        owner == null ||
        owner.cutId != _session.activeCutId) {
      // The preview engages on the SECOND out-of-territory event — an
      // actual drag move — never on the pointer-down alone: a plain TAP
      // over another cut's frames must not flash the track-stack
      // presentation for its press-release interval (the same no-flash
      // rule scrubFrameIndex keeps for in-cut taps; the playhead itself
      // follows immediately through the parking either way). No warm:
      // the track stack self-fills, there is no active-cut cache to fill.
      final parked = _session._gapGlobalFrame;
      // Engage on the SECOND out-of-territory event — OR on the FIRST
      // when this gesture already touched the cut's territory (D6: a
      // press ON the cursor's own frame never set the flag via
      // scrubFrameIndex, so the old two-event rule read the grab-the-
      // playhead drag's genuine crossing as tap-shaped and the canvas
      // froze on the previous cut). A pointer-down alone still engages
      // nothing: the no-flash rule is about the DOWN, not about moves.
      if ((parked != null && parked != globalFrame || _scrubTouchedTerritory) &&
          !_session.frameScrubActive.value) {
        _session.frameScrubActive.value = true;
      }
      _session._gapGlobalFrame = globalFrame;
      // D6: the territory-exit EDGE — only while the gesture is live
      // (a tap's pointer-down park keeps this false, the no-flash rule),
      // and only on the flip, so per-move parking stays notify-quiet.
      if (_session.frameScrubActive.value &&
          !_session.scrubOutOfTerritory.value) {
        _session.scrubOutOfTerritory.value = true;
      }
      return;
    }
    // The gesture stands IN territory — the fact the out-branch's engage
    // reads to tell a real drag's crossing from a bare pointer-down.
    _scrubTouchedTerritory = true;
    if (_session._gapGlobalFrame != null) {
      // Scrubbing back onto the cut un-parks — and kicks the warm the
      // out-of-territory engage skipped (one warm per territory entry,
      // not per move: the preview reads the composite cache, so a cold
      // stretch would otherwise show stale paper for the whole re-entry).
      _session._gapGlobalFrame = null;
      _session._warmActiveCut();
      // D6: the re-entry edge — the content mount swaps back to the
      // interactive canvas even when the cursor lands on its own frame
      // (the retarget scope swallows an unchanged index, so without
      // this the mounted track stack kept showing the backdrop floor).
      if (_session.scrubOutOfTerritory.value) {
        _session.scrubOutOfTerritory.value = false;
      }
    }
    scrubFrameIndex(math.max(0, globalFrame - owner.startFrame));
  }

  /// Whether the LIVE scrub gesture has stood inside the active cut's
  /// territory — plain field (no rebuilds ride on it): it only sharpens
  /// the out-branch's engage above. Cleared with the gesture.
  bool _scrubTouchedTerritory = false;

  /// A scrub move: repositions the playhead WITHOUT notifying — only the
  /// cursor listenables fire; the full session notify is deferred to
  /// [commitFrameScrub] on release.
  ///
  /// ⛔The cursor is not decoration: since #26 the editing canvas listens to
  /// it, so this is what makes the scrub show the crossed frame. It fires on
  /// the same-frame branch too — a tap that lands where it already was is a
  /// no-op the retarget scope swallows by index.
  void scrubFrameIndex(int frameIndex) {
    // R15-⑤: scrubs are seeks too — refused under a live edit.
    if (_session.editingInteractionBusy) {
      return;
    }
    if (frameIndex != _session._timelineController.currentFrameIndex) {
      _session._timelineController.selectFrameIndex(frameIndex);
      _session.editingFrameCursor.value = frameIndex;
      // Each crossed frame plays its slice of the mix (2D audio scrub).
      _session.audioScrubber.onScrubFrame(frameIndex);
      if (!_session.frameScrubActive.value) {
        _session.frameScrubActive.value = true;
        // One warm per gesture. A scrub is a seek and every other seek
        // warms; per-move warms would only thrash the scheduler's ordering.
        _session._warmActiveCut();
      }
    } else {
      _session.editingFrameCursor.value = frameIndex;
    }
  }

  /// The scrub gesture's release: ends the preview and commits the
  /// scrubbed playhead as ONE ordinary seek (warm + committed-seek signal).
  /// A drag that ended OUT of the active cut's territory carries its exact
  /// global in the parking — the deferred full seek lands here: over a cut
  /// it activates it (selectCut + local frame), in a gap it deselects and
  /// keeps the parking (UI-R9 #3). This is the ONLY place a global drag
  /// commits — the moves themselves never do.
  /// Ends a live scrub PREVIEW without the landing seek — the storyboard
  /// release path when playback took the transport mid-drag (there is no
  /// editing seek to commit, but the preview flags must not leak past
  /// the gesture: a stuck territory flag would swallow the next drag's
  /// exit edge and resurrect the D6 stale picture, one drag per leak —
  /// adversarial review).
  void abandonFrameScrubPreview() {
    if (_session.frameScrubActive.value) {
      _session.frameScrubActive.value = false;
    }
    if (_session.scrubOutOfTerritory.value) {
      _session.scrubOutOfTerritory.value = false;
    }
    _scrubTouchedTerritory = false;
  }

  void commitFrameScrub() {
    _session.audioScrubber.onScrubEnd();
    if (_session.frameScrubActive.value) {
      _session.frameScrubActive.value = false;
    }
    // D6: the gesture is over — the out-of-territory display state ends
    // with it (the landing seek below re-derives the real gap answer).
    if (_session.scrubOutOfTerritory.value) {
      _session.scrubOutOfTerritory.value = false;
    }
    _scrubTouchedTerritory = false;
    final parked = _session._gapGlobalFrame;
    if (parked != null) {
      // R15-⑤: a live editing interaction refuses the landing seek — the
      // parking stays put (the parked display state) instead of being
      // half-cleared.
      if (_session.editingInteractionBusy) {
        return;
      }
      // The parking is cleared BEFORE the landing seek: selectCut must
      // not read a live drag's parking as a committed gap departure —
      // its fromGap branch would land frame 0 first and double the
      // committed-seek signal. A gap landing re-parks by itself.
      _session._gapGlobalFrame = null;
      _session.selectGlobalFrame(parked);
      return;
    }
    _session.selectFrameIndex(_session._timelineController.currentFrameIndex);
  }
}
