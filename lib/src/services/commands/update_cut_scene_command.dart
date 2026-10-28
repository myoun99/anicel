import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../project_lookup.dart';
import 'mirrored_field_command.dart';

/// Writes [cutId]'s scene (`CutMetadata.scene`) — the cut's alone: a 겸용
/// sibling keeps its own, as it keeps its own name.
class UpdateCutSceneCommand extends MirroredFieldCommand<CutId, String> {
  UpdateCutSceneCommand({
    required super.repository,
    required this.cutId,
    required String scene,
  }) : super(value: scene);

  final CutId cutId;

  @override
  String get description => 'Set the scene of $cutId';

  @override
  List<CutId> membersOf(Project project) => [cutId];

  @override
  String valueOf(Project project, CutId member) =>
      requireCut(project, member).metadata.scene;

  // The scene alone, into the metadata the cut has NOW — an undo gives the
  // scene back and leaves the rest as it stands.
  @override
  void writeTo(CutId member, String value) => repository.updateCutMetadata(
    cutId: member,
    metadata: requireCut(
      repository.requireProject(),
      member,
    ).metadata.copyWith(scene: value),
  );
}
