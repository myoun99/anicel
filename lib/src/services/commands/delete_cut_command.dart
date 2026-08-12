import '../../controllers/cut_deletion_helpers.dart';
import '../../controllers/editing_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import '../brush_frame_store.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

class DeleteCutCommand implements Command {
  DeleteCutCommand({
    required this.repository,
    required this.editingSession,
    required this.cutId,
    this.brushFrameStore,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final CutId cutId;

  /// Needed when the deleted cut holds a CANONICAL link member: the
  /// surviving member promotes and the cels re-key onto it.
  final BrushFrameStore? brushFrameStore;

  // R28 #14: the replacement-cut inputs are gone. Deleting the only cut
  // empties the track instead of conjuring a stand-in.

  Cut? _deletedCut;
  TrackId? _originalTrackId;
  int? _originalIndex;
  CutId? _previousActiveCutId;
  LayerLinkRegistry? _registryBefore;
  final List<(BrushFrameKey, BrushFrameKey)> _rekeys = [];
  bool _hasExecuted = false;

  /// ⑱'s two undo anchors: the neighbour whose leading gap grew, and the
  /// movie's trailing gap. Both are restored to the exact numbers they held,
  /// never by subtracting back — an edit in between would make arithmetic
  /// undo the wrong thing.
  CutId? _absorbedByCutId;
  int? _absorbedGapBefore;
  int? _trailingFramesBefore;

  @override
  String get description => 'Delete cut $cutId';

  @override
  void execute() {
    final project = repository.requireProject();
    final location = _findCutLocation(cutId);
    final previousActiveCutId = editingSession.activeCutId;
    final isDeletingActiveCut = previousActiveCutId == cutId;
    final fallbackDecision = isDeletingActiveCut
        ? cutDeletionFallbackFor(project, deletingCutId: cutId)
        : null;

    // ⑱: what the cut leaves behind. Measured BEFORE anything moves.
    final hole = cutDeletionHoleFor(project, deletingCutId: cutId);
    final contentEndBefore = projectContentEndFrame(project);
    final absorbedByCutId = hole.absorbedByCutId;

    _previousActiveCutId = previousActiveCutId;
    _originalTrackId = location.trackId;
    _originalIndex = location.index;
    _absorbedByCutId = absorbedByCutId;
    _absorbedGapBefore = absorbedByCutId == null
        ? null
        : requireCut(project, absorbedByCutId).leadingGapFrames;
    _trailingFramesBefore = project.trailingFrames;
    // 링크 정리 BEFORE the cut leaves: dead members must never linger in
    // the registry (mirror fan-outs would hit missing layers). A deleted
    // CANONICAL member promotes the first survivor — its cels re-key
    // onto the new canonical address so pixels keep routing.
    if (_registryBefore == null) {
      _registryBefore = project.linkRegistry;
      _planRegistrySweep(project);
    }
    if (_rekeys.isNotEmpty) {
      brushFrameStore?.rekeyFrames(_rekeys);
    }
    repository.updateProject(
      (current) => current.copyWith(
        linkRegistry: _sweptRegistry(current.linkRegistry),
      ),
    );
    _deletedCut = repository.removeCut(cutId: cutId);

    // ⑱: the removal itself is a list operation, so the frames the cut held
    // have to be handed to something or every cut after it slides earlier.
    if (absorbedByCutId != null && hole.frames > 0) {
      repository.updateCutLeadingGap(
        cutId: absorbedByCutId,
        leadingGapFrames: _absorbedGapBefore! + hole.frames,
      );
    }
    // …and the movie's END LINE does not move either. Stated as "top the
    // trailing gap up by however much the content shrank" rather than as a
    // second branch of the case above: with a neighbour to absorb the hole
    // the content end never moved, so this adds nothing — one rule covers
    // the last cut of a track, the last track, and neither.
    final contentEndAfter = projectContentEndFrame(repository.requireProject());
    final shrink = contentEndBefore - contentEndAfter;
    if (shrink > 0) {
      repository.updateProject(
        (current) =>
            current.copyWith(trailingFrames: current.trailingFrames + shrink),
      );
    }

    if (!isDeletingActiveCut) {
      _hasExecuted = true;
      return;
    }

    switch (fallbackDecision!.kind) {
      case CutDeletionFallbackKind.useExistingCut:
        editingSession.setActiveCutId(fallbackDecision.cutId!);
        break;
      // R28 #14: the track simply empties. No replacement cut is created
      // and nothing is active — the same state a storyboard gap parks in.
      case CutDeletionFallbackKind.emptyTrack:
        editingSession.setActiveCutId(null);
        break;
    }

    _hasExecuted = true;
  }

  @override
  void undo() {
    final deletedCut = _deletedCut;
    final originalTrackId = _originalTrackId;
    final originalIndex = _originalIndex;
    final previousActiveCutId = _previousActiveCutId;
    if (!_hasExecuted ||
        deletedCut == null ||
        originalTrackId == null ||
        originalIndex == null ||
        previousActiveCutId == null) {
      throw StateError('Command has not been executed.');
    }

    repository.insertCut(
      trackId: originalTrackId,
      cut: deletedCut,
      index: originalIndex,
    );
    // ⑱ backwards: the neighbour gives the hole back and the movie's tail
    // returns to what it was.
    final absorbedByCutId = _absorbedByCutId;
    if (absorbedByCutId != null) {
      repository.updateCutLeadingGap(
        cutId: absorbedByCutId,
        leadingGapFrames: _absorbedGapBefore!,
      );
    }
    final trailingFramesBefore = _trailingFramesBefore;
    if (trailingFramesBefore != null) {
      repository.updateProject(
        (current) => current.copyWith(trailingFrames: trailingFramesBefore),
      );
    }
    if (_rekeys.isNotEmpty) {
      brushFrameStore?.rekeyFrames([
        for (final (from, to) in _rekeys) (to, from),
      ]);
    }
    final registryBefore = _registryBefore;
    if (registryBefore != null) {
      repository.updateProject(
        (current) => current.copyWith(linkRegistry: registryBefore),
      );
    }
    editingSession.setActiveCutId(previousActiveCutId);
  }

  /// Computes the canonical promotions this deletion forces and queues
  /// the cel re-keys (old canonical address → surviving member's).
  void _planRegistrySweep(Project project) {
    for (final group in project.linkRegistry.groups) {
      if (group.canonical.cutId != cutId) {
        continue;
      }
      final survivors = [
        for (final member in group.members)
          if (member.cutId != cutId) member,
      ];
      if (survivors.isEmpty) {
        continue; // Whole group dies with the cut — nothing to promote.
      }
      // Even a lone survivor (group dissolves) needs the cels re-keyed
      // onto itself, or its now self-resolving reads find nothing.
      final promoted = survivors.first;
      final oldCanonicalLayer = requireLayer(
        project,
        cutId: cutId,
        layerId: group.canonical.layerId,
      );
      for (final frame in oldCanonicalLayer.frames) {
        _rekeys.add((
          BrushFrameKey(
            projectId: project.id,
            trackId: group.canonical.trackId,
            cutId: group.canonical.cutId,
            layerId: group.canonical.layerId,
            frameId: frame.id,
          ),
          BrushFrameKey(
            projectId: project.id,
            trackId: promoted.trackId,
            cutId: promoted.cutId,
            layerId: promoted.layerId,
            frameId: frame.id,
          ),
        ));
      }
    }
  }

  /// [registry] with every member of the deleted cut removed; singleton
  /// leftovers dissolve. Surviving members keep their order, so the
  /// promoted canonical is exactly the one [_planRegistrySweep] re-keyed
  /// onto.
  LayerLinkRegistry _sweptRegistry(LayerLinkRegistry registry) {
    final groups = <LayerLinkGroup>[];
    for (final group in registry.groups) {
      final survivors = [
        for (final member in group.members)
          if (member.cutId != cutId) member,
      ];
      if (survivors.length >= 2) {
        groups.add(group.copyWith(members: survivors));
      }
    }
    return LayerLinkRegistry(groups: groups);
  }

  _CutLocation _findCutLocation(CutId cutId) {
    final project = repository.requireProject();
    for (final track in project.tracks) {
      final cutIndex = track.cuts.indexWhere((cut) => cut.id == cutId);
      if (cutIndex != -1) {
        return _CutLocation(trackId: track.id, index: cutIndex);
      }
    }

    throw StateError('Cut not found: $cutId');
  }
}

class _CutLocation {
  const _CutLocation({required this.trackId, required this.index});

  final TrackId trackId;
  final int index;
}
