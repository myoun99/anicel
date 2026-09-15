import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
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
final class CutInsertion {
  CutInsertion({required this.trackId, required this.cut, this.index});

  final TrackId trackId;
  final Cut cut;

  /// The slot [cut] takes; null is after the track's last cut.
  final int? index;

  int? _resolvedIndex;

  /// The follower's leading gap before this cut took room out of it, kept so
  /// [revert] can hand the room back. Null when there is no follower.
  CutId? _absorbedFromCutId;
  late int _absorbedGapBefore;

  void apply(ProjectRepository repository) {
    _resolvedIndex ??= index ?? _track(repository).cuts.length;
    final follower = _followerOrNull(repository);
    _absorbedFromCutId = follower?.id;
    if (follower != null) {
      _absorbedGapBefore = follower.leadingGapFrames;
    }

    repository.insertCut(trackId: trackId, cut: cut, index: _resolvedIndex);

    final absorbedFrom = _absorbedFromCutId;
    if (absorbedFrom != null) {
      final footprint = cut.leadingGapFrames + cut.duration;
      final remaining = _absorbedGapBefore - footprint;
      repository.updateCutLeadingGap(
        cutId: absorbedFrom,
        leadingGapFrames: remaining < 0 ? 0 : remaining,
      );
    }
  }

  void revert(ProjectRepository repository) {
    repository.removeCut(cutId: cut.id);
    // ⛔Back to the RECORDED number rather than gap+footprint: the follower
    // may have had less room than this cut took, and adding the footprint
    // back would invent frames that were never there.
    final absorbedFrom = _absorbedFromCutId;
    if (absorbedFrom != null) {
      repository.updateCutLeadingGap(
        cutId: absorbedFrom,
        leadingGapFrames: _absorbedGapBefore,
      );
    }
  }

  /// The cut this one lands in FRONT of — the one whose leading gap is the
  /// free space the new cut is entitled to use. Null when appending.
  Cut? _followerOrNull(ProjectRepository repository) {
    final cuts = _track(repository).cuts;
    final at = _resolvedIndex!;
    return at < cuts.length ? cuts[at] : null;
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
