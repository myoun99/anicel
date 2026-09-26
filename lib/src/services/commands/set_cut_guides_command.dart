import '../../models/cut_id.dart';
import '../../models/drawing_guide.dart';
import '../project_repository.dart';
import 'linked_cut_field_command.dart';

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
/// own undo, and one undo step puts every member back — the walk every
/// shared cut field takes ([LinkedCutFieldCommand]).
///
/// The whole [CutGuides] is written, not merged: "one changes, they all
/// change" is a copy, and a merge would need rules for order, id collisions
/// and one-side-only entries that have no right answer.
class SetCutGuidesCommand extends LinkedCutFieldCommand<CutGuides> {
  SetCutGuidesCommand({
    required super.repository,
    required CutId cutId,
    required CutGuides guides,
  }) : super(
         cutIds: [cutId],
         value: guides,
         fieldName: 'drawing guides',
         read: (cut) => cut.guides,
         write: _writeGuides,
       );

  static void _writeGuides(
    ProjectRepository repository,
    CutId cutId,
    CutGuides value,
  ) => repository.updateCutGuides(cutId: cutId, guides: value);
}
