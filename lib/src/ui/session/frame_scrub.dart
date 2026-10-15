import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'playback_rig.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';

/// The FRAME SCRUB — dragging the playhead: the cuts it crosses into while
/// the finger is down, the gap it may stand in, and the commit or abandon
/// when it lifts — as its own object, and the two flags that say so.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and thirteen
/// session members touched. It names the roles it needs in its constructor.
///
/// ↩️The scrub flags ([active], [inGap]) used to stay on the
/// session, on the reading that "the UI reads them" (that cut). Reading
/// them does not need the session to own them: this object is the one that
/// raises and drops them, so it holds them, and the UI reads
/// `session.frameScrub` — ARCH-session-state's second family (2026-09-23),
/// the same move the onion skin made first, and the `SessionInternals`
/// ledger counted down by the two getters it no longer carries.
class FrameScrub {
  FrameScrub({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required ValueListenable<bool> brushInputActive,
    required ValueNotifier<int> editingFrameCursor,
    required PlaybackRig playbackRig,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _brushInputActive = brushInputActive,
       _editingFrameCursor = editingFrameCursor,
       _playbackRig = playbackRig;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  /// Whether a stroke is in flight — the session's `brushInputActive`:
  /// a scrub never moves the playhead under a pen that is drawing.
  final ValueListenable<bool> _brushInputActive;
  final ValueNotifier<int> _editingFrameCursor;
  final PlaybackRig _playbackRig;

  /// True while a ruler scrub is in flight.
  ///
  /// 🚨★★★ #26 (2026-08-15): THIS NO LONGER SWAPS THE DISPLAY. It used to —
  /// the canvas became the composite-cache preview until the release commit
  /// — and the user's law retired that: 「그냥 액티브레이어급으로 그냥 원본
  /// 보여주게하고싶어 … 그냥 항상 full」. A scrub shows the editing canvas,
  /// which follows the cursor through the canvas area's retarget scope.
  ///
  /// ⛔What it still decides is the GAP ANSWER: a parked global reads as a
  /// gap only while the gesture is live ([CutUnderPlayhead.liveParkedFrame]
  /// asks this), so the flag stays and the canvas rebuilds at enter and
  /// leave.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// D6: whether the LIVE global scrub currently stands in a GAP — the EDGE
  /// the canvas content mount listens to.
  ///
  /// A drag that STARTED inside the cut used to cross into the gap
  /// invisibly: the gap branch parks quietly per move, [active] was already
  /// true (its flip is the only rebuild trigger the content mount had), and
  /// the cursor never fires in a gap — so `inGap` was never recomputed and
  /// the canvas kept the cut's picture until release. One comparison per
  /// move, firing only when the ANSWER flips (gap↔cut), so the per-move
  /// parking stays as quiet as UI-R7 #9 demands. Set only while the gesture
  /// is live — a plain tap in a gap parks on pointer-down but never scrubs,
  /// so this stays false and nothing flashes (the no-flash rule).
  ///
  /// ↩️It was `outOfTerritory` until I-57 ②: another cut's frames parked
  /// the scrub too, and the canvas showed the track stack's preview of
  /// them. A scrub crosses into another cut now ([scrubGlobalFrame]), so a
  /// gap is the only place it parks — and the name says that.
  final ValueNotifier<bool> inGap = ValueNotifier<bool>(false);

  /// Releases the two flags; the session's teardown calls it.
  void dispose() {
    active.dispose();
    inGap.dispose();
  }

  /// Global scrub: rides the cursor path inside the active cut; a move onto
  /// ANOTHER cut's frames CROSSES into it, with the landing every cut switch
  /// makes ([SelectionAccess.selectGlobalFrame] — the cut, its row, its
  /// frame, the timeline's rows turning over in place); only a GAP parks
  /// the exact global PER MOVE (UI-R7 #9), committing nothing until the
  /// release ([commitFrameScrub]) lands it.
  ///
  /// 🗣️I-57 (유저 10-08, Q1: 「넘어간다 — 스크럽도 재생처럼, 경계에서 활성
  /// 컷이 바뀐다」 · 10-09, Q2: 「타임라인 행도 그 자리에서 — 행을 먼저
  /// 가볍게 만든 뒤 켠다」): a scrub crosses a boundary as playback does,
  /// through the same landing. ↩️It parked over another cut's frames too and
  /// showed the track stack's preview of them, switching the cut only on
  /// release — so every surface that shows 「the cut being looked at」 had
  /// to be wired to the parking one at a time (the sheet, the envelope, the
  /// cut name), and each one forgotten was the same bug again. What the
  /// crossing costs is a cut switch's; the rail's rows were made light for
  /// it first (I-57 ①).
  void scrubGlobalFrame(int globalFrame) {
    if (_brushInputActive.value) {
      return;
    }
    final axis = _timeline.trackFrameAxis();
    final owner = axis.ownerOf(globalFrame);
    // A track with no cut is all gap (F-341) — the scrub parks on it like
    // anywhere else a cut is not.
    if (axis.isGap(globalFrame) || owner == null) {
      _parkInTheGap(globalFrame);
      return;
    }
    // The gesture stands on a cut — the fact the gap's engage reads to
    // tell a real drag's crossing from a bare pointer-down.
    _stoodOnACut = true;
    if (inGap.value) {
      inGap.value = false;
    }
    if (owner.cutId != _project.activeCutId) {
      // A live parking is cleared BEFORE the landing: the cut switch must
      // not read a drag through a gap as a committed gap departure — its
      // from-the-gap branch would land frame 0 first and double the
      // committed-seek signal.
      _timeline.editingSession.gapGlobalFrame = null;
      _selection.selectGlobalFrame(globalFrame);
      // The crossed frame plays its slice of the mix, as every frame a
      // scrub crosses does.
      _playbackRig.audioScrubber.onScrubFrame(
        _controllers.timelineController.currentFrameIndex,
      );
      return;
    }
    if (_timeline.editingSession.gapGlobalFrame != null) {
      // Scrubbing back onto the cut un-parks — and kicks the warm the gap
      // skipped (one warm per return, not per move).
      _timeline.editingSession.gapGlobalFrame = null;
      _changes.warmActiveCut();
    }
    scrubFrameIndex(math.max(0, axis.localIn(owner, globalFrame)));
  }

  /// A scrub move into a gap: the exact global is parked, and the active
  /// cut stays where the drag left it until the release lands the gap.
  void _parkInTheGap(int globalFrame) {
    // The gap's display engages on the SECOND gap event — an actual drag
    // move — never on the pointer-down alone: a plain TAP in a gap must not
    // flash the gap's presentation for its press-release interval (the
    // same no-flash rule scrubFrameIndex keeps for in-cut taps; the
    // playhead itself follows immediately through the parking either way).
    // OR on the FIRST when this gesture already stood on a cut (D6: a press
    // ON the cursor's own frame never set the flag via scrubFrameIndex, so
    // a two-event rule read the grab-the-playhead drag's genuine crossing
    // as tap-shaped and the canvas froze on the cut).
    final parked = _timeline.editingSession.gapGlobalFrame;
    if ((parked != null && parked != globalFrame || _stoodOnACut) &&
        !active.value) {
      active.value = true;
    }
    if (parked != globalFrame) {
      // The crossed frame plays its slice of the track's sound, as on a
      // cut: a sound row is the track's, and is there where no cut is
      // (F-341).
      _playbackRig.audioScrubber.onScrubTrackFrame(globalFrame);
    }
    _timeline.editingSession.gapGlobalFrame = globalFrame;
    // D6: the gap EDGE — only while the gesture is live (a tap's
    // pointer-down park keeps this false, the no-flash rule), and only on
    // the flip, so per-move parking stays notify-quiet.
    if (active.value && !inGap.value) {
      inGap.value = true;
    }
  }

  /// Whether the LIVE scrub gesture has stood on a cut — plain field (no
  /// rebuilds ride on it): it only sharpens the gap's engage above. Cleared
  /// with the gesture.
  bool _stoodOnACut = false;

  /// A scrub move: repositions the playhead WITHOUT notifying — only the
  /// cursor listenables fire; the full session notify is deferred to
  /// [commitFrameScrub] on release.
  ///
  /// ⛔The cursor is not decoration: since #26 the editing canvas listens to
  /// it, so this is what makes the scrub show the crossed frame. It fires on
  /// the same-frame branch too — a tap that lands where it already was is a
  /// no-op the retarget scope swallows by index.
  void scrubFrameIndex(int frameIndex) {
    // R15-⑤: scrubs are seeks too — refused under a live stroke.
    if (_brushInputActive.value) {
      return;
    }
    if (frameIndex != _controllers.timelineController.currentFrameIndex) {
      _standTheCursorAt(frameIndex);
      // Each crossed frame plays its slice of the mix (2D audio scrub).
      _playbackRig.audioScrubber.onScrubFrame(frameIndex);
      if (!active.value) {
        active.value = true;
        // One warm per gesture. A scrub is a seek and every other seek
        // warms; per-move warms would only thrash the scheduler's ordering.
        _changes.warmActiveCut();
      }
    } else {
      _editingFrameCursor.value = frameIndex;
    }
  }

  /// A run the canvas plays moves the playhead the way a scrub moves it —
  /// the cursor alone, with no session notify — and the editing canvas
  /// draws the frame it stands on (playback-plays-the-screen-material).
  ///
  /// ⛔None of the scrub GESTURE comes with it: no slice of the mix (the run
  /// plays its own sound), no scrub flag, no warm (the run's warmer is
  /// following it already). Only the refusal does — a run's step is a seek
  /// like any other, and no seek moves the playhead under a live stroke.
  void followTheRun(int frameIndex) {
    if (_brushInputActive.value ||
        frameIndex == _controllers.timelineController.currentFrameIndex) {
      return;
    }
    _standTheCursorAt(frameIndex);
  }

  /// Stands the playhead on [frameIndex] without a session notify: the
  /// timeline controller the canvas's plan reads, and the cursor the canvas
  /// listens to — the one move a scrub and a run the canvas plays both make.
  void _standTheCursorAt(int frameIndex) {
    _controllers.timelineController.selectFrameIndex(frameIndex);
    _editingFrameCursor.value = frameIndex;
  }

  /// Ends a live scrub without the landing seek — the storyboard release
  /// path when playback took the transport mid-drag (there is no editing
  /// seek to commit, but the flags must not leak past the gesture: a stuck
  /// gap flag would swallow the next drag's gap edge and resurrect the D6
  /// stale picture, one drag per leak — adversarial review).
  void abandonFrameScrubPreview() {
    if (active.value) {
      active.value = false;
    }
    if (inGap.value) {
      inGap.value = false;
    }
    _stoodOnACut = false;
  }

  /// The scrub gesture's release: ends the scrub and commits the playhead
  /// as ONE ordinary seek (warm + committed-seek signal). A drag that ended
  /// in a GAP carries its exact global in the parking, and the landing is
  /// here: it deselects the cut and keeps the parking (UI-R9 #3). A drag
  /// that crossed into another cut stands in it already
  /// ([scrubGlobalFrame]); its release commits the frame it stands on.
  void commitFrameScrub() {
    _playbackRig.audioScrubber.onScrubEnd();
    if (active.value) {
      active.value = false;
    }
    // D6: the gesture is over — the gap's display state ends with it (the
    // landing seek below re-derives the real gap answer).
    if (inGap.value) {
      inGap.value = false;
    }
    _stoodOnACut = false;
    final parked = _timeline.editingSession.gapGlobalFrame;
    if (parked != null) {
      // R15-⑤: a live stroke refuses the landing seek — the
      // parking stays put (the parked display state) instead of being
      // half-cleared.
      if (_brushInputActive.value) {
        return;
      }
      _selection.selectGlobalFrame(parked);
      return;
    }
    _selection.selectFrameIndex(
      _controllers.timelineController.currentFrameIndex,
    );
  }
}
