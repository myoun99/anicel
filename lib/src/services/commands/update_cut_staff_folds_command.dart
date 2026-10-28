import '../../models/cut_id.dart';
import '../../models/layer_process.dart';
import '../../models/project.dart';
import '../project_lookup.dart';
import 'mirrored_field_command.dart';

/// Writes the stages whose folds 컷 설정 opens on (`CutMetadata
/// .openStaffFolds`) onto [cutIds] — each cut's own: a 겸용 sibling keeps
/// its own, as it is a window's memory of the cut, not the picture's.
class UpdateCutStaffFoldsCommand
    extends MirroredFieldCommand<CutId, Set<LayerProcess>> {
  UpdateCutStaffFoldsCommand({
    required super.repository,
    required this.cutIds,
    required Set<LayerProcess> open,
  }) : super(value: Set.unmodifiable(open));

  final List<CutId> cutIds;

  @override
  String get description => 'Set the staff folds of ${cutIds.join(', ')}';

  @override
  List<CutId> membersOf(Project project) => cutIds;

  @override
  Set<LayerProcess> valueOf(Project project, CutId member) =>
      requireCut(project, member).metadata.openStaffFolds;

  // The folds alone, into the metadata the cut has NOW — an undo gives the
  // folds back and leaves the rest as it stands.
  @override
  void writeTo(CutId member, Set<LayerProcess> value) =>
      repository.updateCutMetadata(
        cutId: member,
        metadata: requireCut(
          repository.requireProject(),
          member,
        ).metadata.copyWith(openStaffFolds: value),
      );
}
