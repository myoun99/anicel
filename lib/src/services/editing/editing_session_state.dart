import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import 'active_cut_helpers.dart';

class EditingSessionState {
  EditingSessionState({required CutId? activeCutId, TrackId? selectedTrackId})
    : _activeCutId = activeCutId,
      _selectedTrackId = selectedTrackId;

  factory EditingSessionState.forProject(Project project) {
    final activeCutId = defaultActiveCutIdFor(project);
    return EditingSessionState(
      activeCutId: activeCutId,
      selectedTrackId: trackIdOfCut(project, activeCutId),
    );
  }

  /// NULL = the editing playhead stands in a track GAP (UI-R9 #3): no cut
  /// is selected — the timeline/timesheet show their empty states and the
  /// canvas shows the void. Playback FOLLOW keeps the last cut through
  /// gaps; only editing seeks/scrub commits land here.
  CutId? _activeCutId;

  CutId? get activeCutId => _activeCutId;

  void setActiveCutId(CutId? cutId) {
    _activeCutId = cutId;
  }

  /// The SELECTED track — first-class state, the way the timeline's row
  /// selection is. It used to be DERIVED by hunting for whichever track
  /// owned the active cut, which meant it had nowhere to live whenever the
  /// playhead parked in a gap ([activeCutId] null) and the selection
  /// evaporated. The session reconciles the pair: an active cut still wins
  /// while there IS one, so the answer is identical to the old derivation,
  /// and this is what survives when there is not.
  TrackId? _selectedTrackId;

  TrackId? get selectedTrackId => _selectedTrackId;

  void setSelectedTrackId(TrackId? trackId) {
    _selectedTrackId = trackId;
  }

  /// Set while the editing playhead is PARKED IN A GAP (R16-⑥, user
  /// semantics: a gap has NO cut — the canvas shows a paperless void).
  /// Stores the exact global frame, which the leading gap before the
  /// first cut cannot express as any cut-local index. Notifier-backed
  /// (UI-R7 #9): gap scrubs park PER MOVE now, and the storyboard
  /// playhead must follow even where the cut-local cursor cannot change
  /// (the leading gap pins local 0).
  ///
  /// It lives beside [activeCutId] because the two are one question — where
  /// the editing playhead stands — answered for a cut and for no cut (the
  /// session-state audit's twenty-first family, 2026-09-29: it was the
  /// session's own field, read by six collaborators through a role).
  int? get gapGlobalFrame => _gapParking.value;

  set gapGlobalFrame(int? value) => _gapParking.value = value;

  /// Fires when the gap parking is set, moved or cleared — the storyboard
  /// playhead subscribes (per-move gap scrubs, UI-R7 #9).
  ValueListenable<int?> get gapParkingListenable => _gapParking;

  final ValueNotifier<int?> _gapParking = ValueNotifier<int?>(null);

  /// Whether the editing playhead sits in a gap (no cut there). During a
  /// LIVE global scrub the parking transiently addresses ANY
  /// out-of-active-cut position — another cut's frames included (the
  /// quiet-crossing drag) — so consumers outside the scrub-gated display
  /// path must not read a true here as "certainly between cuts" until the
  /// release resolves it into a selection or a real gap parking.
  /// 🚨★★★ T12 — A GAP PARKING IS THE ONLY WAY TO BE IN A GAP.
  ///
  /// This used to also ask `trackFrameAxis().isGap(editingGlobalFrame)`, and
  /// that term was DEAD CODE only because the global frame was clamped into
  /// the cut: a clamped frame is inside its own cut by construction, so the
  /// question could never come back true. Unclamping woke it up, and it
  /// immediately said the wrong thing — standing on frame 31 of a 24-frame
  /// cut lands on a global the axis calls a gap, so the canvas dropped its
  /// paper and its layers.
  ///
  /// ⛔That is precisely the law's negation: 「컷길이 넘어서도 **공간은 항상
  /// 존재하고 항상 보인다**」. If a cut is active you are standing IN it —
  /// anywhere in it, past its end line included. Only a global seek that
  /// parked with no cut is a gap, and [gapGlobalFrame] is exactly that
  /// state, held explicitly rather than inferred.
  ///
  /// ⚠️This is the sweep the getter's own doc promised whoever unclamped:
  /// the term did not need updating, it needed removing.
  bool get playheadInGap => gapGlobalFrame != null;

  void dispose() => _gapParking.dispose();
}
