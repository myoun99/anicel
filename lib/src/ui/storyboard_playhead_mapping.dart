/// Track-global frame mapping between the session and the storyboard panel:
/// the active track's cuts laid end to end (the same layout allCuts
/// playback plays). Free functions so the storyboard host AND the tab host
/// (playhead clamp on tab switch) share one implementation.
library;

import '../models/track_frame_axis.dart';
import 'editor_session_manager.dart';
import 'playback/canvas_playback_controller.dart';
import 'storyboard_timeline_layout.dart';

/// The SELECTED track's layout entries (every entry as fallback when that
/// track holds no cuts). Reads the session's first-class track selection
/// rather than hunting for the active cut's owner, so a playhead parked in
/// a gap keeps addressing the same track.
List<StoryboardTimelineLayoutEntry> storyboardActiveTrackLayout(
  EditorSessionManager session,
) {
  final layout = buildStoryboardTimelineLayout(
    session.repository.requireProject(),
  );
  final trackId = session.selectedTrackId;
  final scoped = [
    for (final entry in layout)
      if (entry.trackId == trackId) entry,
  ];
  return scoped.isEmpty ? layout : scoped;
}

/// "To start" (REC1-B): the first cut's first frame — where an all-cuts
/// play would begin.
///
/// A free function for the same reason the two above are: the storyboard's
/// transport left its panel for the 문턱 (유저 확정, 2026-08-10), so the
/// button that calls this is built by the WORKSPACE now while the host still
/// owns the layout cache. One implementation, two callers.
void seekStoryboardPlayheadToTrackStart(
  EditorSessionManager session, {
  List<StoryboardTimelineLayoutEntry>? layout,
}) {
  final entries = layout ?? storyboardActiveTrackLayout(session);
  if (entries.isEmpty) {
    return;
  }
  final firstCutId = entries.first.cutId;
  if (session.activeCutOrNull?.id != firstCutId) {
    session.selectCut(firstCutId);
  }
  session.selectFrameIndex(0);
}

/// Where the storyboard playhead sits: the playback position while playback
/// is active (an activeCut-scope playlist is rebased to frame 0, so map
/// through the cut's track slot), the editing playhead otherwise. An
/// over-end playhead on the track's LAST cut stays unclamped — it lives in
/// the endless runway, exactly like the timeline shows it.
///
/// [layout] takes a prebuilt active-track layout so per-tick callers
/// (the storyboard host's playhead refresh) don't rebuild it every frame
/// (R12-⑥); omitted, it is derived here.
int? storyboardPlayheadFrame(
  EditorSessionManager session, {
  List<StoryboardTimelineLayoutEntry>? layout,
}) {
  final playback = session.playback;
  // All-cuts playback speaks TRACK-GLOBAL frames directly — including the
  // GAP frames between cuts, where there is no cut position to map
  // through (R10-⑤: the ruler must keep moving through gaps).
  if (playback.isActive && playback.scope == PlaybackScope.allCuts) {
    final global = playback.globalFrameIndexListenable.value;
    if (global != null) {
      return global;
    }
  }
  layout ??= storyboardActiveTrackLayout(session);
  final playbackPosition = session.playback.isActive
      ? session.playback.position
      : null;
  if (playbackPosition == null) {
    // Editing playhead: a GAP PARKING reads its exact stored global
    // (R16-⑥); otherwise the playhead clamps to the CUT's last frame
    // (UI-R9 #4 — the timeline's over-end runway is a clipped view of
    // the cut, never the trailing gap) — the same math the session's
    // editingGlobalFrame speaks. No cut + no parking = no playhead.
    final parked = session.gapParkedGlobalFrame;
    if (parked != null) {
      return parked;
    }
    final cutId = session.activeCutId;
    if (cutId == null) {
      return null;
    }
    return TrackFrameAxis(
      layout,
    ).clampedToCutGlobalOf(cutId, session.currentFrameIndex);
  }
  for (final entry in layout) {
    if (entry.cutId == playbackPosition.cutId) {
      final maxLocal = entry.duration > 0 ? entry.duration - 1 : 0;
      return entry.startFrame +
          playbackPosition.localFrameIndex.clamp(0, maxLocal);
    }
  }
  return null;
}

