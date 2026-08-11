import '../../models/cut_id.dart';
import '../../models/drawing_guide.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';

/// Writes a cut's drawing guides — and the same guides onto every 겸용
/// sibling, in ONE command.
///
/// Guides are a property of the picture being drawn, and 겸용 cuts show ONE
/// physical cel in two places ("cel pixels stay ONE physical entity per
/// group"). Two members with different axes would be two different answers
/// about the same drawing.
///
/// The fan-out lives in the command, not further down. `UpdateLayerKindCommand`
/// records what happens otherwise: a kind smuggled through the frames funnel
/// left linked siblings as content-less rows, and the bake sweep blank-baked
/// the shared bank both cuts display. So this owns its own fan-out and its
/// own undo, and one undo step puts every member back.
///
/// The whole [CutGuides] is written, not merged: "one changes, they all
/// change" is a copy, and a merge would need rules for order, id collisions
/// and one-side-only entries that have no right answer.
class SetCutGuidesCommand implements Command {
  SetCutGuidesCommand({
    required this.repository,
    required this.cutId,
    required this.guides,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final CutGuides guides;

  List<({CutId cutId, CutGuides previousGuides})>? _targets;

  @override
  String get description => 'Set drawing guides on $cutId';

  @override
  void execute() {
    final project = repository.requireProject();
    _targets ??= [
      for (final targetCutId in [
        cutId,
        ...linkedCutSiblings(project, cutId: cutId),
      ])
        (
          cutId: targetCutId,
          previousGuides: requireCut(project, targetCutId).guides,
        ),
    ];
    for (final target in _targets!) {
      repository.updateCutGuides(cutId: target.cutId, guides: guides);
    }
  }

  @override
  void undo() {
    final targets = _targets;
    if (targets == null) {
      throw StateError('Command has not been executed.');
    }
    for (final target in targets) {
      repository.updateCutGuides(
        cutId: target.cutId,
        guides: target.previousGuides,
      );
    }
  }
}
