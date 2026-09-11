part of '../cut_command_coordinator.dart';

/// THE TRACK COMMANDS — a track's effects, display, SE order, and a
/// layer's transform track — as their own object.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: two coordinator members
/// shared. It reaches the coordinator through `_coordinator`.
class _TrackCommands {
  _TrackCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  /// Replaces the V track's EFFECT CHAIN; one undo step, no-op when
  /// unchanged.
  ///
  /// No 겸용 mirror and no value merge, unlike [_coordinator.updateLayerEffects]: a track
  /// is held once (there is no second use of it to keep in step), so the
  /// chain — shape and numbers together — is simply the track's.
  void updateTrackEffects({
    required TrackId trackId,
    required List<LayerEffect> effects,
    String description = 'Edit track effects',
  }) {
    for (final track in _coordinator.repository.requireProject().tracks) {
      if (track.id != trackId) {
        continue;
      }
      if (listEquals(track.effects, effects)) {
        return;
      }
      break;
    }
    _coordinator.historyManager.execute(
      UpdateTrackEffectsCommand(
        repository: _coordinator.repository,
        trackId: trackId,
        effects: effects,
        description: description,
      ),
    );
  }

  /// The V track's static opacity and fx master (R9 #21) in one undo step;
  /// no-op when nothing changes.
  void updateTrackDisplay({
    required TrackId trackId,
    double? opacity,
    bool? fxEnabled,
    String description = 'Edit track display',
  }) {
    for (final track in _coordinator.repository.requireProject().tracks) {
      if (track.id == trackId) {
        final sameOpacity = opacity == null || track.opacity == opacity;
        final sameFx = fxEnabled == null || track.fxEnabled == fxEnabled;
        if (sameOpacity && sameFx) {
          return;
        }
        break;
      }
    }

    _coordinator.historyManager.execute(
      UpdateTrackDisplayCommand(
        repository: _coordinator.repository,
        trackId: trackId,
        opacity: opacity,
        fxEnabled: fxEnabled,
        description: description,
      ),
    );
  }

  /// Replaces a layer's transform track; one undo step, no-op when
  /// unchanged. Camera layers keep their own track on the cut (the camera
  /// panel/lanes edit that one).
  void updateLayerTransformTrack({
    required CutId cutId,
    required LayerId layerId,
    required TransformTrack transformTrack,
    String description = 'Edit layer transform',
  }) {
    // Anywhere lookup, like the name tag above — SE rows are TRACK
    // fixtures and the cut-scoped read throws for them, which is what
    // stood between R5 #8's converted lane edits and the project.
    final layer = requireLayerAnywhere(
      _coordinator.repository.requireProject(),
      layerId,
    );
    if (!layer.kind.hasLayerTransform) {
      throw StateError(
        'The camera layer transforms through the cut camera track.',
      );
    }
    if (layer.transformTrack == transformTrack) {
      return;
    }

    // "Same name, same value" — the transform law, one for a layer's lanes
    // and a cut's camera ([namedTransformWrites]).
    final commands = <Command>[
      for (final write in namedTransformWrites(
        _coordinator.repository.requireProject(),
        cutId: cutId,
        layerId: layerId,
        after: transformTrack,
      ))
        UpdateLayerTransformCommand(
          repository: _coordinator.repository,
          cutId: write.cutId,
          layerId: write.layerId,
          transformTrack: write.track,
          description: description,
        ),
    ];

    _coordinator.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
    );
  }

  /// The transform track that ALREADY holds [name] in [property]'s lane,
  /// anywhere in this row's naming space — the row itself AND its 겸용
  /// siblings, a camera row's read off its cut ([transformTrackOfRow]). Null
  /// when the name is free, which is what tells a rename it can simply
  /// apply.
  ///
  /// The space is keyed by the LINK GROUP because a transform has no
  /// equivalent of the effect id that carries an FX naming space across
  /// cuts: sibling rows are different [LayerId]s holding the same part, and
  /// [linkMirrorTargets] is exactly that group. Returning the TRACK rather
  /// than a bool lets the joining key adopt from it — the two questions a
  /// rename asks have one answer.
  TransformTrack? transformTrackHoldingName({
    required CutId cutId,
    required LayerId layerId,
    required TransformPropertyId property,
    required String name,
    Set<int> excludeFramesOnSource = const {},
  }) {
    final project = _coordinator.repository.requireProject();
    for (final target in linkMirrorTargets(
      project,
      cutId: cutId,
      layerId: layerId,
    )) {
      final isSource = target.cutId == cutId && target.layerId == layerId;
      final track = transformTrackOfRow(
        project,
        cutId: target.cutId,
        layerId: target.layerId,
      );
      if (transformLaneUsesName(
        track,
        property,
        name,
        // Only the SOURCE row holds the keys a range rename is naming; a
        // sibling's keys are all "somewhere else" by construction.
        excludeFrames: isSource ? excludeFramesOnSource : const {},
      )) {
        return track;
      }
    }
    return null;
  }

  /// Resequences a track's SE rows. They live on the TRACK, so no cut and
  /// no mirror is involved — the order is the whole placement.
  void setTrackSeOrder({
    required TrackId trackId,
    required List<LayerId> order,
  }) {
    _coordinator.historyManager.execute(
      SetTrackSeOrderCommand(
        repository: _coordinator.repository,
        trackId: trackId,
        order: order,
      ),
    );
  }

  Track _requireTrack(TrackId trackId) {
    for (final track in _coordinator.repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    throw StateError('Track not found: $trackId');
  }
}