/// Whether the track-global [globalFrame]'s playback composite is warmed —
/// the storyboard ruler's green bar. [layout] takes a prebuilt layout: the
/// ruler asks PER VISIBLE FRAME per repaint, and rebuilding the whole
/// track layout for each column was a fixed per-tick tax (R12-⑥).
bool storyboardFrameReady(
  EditorSessionManager session,
  int globalFrame, {
  List<StoryboardTimelineLayoutEntry>? layout,
}) {
  for (final entry in layout ?? storyboardActiveTrackLayout(session)) {
    if (globalFrame >= entry.startFrame && globalFrame < entry.endFrame) {
      return session.isPlaybackFrameReadyForCut(
        entry.cut,
        globalFrame - entry.startFrame,
      );
    }
  }
  return false;
}

/// The layout entry that OWNS [globalFrame] — delegates to the ONE
/// structural axis model ([TrackFrameAxis.ownerOf], R15-①).
StoryboardTimelineLayoutEntry? storyboardEntryOwningFrame(
  List<StoryboardTimelineLayoutEntry> layout,
  int globalFrame,
) => TrackFrameAxis(layout).ownerOf(globalFrame);

/// Ruler seeks: playback seeks the clock; EDITING seeks are the session's
/// own global-axis seek ([EditorSessionManager.selectGlobalFrame]) — the
/// storyboard adds nothing of its own (R15-①: one model, both panels).
void seekStoryboardGlobalFrame(EditorSessionManager session, int globalFrame) {
  final playback = session.playback;
  if (playback.isActive) {
    if (playback.scope == PlaybackScope.allCuts) {
      playback.seekToGlobalFrame(globalFrame);
      return;
    }
    // Single-cut playback: its playlist is rebased to frame 0, and seeks
    // outside the playing cut are a no-op.
    for (final entry in storyboardActiveTrackLayout(session)) {
      if (globalFrame >= entry.startFrame &&
          globalFrame < entry.endFrame &&
          entry.cutId == playback.position?.cutId) {
        playback.seekToGlobalFrame(globalFrame - entry.startFrame);
        return;
      }
    }
    return;
  }
  session.selectGlobalFrame(globalFrame);
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
  if (session.playback.isActive) {
    seekStoryboardGlobalFrame(session, globalFrame);
    return;
  }
  session.scrubGlobalFrame(globalFrame);
}

/// The storyboard ruler drag's release: commits the scrubbed playhead once
/// (playback drags have nothing to commit).
void commitStoryboardScrub(EditorSessionManager session) {
  if (!session.playback.isActive) {
    session.commitFrameScrub();
    return;
  }
  // Playback took the transport mid-drag: there is no editing seek to
  // commit, but the preview flag must not leak past the gesture — stuck
  // true it would freeze the canvas in scrub-preview mode after the
  // playback stops.
  session.frameScrubActive.value = false;
}

/// Switching into the storyboard clamps an over-end playhead back onto the
/// CUT's last frame (UI-R9 #4 — the runway is a clipped view of the cut,
/// so tab-switching never lands the playhead in the trailing gap); the
/// track's last cut keeps its endless runway — so the frame counter and
/// the playhead line agree. Gap parkings (no active cut) need no clamp.
void clampPlayheadForStoryboard(EditorSessionManager session) {
  if (session.playback.isActive) {
    return;
  }
  final cutId = session.activeCutId;
  if (cutId == null) {
    return;
  }
  final layout = storyboardActiveTrackLayout(session);
  final entry = TrackFrameAxis(layout).entryFor(cutId);
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
