import '../models/cut_id.dart';
import '../models/project.dart';
import '../models/track.dart';
import 'cut_list_helpers.dart';

/// The empty frames a deleted cut leaves standing in its place, and who
/// carries them.
///
/// ⑱ (user, 2026-08-12): 「컷 삭제는 그 자리에서 컷 하나를 지울 뿐이다.
/// 앞으로 재정렬하지 않고 스토리보드 엔드라인도 안 건드린다」 — and, on the
/// obvious follow-up question: 「삭제하고 다른거 붙이게하는 기능 넣을까요?
/// **이런거묻지마.** 그냥 지금 그런식으로 동작하도록」.
///
/// A cut occupies its leading gap PLUS its duration, so a plain list removal
/// slides everything after it that many frames earlier. Track order is the
/// sequence authority and a gap is an attribute of the BOUNDARY
/// ([Cut.leadingGapFrames]) — so the hole is handed to the next cut's
/// leading gap and nothing else in the project is renumbered.
class CutDeletionHole {
  const CutDeletionHole({required this.frames, required this.absorbedByCutId});

  /// Leading gap + duration of the cut being deleted.
  final int frames;

  /// The next cut in the SAME track, whose leading gap grows by [frames].
  ///
  /// Null when the cut is its track's last: there is no boundary left to
  /// hang a gap on, so that track ends earlier — and the movie's END LINE
  /// is held still by [Project.trailingFrames] instead (see
  /// [projectContentEndFrame]). Track-local on purpose: a cut's neighbours
  /// are the cuts on its own track.
  final CutId? absorbedByCutId;
}

CutDeletionHole cutDeletionHoleFor(
  Project project, {
  required CutId deletingCutId,
}) {
  for (final track in project.tracks) {
    final index = track.cuts.indexWhere((cut) => cut.id == deletingCutId);
    if (index == -1) {
      continue;
    }
    final cut = track.cuts[index];
    return CutDeletionHole(
      frames: cut.leadingGapFrames + cut.duration,
      absorbedByCutId: index + 1 < track.cuts.length
          ? track.cuts[index + 1].id
          : null,
    );
  }
  throw StateError('Project does not contain cut ${deletingCutId.value}.');
}

/// The last frame the project's CUTS reach — the movie's content end,
/// before [Project.trailingFrames].
///
/// The same cumulative pass the storyboard layout makes, kept here as well
/// because it is a fact about the model and a command cannot reach into the
/// UI for it.
int projectContentEndFrame(Project project) {
  var end = 0;
  for (final track in project.tracks) {
    final trackEnd = _trackContentEndFrame(track);
    if (trackEnd > end) {
      end = trackEnd;
    }
  }
  return end;
}

int _trackContentEndFrame(Track track) {
  var end = 0;
  for (final cut in track.cuts) {
    end += cut.leadingGapFrames + cut.duration;
  }
  return end;
}

/// R28 #14: [emptyTrack] replaced the old `createDefaultCut`. Deleting the
/// only cut leaves NO cut selected instead of conjuring a replacement —
/// "컷도 1개도 없는 상황 허용". The no-active-cut state is one the editor
/// already renders (a storyboard gap parks there), so nothing new had to
/// learn about it.
enum CutDeletionFallbackKind { useExistingCut, emptyTrack }

class CutDeletionFallbackDecision {
  const CutDeletionFallbackDecision.useExistingCut(this.cutId)
    : kind = CutDeletionFallbackKind.useExistingCut;

  const CutDeletionFallbackDecision.emptyTrack()
    : kind = CutDeletionFallbackKind.emptyTrack,
      cutId = null;

  final CutDeletionFallbackKind kind;
  final CutId? cutId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutDeletionFallbackDecision &&
          other.kind == kind &&
          other.cutId == cutId;

  @override
  int get hashCode => Object.hash(kind, cutId);

  @override
  String toString() =>
      'CutDeletionFallbackDecision(kind: $kind, cutId: $cutId)';
}

CutDeletionFallbackDecision cutDeletionFallbackFor(
  Project project, {
  required CutId deletingCutId,
}) {
  final cutIds = cutListEntriesFor(
    project,
  ).map((entry) => entry.cutId).toList(growable: false);
  final deletingCutIndex = cutIds.indexOf(deletingCutId);

  if (deletingCutIndex == -1) {
    throw StateError('Project does not contain cut ${deletingCutId.value}.');
  }

  if (deletingCutIndex > 0) {
    return CutDeletionFallbackDecision.useExistingCut(
      cutIds[deletingCutIndex - 1],
    );
  }

  if (cutIds.length > 1) {
    return CutDeletionFallbackDecision.useExistingCut(cutIds[1]);
  }

  return const CutDeletionFallbackDecision.emptyTrack();
}
