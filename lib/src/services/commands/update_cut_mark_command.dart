import '../../models/cut_id.dart';
import '../../models/cut_metadata.dart';
import '../../models/layer_mark.dart';
import '../../models/project.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';

/// Writes one 색 라벨 onto [cutIds] — and onto every 겸용 sibling of each, in
/// ONE command.
///
/// 🗣️유저 2026-09-26: 「겸용컷은 물론 한 컷 취급이니까 같이바뀌고 … 선택범위
/// 한상태로 조작가능한거 물론이고」. A 겸용 pair is one cut to the person
/// labelling it, so the label fans out the way the drawing guides do
/// ([SetCutGuidesCommand]); the cuts a selection covers are one pick, so they
/// share one undo step.
class UpdateCutMarkCommand implements Command {
  UpdateCutMarkCommand({
    required this.repository,
    required this.cutIds,
    required this.mark,
  });

  final ProjectRepository repository;
  final List<CutId> cutIds;
  final LayerMark mark;

  List<({CutId cutId, CutMetadata previous})>? _targets;

  /// Every cut a label picked for [cutIds] lands on: each of them and its
  /// 겸용 siblings, once each.
  static List<CutId> targetsOf(Project project, List<CutId> cutIds) => [
    ...{
      for (final cutId in cutIds) ...[
        cutId,
        ...linkedCutSiblings(project, cutId: cutId),
      ],
    },
  ];

  @override
  String get description => 'Set the colour label of ${cutIds.join(', ')}';

  @override
  void execute() {
    final project = repository.requireProject();
    _targets ??= [
      for (final cutId in targetsOf(project, cutIds))
        (cutId: cutId, previous: requireCut(project, cutId).metadata),
    ];
    for (final target in _targets!) {
      repository.updateCutMetadata(
        cutId: target.cutId,
        metadata: target.previous.copyWith(mark: mark),
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
      repository.updateCutMetadata(
        cutId: target.cutId,
        metadata: target.previous,
      );
    }
  }
}
