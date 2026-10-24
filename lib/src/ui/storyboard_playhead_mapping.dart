/// Track-global frame mapping between the session and the storyboard panel:
/// the active track's cuts laid end to end (the same layout allCuts
/// playback plays). Free functions so the storyboard host AND the tab host
/// (playhead clamp on tab switch) share one implementation.
library;

import 'dart:math' as math;

import 'editor_session_manager.dart';
import 'playback/canvas_playback_controller.dart';
import 'timeline/timeline_ruler_cursor_overlay.dart' show ReadyRun;
import '../models/cut_id.dart';
import '../models/storyboard_timeline_layout.dart';

/// The SELECTED track's layout entries (every entry as fallback when that
/// track holds no cuts). Reads the session's first-class track selection
/// rather than hunting for the active cut's owner, so a playhead parked in
/// a gap keeps addressing the same track.
///
/// ⛔It is the session's track axis, not a second walk of its own: this
/// narrowed the layout itself, word for word the walk
/// [EditorSessionManager.trackFrameAxis] does, and the two had only to
/// drift for the storyboard to address one track and the session another.
List<StoryboardTimelineLayoutEntry> storyboardActiveTrackLayout(
  EditorSessionManager session,
) => session.trackFrameAxis().entries;

/// "To start" (REC1-B, amended by D1 2026-08-17): global frame 0 — the
/// axis origin GAPS INCLUDED, where an all-cuts play actually begins.
/// The old body spoke cut-local (selectCut + frame 0) and so skipped a
/// leading gap; the canonical global seek already knows the whole law —
/// first cut at 0 selects it, a leading gap PARKS there (T12: parking is
/// the only way to be in a gap), and the storyboard playhead follows the
/// parking with no extra wiring.
///
/// A free function because its callers are not the storyboard host: the
/// transport's 「처음으로」 and its key, both through [panelTransportFor].
/// One implementation, two callers. ↩️It left the host when the transport
/// went to the 문턱 (유저 확정, 2026-08-10), built by the workspace.
void seekStoryboardPlayheadToTrackStart(EditorSessionManager session) {
  // An EMPTY selected track displays the whole-layout fallback — re-aim
  // at the track actually on screen before seeking (the old body's
  // selectCut did this as a side effect, and losing it left the play
  // button silently dead: the play playlist filters by selected track
  // with NO fallback, so the parked axis and the playlist disagreed —
  // adversarial review). With cuts on the selected track this is a
  // no-op.
  final entries = storyboardActiveTrackLayout(session);
  if (entries.isEmpty) {
    return;
  }
  if (entries.first.trackId != session.selectedTrackId) {
    session.selectCut(entries.first.cutId);
  }
  session.selectGlobalFrame(0);
}

