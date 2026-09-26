import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';
import 'mirrored_field_command.dart';

/// Writes ONE shared layer field through every link mirror of the layer in
/// a single command ("레인만 각자, 나머지는 하나": linked members are "the
/// same layer" seen from different cuts), and one undo step restores every
/// member's own previous value.
///
/// 🚨ONE law for the name, mark and kind commands — three copies of the
/// same execute/undo walk (the audit's clone scan, 2026-09-03). [write] is
/// the repository setter for the field, [read] its getter on a layer. The
/// walk itself is every shared field's, a cut's too ([MirroredFieldCommand]).
class LinkMirroredLayerFieldCommand<T>
    extends MirroredFieldCommand<({CutId cutId, LayerId layerId}), T> {
  LinkMirroredLayerFieldCommand({
    required super.repository,
    required this.cutId,
    required this.layerId,
    required super.value,
    required this.fieldName,
    required T Function(Layer layer) read,
    required LayerFieldWrite<T> write,
  }) : _read = read,
       _write = write;

  final CutId cutId;
  final LayerId layerId;
  final String fieldName;
  final T Function(Layer layer) _read;
  final LayerFieldWrite<T> _write;

  @override
  String get description => 'Update layer $fieldName $layerId';

  // Anywhere lookup: track-owned SE rows are not in the cut's layer list but
  // carry marks like every row (unified layer controls). SE rows are never
  // linked, so their mirror target set is just themselves.
  @override
  List<({CutId cutId, LayerId layerId})> membersOf(Project project) =>
      linkMirrorTargets(project, cutId: cutId, layerId: layerId);

  @override
  T valueOf(Project project, ({CutId cutId, LayerId layerId}) member) =>
      _read(requireLayerAnywhere(project, member.layerId));

  @override
  void writeTo(({CutId cutId, LayerId layerId}) member, T value) => _write(
    repository,
    cutId: member.cutId,
    layerId: member.layerId,
    value: value,
  );
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
