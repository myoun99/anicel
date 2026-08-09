import '../../models/cut_id.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Replaces a layer's whole EFFECT CHAIN in one undo step (R6).
///
/// Adding, removing, re-parameterizing and keyframing an effect are all
/// computed as pure functions on the chain and committed here — the same
/// shape [UpdateLayerTransformCommand] gives the transform lanes, so one
/// lane drag is one undo whichever kind of FX it edited.
class UpdateLayerEffectsCommand implements Command {
  UpdateLayerEffectsCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.effects,
    this.description = 'Edit layer effects',
  });

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;
  final List<LayerEffect> effects;

  @override
  final String description;

  List<LayerEffect>? _previousEffects;
  bool _hasExecuted = false;

  @override
  void execute() {
    // ANYWHERE lookup, like the transform twin: a track-owned SE row is
    // not in any cut, and the repository writer already searches both.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    _previousEffects ??= layer.effects;

    repository.updateLayerEffects(
      cutId: cutId,
      layerId: layerId,
      effects: effects,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousEffects = _previousEffects;
    if (!_hasExecuted || previousEffects == null) {
      throw StateError('Command has not been executed.');
    }

    requireLayerAnywhere(repository.requireProject(), layerId);
    repository.updateLayerEffects(
      cutId: cutId,
      layerId: layerId,
      effects: previousEffects,
    );
  }
}
