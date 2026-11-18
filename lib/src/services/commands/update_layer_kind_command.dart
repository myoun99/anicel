import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_exposure.dart';
import '../project_lookup.dart' show requireLayerAnywhere;
import '../project_repository.dart';
import 'link_mirrored_layer_field_command.dart';

/// Changes a layer's kind — and, when it is LINKED, every member of its
/// group in the same command (kind is a shared property like name/mark:
/// linked members are "the same layer" seen from different cuts). One
/// undo step restores every member's previous kind.
class UpdateLayerKindCommand extends LinkMirroredLayerFieldCommand<LayerKind> {
  UpdateLayerKindCommand({
    required super.repository,
    required super.cutId,
    required super.layerId,
    required LayerKind kind,
  }) : super(
         value: kind,
         fieldName: 'kind',
         read: (layer) => layer.kind,
         write: _writeKind,
         // The kind is what seats a row in a conte group — not something
         // the group's rows share ([LinkMirroredLayerFieldCommand.ofTheHead]).
         ofTheHead: false,
       );

  static void _writeKind(
    ProjectRepository repository, {
    required CutId cutId,
    required LayerId layerId,
    required LayerKind value,
  }) => repository.updateLayerKind(cutId: cutId, layerId: layerId, kind: value);

  /// Each member's lane as it stood before the first execute. The write a
  /// kind lands in reshapes the lane of a covering kind — an image's row is
  /// one cell held over its cut (`covering_image_normalize.dart`) — and the
  /// kind put back alone would leave the lane that shape: an animation's
  /// row of twelve frames came back from an image as one held over the
  /// whole cut (card 「파일마다 배치 기본값」-Q8, the sync's kind).
  Map<LayerId, Map<int, TimelineExposure>>? _lanes;

  @override
  void execute() {
    final project = repository.requireProject();
    _lanes ??= {
      for (final member in membersOf(project))
        member.layerId: requireLayerAnywhere(
          project,
          member.layerId,
        ).timeline,
    };
    super.execute();
  }

  @override
  void undo() {
    super.undo();
    for (final MapEntry(key: layerId, value: lane) in _lanes!.entries) {
      repository.updateLayer(
        layerId: layerId,
        update: (layer) => layer.copyWith(timeline: lane),
      );
    }
  }
}
