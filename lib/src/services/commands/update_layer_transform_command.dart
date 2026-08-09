import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/transform_track.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Replaces a layer's whole transform track in one undo step (lane edits
/// are computed as pure functions on the track, then committed here —
/// mirrors the instruction and camera-track commands).
class UpdateLayerTransformCommand implements Command {
  UpdateLayerTransformCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.transformTrack,
    this.description = 'Edit layer transform',
  });

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;
  final TransformTrack transformTrack;

  @override
  final String description;

  TransformTrack? _previousTrack;
  bool _hasExecuted = false;

  @override
  void execute() {
    // ANYWHERE lookup: layer ids are globally unique and a track-owned SE
    // row is not IN any cut, so the cut-scoped read threw for exactly the
    // rows whose lanes R5 #8 taught to key. The repository writer below
    // has always searched both places; only the read had not caught up.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    _previousTrack ??= layer.transformTrack;

    repository.updateLayerTransformTrack(
      cutId: cutId,
      layerId: layerId,
      transformTrack: transformTrack,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousTrack = _previousTrack;
    if (!_hasExecuted || previousTrack == null) {
      throw StateError('Command has not been executed.');
    }

    requireLayerAnywhere(repository.requireProject(), layerId);
    repository.updateLayerTransformTrack(
      cutId: cutId,
      layerId: layerId,
      transformTrack: previousTrack,
    );
  }
}
