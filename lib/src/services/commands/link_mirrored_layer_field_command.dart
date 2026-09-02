import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';

/// Writes ONE shared layer field through every link mirror of the layer in
/// a single command ("레인만 각자, 나머지는 하나": linked members are "the
/// same layer" seen from different cuts), and one undo step restores every
/// member's own previous value.
///
/// 🚨ONE law for the name, mark and kind commands — three copies of the
/// same execute/undo walk (the audit's clone scan, 2026-09-03). [write] is
/// the repository setter for the field, [read] its getter on a layer.
class LinkMirroredLayerFieldCommand<T> implements Command {
  LinkMirroredLayerFieldCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.value,
    required this.fieldName,
    required T Function(Layer layer) read,
    required LayerFieldWrite<T> write,
  }) : _read = read,
       _write = write;

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;
  final T value;
  final String fieldName;
  final T Function(Layer layer) _read;
  final LayerFieldWrite<T> _write;

  List<({CutId cutId, LayerId layerId, T previous})>? _targets;

  @override
  String get description => 'Update layer $fieldName $layerId';

  @override
  void execute() {
    final project = repository.requireProject();
    // Anywhere lookup: track-owned SE rows are not in the cut's layer list
    // but carry marks like every row (unified layer controls). SE rows are
    // never linked, so their mirror target set is just themselves.
    _targets ??= [
      for (final target in linkMirrorTargets(
        project,
        cutId: cutId,
        layerId: layerId,
      ))
        (
          cutId: target.cutId,
          layerId: target.layerId,
          previous: _read(requireLayerAnywhere(project, target.layerId)),
        ),
    ];
    for (final target in _targets!) {
      _write(
        repository,
        cutId: target.cutId,
        layerId: target.layerId,
        value: value,
      );
    }
  }

  @override
  void undo() {
    final targets = _targets;
    if (targets == null) {
      throw StateError('Command has not been executed.');
    }
    for (final target in targets) {
      _write(
        repository,
        cutId: target.cutId,
        layerId: target.layerId,
        value: target.previous,
      );
    }
  }
}

/// A repository setter for one layer field, addressed the way the mirror
/// targets are.
typedef LayerFieldWrite<T> =
    void Function(
      ProjectRepository repository, {
      required CutId cutId,
      required LayerId layerId,
      required T value,
    });
