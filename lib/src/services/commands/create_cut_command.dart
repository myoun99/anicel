import '../../controllers/default_cut_helpers.dart';
import '../../controllers/editing_session_state.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

class CreateCutCommand implements Command {
  CreateCutCommand({
    required this.repository,
    required this.editingSession,
    required this.trackId,
    required CutId cutId,
    required LayerId layerId,
    required String name,
    this.index,
    CanvasSize canvasSize = defaultCutCanvasSize,
  }) : cut = createDefaultCut(
         cutId: cutId,
         name: name,
         layerId: layerId,
         canvasSize: canvasSize,
       );

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final TrackId trackId;
  final int? index;
  final Cut cut;

  CutId? _previousActiveCutId;
  int? _resolvedIndex;
  bool _hasExecuted = false;

  /// The follower's leading gap before this cut took room out of it, kept so
  /// undo can hand the room back. Null when there is no follower.
  CutId? _absorbedFromCutId;
  int? _absorbedGapBefore;

  @override
  String get description => 'Create cut ${cut.name}';

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    _resolvedIndex ??= index ?? _cutCountForTrack();

    // 🚨★★ 유저 #19 (2026-08-15): 「미는건 뒤에 공간없으면 밀어도되는데,
    // **공간이 여유분이 있는데도 여유분 뒤의 컷을 밀어버림**」
    //
    // Cut positions are one cumulative pass over `leadingGap + duration`, so
    // a plain list splice slides EVERY following cut right by the new cut's
    // whole footprint — even when the room it needed was already sitting
    // there as the follower's leading gap.
    //
    // ★This is deletion's rule read backwards. [cutDeletionHoleFor] hands a
    // removed cut's frames TO the next cut's leading gap so nothing after it
    // moves; creation takes them back out of that same gap, and only what
    // the gap could not cover becomes a push. Empty gap, no room, the
    // followers move exactly as far as they always did.
    final follower = _followerCutOrNull();
    if (follower != null) {
      _absorbedFromCutId = follower.id;
      _absorbedGapBefore = follower.leadingGapFrames;
    }

    repository.insertCut(trackId: trackId, cut: cut, index: _resolvedIndex);

    final absorbedFrom = _absorbedFromCutId;
    if (absorbedFrom != null) {
      final footprint = cut.leadingGapFrames + cut.duration;
      final remaining = _absorbedGapBefore! - footprint;
      repository.updateCutLeadingGap(
        cutId: absorbedFrom,
        leadingGapFrames: remaining < 0 ? 0 : remaining,
      );
    }

    editingSession.setActiveCutId(cut.id);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousActiveCutId = _previousActiveCutId;
    if (!_hasExecuted || previousActiveCutId == null) {
      throw StateError('Command has not been executed.');
    }

    repository.removeCut(cutId: cut.id);
    // ⛔The gap goes back BEFORE the active cut does, and it goes back to the
    // recorded number rather than gap+footprint: the follower may have had
    // less room than this cut took, and adding the footprint back would
    // invent frames that were never there.
    final absorbedFrom = _absorbedFromCutId;
    if (absorbedFrom != null) {
      repository.updateCutLeadingGap(
        cutId: absorbedFrom,
        leadingGapFrames: _absorbedGapBefore!,
      );
    }
    editingSession.setActiveCutId(previousActiveCutId);
  }

  /// The cut this one will land in FRONT of — the one whose leading gap is
  /// the free space the new cut is entitled to use. Null when appending.
  Cut? _followerCutOrNull() {
    final project = repository.requireProject();
    for (final track in project.tracks) {
      if (track.id != trackId) {
        continue;
      }
      final at = _resolvedIndex!;
      return at < track.cuts.length ? track.cuts[at] : null;
    }
    throw StateError('Track not found: $trackId');
  }

  int _cutCountForTrack() {
    final project = repository.requireProject();
    for (final track in project.tracks) {
      if (track.id == trackId) {
        return track.cuts.length;
      }
    }

    throw StateError('Track not found: $trackId');
  }
}
