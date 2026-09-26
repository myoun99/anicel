import '../../models/cut_id.dart';
import '../../models/layer_mark.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'linked_cut_field_command.dart';

/// Writes one 색 라벨 onto [cutIds] — and onto every 겸용 sibling of each, in
/// ONE command.
///
/// 🗣️유저 2026-09-26: 「겸용컷은 물론 한 컷 취급이니까 같이바뀌고 … 선택범위
/// 한상태로 조작가능한거 물론이고」. A 겸용 pair is one cut to the person
/// labelling it, so the label fans out the way the drawing guides do — the
/// walk every shared cut field takes ([LinkedCutFieldCommand]); the cuts a
/// selection covers are one pick, so they share one undo step.
class UpdateCutMarkCommand extends LinkedCutFieldCommand<LayerMark> {
  UpdateCutMarkCommand({
    required super.repository,
    required super.cutIds,
    required LayerMark mark,
  }) : super(
         value: mark,
         fieldName: 'colour label',
         read: (cut) => cut.metadata.mark,
         write: _writeMark,
       );

  /// The label alone, into the metadata the cut has NOW — an undo gives the
  /// label back and leaves the rest of the metadata as it stands.
  static void _writeMark(
    ProjectRepository repository,
    CutId cutId,
    LayerMark value,
  ) => repository.updateCutMetadata(
    cutId: cutId,
    metadata: requireCut(
      repository.requireProject(),
      cutId,
    ).metadata.copyWith(mark: value),
  );
}
