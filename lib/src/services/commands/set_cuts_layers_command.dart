import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_link_registry.dart';
import 'link_registry_snapshot_command.dart';
import '../project_lookup.dart';

/// Writes several cuts' rows whole, and the link table, as ONE write taken
/// back as one — what `SetCutLayersCommand` is for one cut, for an edit a
/// 겸용 layer's other cuts share: a merge across them (I-78-Q9), whose
/// rows go from every cut at once and whose results are ONE layer after.
///
/// The table goes first, so each cut written after it reads its rows'
/// links as they will stand; and every cut is written in one write of the
/// tracks' contes, as a delete across cuts is (`DeleteLayerCommand`).
class SetCutsLayersCommand extends LinkRegistrySnapshotCommand {
  SetCutsLayersCommand({
    required super.repository,
    required this.layers,
    required this.links,
    required this.description,
  });

  /// Each cut's rows after, by the cut.
  final Map<CutId, List<Layer>> layers;

  /// The link table after.
  final LayerLinkRegistry links;

  @override
  final String description;

  Map<CutId, List<Layer>>? _before;

  @override
  void execute() {
    final project = repository.requireProject();
    snapshotRegistry(project);
    _before ??= {
      for (final cutId in layers.keys)
        cutId: requireCut(project, cutId).layers,
    };
    repository.updateProject(
      (current) => current.copyWith(linkRegistry: links),
    );
    _write(layers);
    markExecuted();
  }

  @override
  void undoBeforeRegistry() => _write(_before!);

  void _write(Map<CutId, List<Layer>> rowsByCut) {
    repository.asOneConteWrite(() {
      for (final MapEntry(key: cutId, value: rows) in rowsByCut.entries) {
        repository.setCutLayers(cutId: cutId, layers: rows);
      }
    });
  }
}
