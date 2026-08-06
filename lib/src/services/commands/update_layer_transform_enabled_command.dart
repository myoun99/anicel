import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';

/// Flips a layer's TRANSFORM switch ([Layer.transformEnabled], R8) in one
/// undo step — the Transform group header's bypass, and half of what the
/// layer-label master writes (the other half being each effect's own
/// switch, through [UpdateLayerEffectsCommand]).
///
/// Repo-direct like the eye and the static opacity, and MIRRORED across a
/// 겸용 link group (user 2026-08-06): a switch says whether the row has
/// that FX at all, which is structure — the same reason an effect's own
/// `enabled` mirrors. Only the lane it bypasses stays per-use, so every
/// member SETS the written value rather than toggling its own (per-member
/// toggling could freeze a divergent state forever — the eye's rule).
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

  /// Per-member previous values: linked rows may start out disagreeing, so
  /// one remembered bool would flatten them on undo.
  Map<LayerId, bool>? _previous;

  List<LayerId> _targets() {
    final project = repository.requireProject();
    final cutId = cutIdOfLayer(project, layerId);
    if (cutId == null) {
      return [layerId];
    }
    return [
      for (final target in linkMirrorTargets(
        project,
        cutId: cutId,
        layerId: layerId,
      ))
        target.layerId,
    ];
  }

  @override
  void execute() {
    // Captured on the way through — one pass, so there is no second lookup
    // that could disagree about which row this is. `??=` keeps the FIRST
    // execute's values, which is what makes redo walk back to the same place.
    final previous = _previous ??= <LayerId, bool>{};
    for (final target in _targets()) {
      repository.updateLayer(
        layerId: target,
        update: (layer) {
          previous.putIfAbsent(target, () => layer.transformEnabled);
          return layer.transformEnabled == transformEnabled
              ? layer
              : layer.copyWith(transformEnabled: transformEnabled);
        },
      );
    }
  }

  @override
  void undo() {
    final previous = _previous;
    if (previous == null) {
      throw StateError('Command has not been executed.');
    }
    for (final entry in previous.entries) {
      repository.updateLayer(
        layerId: entry.key,
        update: (layer) => layer.transformEnabled == entry.value
            ? layer
            : layer.copyWith(transformEnabled: entry.value),
      );
    }
  }
}
