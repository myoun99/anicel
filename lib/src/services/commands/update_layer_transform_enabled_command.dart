import '../../models/layer_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// Flips a layer's TRANSFORM switch ([Layer.transformEnabled], R8) in one
/// undo step — the Transform group header's bypass, and half of what the
/// layer-label master writes (the other half being each effect's own
/// switch, through [UpdateLayerEffectsCommand]).
///
/// Repo-direct like the eye and the static opacity, and NOT mirrored across
/// a 겸용 link group: a bypass is per-use, exactly like the lane it bypasses
/// ("레인만 각자").
class UpdateLayerTransformEnabledCommand implements Command {
  UpdateLayerTransformEnabledCommand({
    required this.repository,
    required this.layerId,
    required this.transformEnabled,
    this.description = 'Toggle transform FX',
  });

  final ProjectRepository repository;
  final LayerId layerId;
  final bool transformEnabled;

  @override
  final String description;

  bool? _previous;

  @override
  void execute() {
    // Captured on the way through — one pass, so there is no second lookup
    // that could disagree about which row this is. `??=` keeps the FIRST
    // execute's value, which is what makes redo walk back to the same place.
    repository.updateLayer(
      layerId: layerId,
      update: (layer) {
        _previous ??= layer.transformEnabled;
        return layer.transformEnabled == transformEnabled
            ? layer
            : layer.copyWith(transformEnabled: transformEnabled);
      },
    );
  }

  @override
  void undo() {
    final previous = _previous;
    if (previous == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateLayer(
      layerId: layerId,
      update: (layer) => layer.transformEnabled == previous
          ? layer
          : layer.copyWith(transformEnabled: previous),
    );
  }
}
