import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import '../editing/cut_insertion_room.dart';
import '../project_repository.dart';
import '../project_tree_editor.dart';
import 'transitions_ride_the_cuts.dart';

/// [project] with [cut] put into [trackId] at [index] — after the track's
/// last cut when null — and the leading gaps of the cuts it took room
/// from, AS THEY WERE: what [projectWithCutTakenOut] hands the room back by.
///
/// ⛔THE ONE INSERTION, as a write on a project ([CutInsertion]'s law, which
/// see for why). [CutInsertion] makes it a write of its own. 겸용컷 생성
/// makes it part of ITS write, because the link registry it records names
/// the cut it is written with — and that is the one reason the law is a
/// function as well as an object.
///
/// ↩️That command re-wrote this arithmetic inside its own project write
/// (found 2026-09-30, `duplicate-cut-skips-the-insertion-law`): the same
/// answer, spelt twice — 유저 #19 · F-97 「법 하나로 통일」.
({Project project, Map<CutId, int> gapsBefore}) projectWithCutInserted(
  Project project, {
  required TrackId trackId,
  required Cut cut,
  int? index,
}) {
  final track = project.tracks.firstWhere(
    (track) => track.id == trackId,
    orElse: () => throw StateError('Track not found: $trackId'),
  );
  final cuts = track.cuts;
  final at = index ?? cuts.length;
  final gaps = followerGapsAfterInsert(
    cuts,
    index: at,
    leadingGap: cut.leadingGapFrames,
    duration: cut.duration,
  );
  return (
    project: project.copyWith(
      tracks: [
        for (final other in project.tracks)
          if (other.id != trackId)
            other
          else
            other.copyWith(
              cuts: [
                for (final follower in cuts)
                  if (gaps.containsKey(follower.id))
                    follower.copyWith(leadingGapFrames: gaps[follower.id])
                  else
                    follower,
              ]..insert(at, cut),
            ),
      ],
    ),
    gapsBefore: {
      for (final follower in cuts)
        if (gaps.containsKey(follower.id))
          follower.id: follower.leadingGapFrames,
    },
  );
}

/// The way back: [cutId] out of [project], and the room handed back.
///
/// ⛔Back to the RECORDED numbers rather than gap+footprint: a follower may
/// have had less room than the cut took, and adding the footprint back
/// would invent frames that were never there.
Project projectWithCutTakenOut(
  Project project, {
  required CutId cutId,
  required Map<CutId, int> gapsBefore,
}) {
  final without = removeCutAnywhere(project, cutId);
  if (without.removed == null) {
    throw StateError('Cut not found: $cutId');
  }
  var next = without.project;
  for (final MapEntry(key: followerId, value: gap) in gapsBefore.entries) {
    next =
        updateCutAnywhere(
          next,
          followerId,
          (follower) => follower.copyWith(leadingGapFrames: gap),
        ) ??
        next;
  }
  return next;
}

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

  /// The transition rows this insertion moved — made on the first apply,
  /// with the repository it was handed.
  TransitionsRideTheCuts? _ride;

  void apply(ProjectRepository repository) =>
      (_ride ??= TransitionsRideTheCuts(repository)).carry(
        () => _apply(repository),
      );

  void revert(ProjectRepository repository) =>
      (_ride ??= TransitionsRideTheCuts(repository)).carryBack(
        () => _revert(repository),
      );

  /// ONE write for the cut and the room it takes ([projectWithCutInserted]).
  /// ↩️It was the insert and then a write per follower's gap.
  void _apply(ProjectRepository repository) =>
      repository.updateProject((project) {
        final inserted = projectWithCutInserted(
          project,
          trackId: trackId,
          cut: cut,
          // Resolved once: a redo lands where the first apply did.
          index: _resolvedIndex ??= index ?? _cutCountIn(project),
        );
        _gapsBefore = inserted.gapsBefore;
        return inserted.project;
      });

  void _revert(ProjectRepository repository) => repository.updateProject(
    (project) => projectWithCutTakenOut(
      project,
      cutId: cut.id,
      gapsBefore: _gapsBefore,
    ),
  );

  int _cutCountIn(Project project) {
    for (final track in project.tracks) {
      if (track.id == trackId) {
        return track.cuts.length;
      }
    }
    throw StateError('Track not found: $trackId');
  }
}
