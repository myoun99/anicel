import '../../models/cut_id.dart';
import '../../models/timesheet_sheet_kind.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'linked_cut_field_command.dart';

/// Writes the paper a cut's timesheet prints on onto [cutIds] — and onto
/// every 겸용 sibling of each, in ONE command: each cut keeps its own
/// (timesheet-sheet-kind-scope-Q1: 「컷마다 따로」), and a 겸용 pair is one
/// cut (유저 2026-09-26: 「겸용컷은 물론 한 컷 취급이니까 같이바뀌고」), the
/// walk every shared cut field takes ([LinkedCutFieldCommand]).
class UpdateCutSheetKindCommand
    extends LinkedCutFieldCommand<TimesheetSheetKind> {
  UpdateCutSheetKindCommand({
    required super.repository,
    required super.cutIds,
    required TimesheetSheetKind kind,
  }) : super(
         value: kind,
         fieldName: 'timesheet paper',
         read: (cut) => cut.metadata.sheetKind,
         write: _writeKind,
       );

  /// The paper alone, into the metadata the cut has NOW — an undo gives the
  /// paper back and leaves the rest of the metadata as it stands.
  static void _writeKind(
    ProjectRepository repository,
    CutId cutId,
    TimesheetSheetKind value,
  ) => repository.updateCutMetadata(
    cutId: cutId,
    metadata: requireCut(
      repository.requireProject(),
      cutId,
    ).metadata.copyWith(sheetKind: value),
  );
}