/// The stretches of the track-global frames in `[start, end)` that are
/// READY to play — the storyboard ruler's green bar. [layout] defaults to
/// the session's track axis, which is one memo per layout and track: the
/// ruler asks on every repaint, and rebuilding the whole track layout each
/// time was a fixed per-tick tax (R12-⑥).
///
/// Each cut answers for its own frames in spans of one picture
/// ([PlaybackCacheBudget.playbackReadyRunsForCut]) — the bar used to ask
/// per frame, which zoomed out to a ten-minute film was 89% of a playback
/// tick (I-22). A frame belongs to the FIRST layout entry holding it, as
/// it always has; the edges are the only places that can change.
///
/// B1: a frame no cut owns is a GAP, and playback at a gap has no picture
/// of its own — no cut, so no paper and no fade — so there is nothing to
/// prepare and the gap is ready BY DEFINITION, the same two-kind law the
/// in-cut answer follows. (The
/// multitrack gap-PARKED preview showing other tracks is the EDITING
/// path, not playback — this bar answers for playback.)
List<ReadyRun> storyboardReadyRuns(
  EditorSessionManager session,
  int start,
  int end, {
  List<StoryboardTimelineLayoutEntry>? layout,
}) {
  final entries = [
    for (final entry in layout ?? storyboardActiveTrackLayout(session))
      if (entry.startFrame < end && entry.endFrame > start) entry,
  ];
  final edges = <int>{
    start,
    end,
    for (final entry in entries) ...[entry.startFrame, entry.endFrame],
    // Where any track's cut begins or ends, the film's stage — its lowest
    // track covered — may move, and with it which picture of a cut the
    // film shows ([DemandedPicture.paintPaper]).
    for (final entry in session.projectSettings.projectLayout())
      if (entry.startFrame < end && entry.endFrame > start) ...[
        entry.startFrame,
        entry.endFrame,
      ],
  }.where((frame) => frame >= start && frame <= end).toList()..sort();
  if (edges.length < 2) {
    return const [];
  }
  final owners = _firstOwners(entries, edges);
  // Where each cut's OWN frames stand on its track — the cache holds a
  // cut's pictures by the cut's own frame.
  final axis = session.projectSettings.projectAxis();
  final runs = <ReadyRun>[];
  for (var stretch = 0; stretch < owners.length; stretch += 1) {
    final from = edges[stretch];
    final to = edges[stretch + 1];
    final owner = owners[stretch];
    if (owner == null) {
      _append(runs, (
        startIndex: from,
        endIndexExclusive: to,
        unreadable: false,
      ));
      continue;
    }
    final ownFrom = axis.localIn(owner, from);
    final onTrack = from - ownFrom;
    // The FILM's bar: no canvas — the film plays on composites yet.
    for (final run
        in session.playbackRig.playbackCache.playbackReadyRunsForCut(
          owner.cut,
          ownFrom,
          ownFrom + (to - from),
          paintPaper: session.rowSpans
              .trackStackContributionsAt(from)
              .any(
                (shown) =>
                    shown.cut.id == owner.cutId && shown.isBottomTrack,
              ),
        )) {
      _append(runs, (
        startIndex: run.startIndex + onTrack,
        endIndexExclusive: run.endIndexExclusive + onTrack,
        unreadable: run.unreadable,
      ));
    }
  }
  return runs;
}

/// [run] at the end of [runs] — joined onto the last one where it starts as
/// that one ends and is as readable.
///
/// ⛔Not shared with the cut's own bar, which joins its spans the same way
/// (`PlaybackCacheBudget.playbackReadyRunsForCut`): the SECOND, and the
/// rule of three holds.
void _append(List<ReadyRun> runs, ReadyRun run) {
  final last = runs.isEmpty ? null : runs.last;
  if (last != null &&
      last.endIndexExclusive == run.startIndex &&
      last.unreadable == run.unreadable) {
    runs.last = (
      startIndex: last.startIndex,
      endIndexExclusive: run.endIndexExclusive,
      unreadable: run.unreadable,
    );
  } else {
    runs.add(run);
  }
}

/// Each stretch between two [edges] with the FIRST of [entries] covering
/// it: painted in layout order, a stretch keeps the owner it got first.
List<StoryboardTimelineLayoutEntry?> _firstOwners(
  List<StoryboardTimelineLayoutEntry> entries,
  List<int> edges,
) {
  final edgeAt = {for (var i = 0; i < edges.length; i += 1) edges[i]: i};
  final owners = List<StoryboardTimelineLayoutEntry?>.filled(
    edges.length - 1,
    null,
  );
  for (final entry in entries) {
    for (
      var stretch = edgeAt[math.max(entry.startFrame, edges.first)]!;
      stretch < owners.length && edges[stretch] < entry.endFrame;
      stretch += 1
    ) {
      owners[stretch] ??= entry;
    }
  }
  return owners;
}

/// Ruler seeks: playback seeks the clock; EDITING seeks are the session's
/// own global-axis seek ([EditorSessionManager.selectGlobalFrame]) — the
/// storyboard adds nothing of its own (R15-①: one model, both panels).
void seekStoryboardGlobalFrame(EditorSessionManager session, int globalFrame) {
  final playback = session.playbackRig.playback;
  if (playback.isActive) {
    if (playback.scope == PlaybackScope.allCuts) {
      playback.seekToGlobalFrame(globalFrame);
      return;
    }
    // Single-cut playback: its playlist counts the cut's OWN frames from
    // 0, and seeks outside the playing cut are a no-op.
    for (final entry in storyboardActiveTrackLayout(session)) {
      if (globalFrame >= entry.startFrame &&
          globalFrame < entry.endFrame &&
          entry.cutId == playback.position?.cutId) {
        playback.seekToGlobalFrame(
          session.projectSettings.projectAxis().localIn(entry, globalFrame),
        );
        return;
      }
    }
    return;
  }
  session.selectGlobalFrame(globalFrame);
}

