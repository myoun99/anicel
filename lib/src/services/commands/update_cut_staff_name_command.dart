import '../../models/layer_mark.dart';
import '../project_lookup.dart';
import 'linked_cut_field_command.dart';

/// Writes one stage's name onto [cutIds] — and onto every 겸용 sibling of
/// each — in ONE command: 컷 설정 (유저 09-25: 작품 설정에는 기본값, 컷
/// 설정에는 컷별 이름). An empty name gives the stage back to the work's.
///
/// ONE stage a command, so a pick for several cuts carries the stages it
/// changed and leaves every other stage as each cut has it — the edit is
/// passed on as it was made (CLAUDE.md 절대명령 2). A 겸용 pair is one cut to
/// the person naming it, as it is to the one labelling it
/// ([UpdateCutMarkCommand]).
class UpdateCutStaffNameCommand extends LinkedCutFieldCommand<String> {
  UpdateCutStaffNameCommand({
    required super.repository,
    required super.cutIds,
    required LayerMark mark,
    required String name,
  }) : super(
         value: name,
         fieldName: 'staff name ${mark.keySlug}',
         read: (cut) => cut.metadata.staffNameFor(mark),
         // The name alone, into the metadata the cut has NOW — an undo
         // gives the name back and leaves the rest as it stands.
         write: (repository, cutId, value) => repository.updateCutMetadata(
           cutId: cutId,
           metadata: requireCut(
             repository.requireProject(),
             cutId,
           ).metadata.withStaffName(mark, value),
         ),
       );
}
