import 'cut_id.dart';
import 'frame_id.dart';
import 'layer_id.dart';
import 'project_id.dart';
import 'track_id.dart';

class BrushFrameKey {
  const BrushFrameKey({
    required this.projectId,
    required this.trackId,
    required this.cutId,
    required this.layerId,
    required this.frameId,
  });

  final ProjectId projectId;
  final TrackId trackId;
  final CutId cutId;
  final LayerId layerId;
  final FrameId frameId;

  /// The cel as its painters name it — its row and its frame, without the
  /// project, track and cut this key finds it through: what a canvas shows
  /// (`ShownCel`), a tile picture's lineage and the engine ledger's cel are
  /// keyed by.
  (LayerId, FrameId) get cel => (layerId, frameId);

  /// The cel a surface that is nobody's is named by — the selection
  /// float's: one name for every such surface, where a painter's [cel] is
  /// asked, so all of them are counted together. ⚠️A new `Object()` each
  /// time would be a new cel each paint — the ledger keeps a pool cel for
  /// every name it is given.
  static final Object noCel = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushFrameKey &&
          other.projectId == projectId &&
          other.trackId == trackId &&
          other.cutId == cutId &&
          other.layerId == layerId &&
          other.frameId == frameId;

  @override
  int get hashCode => Object.hash(projectId, trackId, cutId, layerId, frameId);

  @override
  String toString() =>
      'BrushFrameKey('
      'projectId: $projectId, '
      'trackId: $trackId, '
      'cutId: $cutId, '
      'layerId: $layerId, '
      'frameId: $frameId'
      ')';
}