/// A press that lands in a CUT at a frame of its OWN (I-73 ④) — the camera
/// row's: over an O.L its two lines name the cut by the line pressed, where
/// the track frame alone names the cut it stands under (an arriving cut's
/// のりしろ is the cut in front's place on the track). Playback seeks the
/// clock to where that frame plays ([seekStoryboardGlobalFrame]); editing
/// takes the cut and its frame, the stand [selectGlobalFrame] makes when the
/// track frame names that cut.
void seekStoryboardCutFrame(
  EditorSessionManager session,
  CutId cutId,
  int ownFrame,
) {
  if (session.playbackRig.playback.isActive) {
    final globalFrame = session.projectSettings.projectAxis().globalOf(
      cutId,
      ownFrame,
    );
    if (globalFrame != null) {
      seekStoryboardGlobalFrame(session, globalFrame);
    }
    return;
  }
  if (session.activeCutId != cutId) {
    session.selectCut(cutId);
  }
  session.selectFrameIndex(ownFrame);
}

// `parkStoryboardGlobalFrame` is gone with the law it carried (⑭): a press
// on a row that owns no cuts used to release the active cut "however many
// cuts sit under that frame on the V row" (feedback #7). That question only
// existed while several tracks could cover one frame. With one track the
// index names exactly one cut, so every row press is [seekStoryboardGlobalFrame]
// — whose gap branch still parks, which is the only thing the old verb did
// that anyone still needs.

/// Ruler drag moves: playback keeps seeking the clock per move; editing
/// scrubs are the session's global-axis scrub — the cursor path inside
/// the active cut's territory, and a QUIET per-move parking everywhere
/// else (gaps and other cuts' frames alike). Nothing commits per move;
/// the release lands the one full seek.
void scrubStoryboardGlobalFrame(EditorSessionManager session, int globalFrame) {
  if (session.playbackRig.playback.isActive) {
    seekStoryboardGlobalFrame(session, globalFrame);
    return;
  }
  session.frameScrub.scrubGlobalFrame(globalFrame);
}

/// The storyboard ruler drag's release: commits the scrubbed playhead once
/// (playback drags have nothing to commit).
void commitStoryboardScrub(EditorSessionManager session) {
  if (!session.playbackRig.playback.isActive) {
    session.frameScrub.commitFrameScrub();
    return;
  }
  // Playback took the transport mid-drag: there is no editing seek to
  // commit, but the scrub's FLAGS must not leak past the gesture — a
  // stuck scrub flag would freeze the canvas in scrub mode, and a stuck
  // gap flag would swallow the NEXT drag's gap edge (the D6 stale
  // picture, resurrected one drag per leak). One verb clears them all.
  session.frameScrub.abandonFrameScrubPreview();
}

/// Switching into the storyboard clamps an over-end playhead back onto the
/// CUT's last frame (UI-R9 #4 — the runway is a clipped view of the cut,
/// so tab-switching never lands the playhead in the trailing gap); the
/// track's last cut keeps its endless runway — so the frame counter and
/// the playhead line agree. Gap parkings (no active cut) need no clamp.
void clampPlayheadForStoryboard(EditorSessionManager session) {
  if (session.playbackRig.playback.isActive) {
    return;
  }
  final cutId = session.activeCutId;
  if (cutId == null) {
    return;
  }
  final axis = session.trackFrameAxis();
  final layout = axis.entries;
  final entry = axis.entryFor(cutId);
  if (entry == null) {
    return;
  }
  // The track's LAST cut keeps the endless runway (no next cut to leak
  // into); every other cut clamps to its own last frame.
  if (layout.isNotEmpty && layout.last.cutId == cutId) {
    return;
  }
  final maxLocal = entry.duration > 0 ? entry.duration - 1 : 0;
  if (session.currentFrameIndex > maxLocal) {
    session.selectFrameIndex(maxLocal);
  }
}
