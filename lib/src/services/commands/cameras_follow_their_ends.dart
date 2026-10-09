import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track_transitions.dart' show drawnFrameCountsOf;
import '../project_repository.dart';

/// What a command that moves cuts or their O.L owes the cameras
/// (I-73-camera-row-Q4 · Q7): each camera on the end its cut is left
/// drawn to, and put back on the way back.
///
/// The write settles every camera as its cut's end moves
/// ([cameraFollowingItsEnd]), but a command may pass through layouts on
/// the way — a cut trimmed first and its O.L carried after it, which for
/// a moment is no O.L of that cut at all — and a shrink brings keys in.
/// So the command's cameras are settled once more from what it FOUND to
/// where it left the cuts, over whatever the steps between did.
///
/// And what came in does not go back out when the のりしろ comes back
/// (only the end key does), so every camera the edit moved is kept as it
/// was and put back after the command's undo.
class CamerasFollowTheirEnds {
  CamerasFollowTheirEnds(this._repository);

  final ProjectRepository _repository;

  /// The cameras [around] saw its edit move, as they were before it.
  Map<CutId, CutCamera> _before = const {};

  /// Runs [edit], then gives the camera of every cut it found the end the
  /// cut is left drawn to — keeping each one that moved for [back].
  void around(void Function() edit) {
    final found = _repository.requireProject();
    final drawn = drawnFrameCountsOf(found);
    final cameras = _camerasOf(found);
    edit();
    final left = _repository.requireProject();
    final drawnNow = drawnFrameCountsOf(left);
    for (final track in left.tracks) {
      for (final cut in track.cuts) {
        final camera = cameras[cut.id];
        final was = drawn[cut.id];
        if (camera == null || was == null) {
          continue;
        }
        final settled = cameraFollowingItsEnd(
          camera,
          lastFrame: drawnNow[cut.id]! - 1,
          previousLastFrame: was - 1,
        );
        if (settled != cut.camera) {
          _repository.updateCutCamera(cutId: cut.id, camera: settled);
        }
      }
    }
    final now = _camerasOf(_repository.requireProject());
    _before = {
      for (final MapEntry(key: cutId, value: camera) in cameras.entries)
        if (now[cutId] case final moved? when moved != camera) cutId: camera,
    };
  }

  /// Runs [undo], then puts back every camera [around] kept that is not
  /// back already.
  void back(void Function() undo) {
    undo();
    final now = _camerasOf(_repository.requireProject());
    for (final MapEntry(key: cutId, value: camera) in _before.entries) {
      if (now.containsKey(cutId) && now[cutId] != camera) {
        _repository.updateCutCamera(cutId: cutId, camera: camera);
      }
    }
    _before = const {};
  }

  static Map<CutId, CutCamera> _camerasOf(Project project) => {
    for (final track in project.tracks)
      for (final cut in track.cuts) cut.id: cut.camera,
  };
}
