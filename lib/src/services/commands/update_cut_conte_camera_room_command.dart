import '../../models/conte/conte_camera_room.dart';
import '../../models/cut_id.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'linked_cut_field_command.dart';

/// Writes how much of the conte sheet a cut's cells take where its camera
/// moves (`CutMetadata.conteCameraRoom`, I-82) onto [cutIds] — and onto
/// every 겸용 sibling of each, in ONE command, as the paper its timesheet
/// prints on is (`UpdateCutSheetKindCommand`): a 겸용 pair is one cut. A
/// null room gives the cut back to the format window's.
class UpdateCutConteCameraRoomCommand
    extends LinkedCutFieldCommand<ConteCameraRoom?> {
  UpdateCutConteCameraRoomCommand({
    required super.repository,
    required super.cutIds,
    required ConteCameraRoom? room,
  }) : super(
         value: room,
         fieldName: 'conte camera room',
         read: (cut) => cut.metadata.conteCameraRoom,
         write: _writeRoom,
       );

  /// The room alone, into the metadata the cut has NOW — an undo gives the
  /// room back and leaves the rest of the metadata as it stands.
  static void _writeRoom(
    ProjectRepository repository,
    CutId cutId,
    ConteCameraRoom? value,
  ) => repository.updateCutMetadata(
    cutId: cutId,
    metadata: requireCut(
      repository.requireProject(),
      cutId,
    ).metadata.copyWith(conteCameraRoom: value),
  );
}
