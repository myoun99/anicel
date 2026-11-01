import '../../models/cut_id.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'linked_cut_field_command.dart';

/// Writes whether a cut's conte cells write their fixed lines
/// (`CutMetadata.conteFixedText`, F-542) onto [cutIds] — and onto every 겸용
/// sibling of each, in ONE command, as the room its cells take is
/// (`UpdateCutConteCameraRoomCommand`). Null gives the cut back to the format
/// window's.
class UpdateCutConteFixedTextCommand extends LinkedCutFieldCommand<bool?> {
  UpdateCutConteFixedTextCommand({
    required super.repository,
    required super.cutIds,
    required bool? on,
  }) : super(
         value: on,
         fieldName: 'conte fixed text',
         read: (cut) => cut.metadata.conteFixedText,
         write: _write,
       );

  /// The choice alone, into the metadata the cut has NOW.
  static void _write(
    ProjectRepository repository,
    CutId cutId,
    bool? value,
  ) => repository.updateCutMetadata(
    cutId: cutId,
    metadata: requireCut(
      repository.requireProject(),
      cutId,
    ).metadata.copyWith(conteFixedText: value),
  );
}

/// The same of its timesheet's pages (`CutMetadata.sheetFixedText`, F-542).
class UpdateCutSheetFixedTextCommand extends LinkedCutFieldCommand<bool?> {
  UpdateCutSheetFixedTextCommand({
    required super.repository,
    required super.cutIds,
    required bool? on,
  }) : super(
         value: on,
         fieldName: 'sheet fixed text',
         read: (cut) => cut.metadata.sheetFixedText,
         write: _write,
       );

  /// The choice alone, into the metadata the cut has NOW.
  static void _write(
    ProjectRepository repository,
    CutId cutId,
    bool? value,
  ) => repository.updateCutMetadata(
    cutId: cutId,
    metadata: requireCut(
      repository.requireProject(),
      cutId,
    ).metadata.copyWith(sheetFixedText: value),
  );
}
