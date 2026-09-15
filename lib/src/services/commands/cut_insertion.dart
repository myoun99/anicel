import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../editing/cut_insertion_room.dart';
import '../project_repository.dart';

/// A cut put INTO a track — at [index], or after the track's last cut — and
/// taken back out exactly as it went in.
///
/// ⛔ONE insertion for every new cut. Create Cut made room for its cut this
/// way while an import appended with a bare `insertCut`: harmless while an
/// import could only append (no cut follows it), wrong the moment a drop
/// puts a new cut at a frame (storyboard-drop-follows-the-timeline-law).
///
/// 🚨★★ 유저 #19 (2026-08-15): 「미는건 뒤에 공간없으면 밀어도되는데,
/// **공간이 여유분이 있는데도 여유분 뒤의 컷을 밀어버림**」
///
/// Cut positions are one cumulative pass over `leadingGap + duration`, so
/// a plain list splice slides EVERY following cut right by the new cut's
/// whole footprint — even when the room it needed was already sitting
/// there as the follower's leading gap.
///
/// ★This is deletion's rule read backwards. [cutDeletionHoleFor] hands a
/// removed cut's frames TO the next cut's leading gap so nothing after it
/// moves; creation takes them back out of that same gap, and only what
/// the gap could not cover becomes a push. Empty gap, no room, the
/// followers move exactly as far as they always did.
///
/// ↩️F-97 (유저 2026-09-12): 「근데 이런거 애초에 프레임블록 로직이랑
/// 똑같이 법 통일」. The room came out of the NEXT cut's gap alone, so a
/// push that gap could not hold moved every cut behind it, gaps or no
/// gaps. The push now travels the frame axis's way — each gap ahead
/// spent before it reaches the cut behind — and a 겸용 cut lands by the
/// same answer ([followerGapsAfterInsert]).
final class CutInsertion {
  CutInsertion({required this.trackId, required this.cut, this.index});

  final TrackId trackId;
  final Cut cut;

  /// The slot [cut] takes; null is after the track's last cut.
  final int? index;

  int? _resolvedIndex;

  /// The leading gaps of the cuts this one took room from, as they were —
  /// kept so [revert] can hand the room back.
  Map<CutId, int> _gapsBefore = const {};

  void apply(ProjectRepository repository) {
    final cuts = _track(repository).cuts;
    _resolvedIndex ??= index ?? cuts.length;
    final gaps = followerGapsAfterInsert(
      cuts,
      index: _resolvedIndex!,
      leadingGap: cut.leadingGapFrames,
      duration: cut.duration,
    );
    _gapsBefore = {
      for (final follower in cuts)
        if (gaps.containsKey(follower.id))
          follower.id: follower.leadingGapFrames,
    };

    repository.insertCut(trackId: trackId, cut: cut, index: _resolvedIndex);
    for (final MapEntry(key: cutId, value: gap) in gaps.entries) {
      repository.updateCutLeadingGap(cutId: cutId, leadingGapFrames: gap);
    }
  }

  void revert(ProjectRepository repository) {
    repository.removeCut(cutId: cut.id);
    // ⛔Back to the RECORDED numbers rather than gap+footprint: a follower
    // may have had less room than this cut took, and adding the footprint
    // back would invent frames that were never there.
    for (final MapEntry(key: cutId, value: gap) in _gapsBefore.entries) {
      repository.updateCutLeadingGap(cutId: cutId, leadingGapFrames: gap);
    }
  }

  Track _track(ProjectRepository repository) {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    throw StateError('Track not found: $trackId');
  }
}
