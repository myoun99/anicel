import 'dart:collection';

import '../../models/camera_pose.dart';
import '../../models/cut_camera.dart';

/// Deviations a straight line may have before the simplifier keeps the
/// frame as its own key. Sized to stay under a quarter canvas pixel on a
/// 2000px-ish canvas: position is already in canvas pixels; a 1e-4 zoom
/// error moves a 2000px span by 0.2px, and 0.01° swings a 1000px radius
/// by 0.17px.
const double _cameraPositionTolerance = 0.25;
const double _cameraZoomTolerance = 1e-4;
const double _cameraRotationTolerance = 0.01;

/// A key at least this often, so the simplifier's per-run rescan cannot
/// turn quadratic on a very long clip.
const int _cameraMaxRunFrames = 512;

/// The camera that holds [byFrame] — a pose on every frame, as an import
/// bakes another program's move — in the keys it needs: every frame a
/// straight line between its neighbours already reproduces is dropped, so
/// a linear pan collapses back to two keys and easing keeps exactly the
/// keys it needs. A hold at either end needs no key of its own — the app
/// holds the first key before it and the last after it — so a move that
/// starts late or stops early is keyed where it starts and stops, and a
/// camera that never moves is ONE key. The simplifier keeps both ends of
/// whatever it walks, and a hold's far end was a key on a frame no one set
/// (288, hands-on: one key on frame 1 arrived as keys on 1 and 96; s6's
/// pan, keyed on frames 0 and 108, arrived with a third on its last
/// frame). The TVPaint and CLIP STUDIO imports both make their cut's
/// camera here.
CutCamera cutCameraOfFramePoses(SplayTreeMap<int, CameraPose> byFrame) {
  if (byFrame.isEmpty) {
    return CutCamera.empty();
  }
  final frames = byFrame.keys.toList();
  final poses = byFrame.values.toList();
  final kept = _simplifiedTrack(frames, poses);
  bool holds(int a, int b) => _same(poses[kept[a]], poses[kept[b]]);
  if (kept.length > 1 && holds(kept.length - 1, kept.length - 2)) {
    kept.removeLast();
  }
  if (kept.length > 1 && holds(0, 1)) {
    kept.removeAt(0);
  }
  return CutCamera(
    keyframes: {for (final index in kept) frames[index]: poses[index]},
  );
}

bool _same(CameraPose a, CameraPose b) =>
    a.center.x == b.center.x &&
    a.center.y == b.center.y &&
    a.zoom == b.zoom &&
    a.rotationDegrees == b.rotationDegrees;

/// Indexes worth keeping: the ends, plus every frame a straight line
/// between the surrounding kept frames fails to reproduce.
List<int> _simplifiedTrack(List<int> frames, List<CameraPose> poses) {
  if (poses.length <= 2) {
    return [for (var i = 0; i < poses.length; i += 1) i];
  }
  final kept = <int>[0];
  var anchor = 0;
  for (var candidate = 2; candidate < poses.length; candidate += 1) {
    if (frames[candidate] - frames[anchor] > _cameraMaxRunFrames ||
        !_lineReproduces(frames, poses, anchor, candidate)) {
      kept.add(candidate - 1);
      anchor = candidate - 1;
    }
  }
  kept.add(poses.length - 1);
  return kept;
}

bool _lineReproduces(
  List<int> frames,
  List<CameraPose> poses,
  int from,
  int to,
) {
  final span = frames[to] - frames[from];
  if (span <= 0) {
    return false;
  }
  final start = poses[from];
  final end = poses[to];
  for (var middle = from + 1; middle < to; middle += 1) {
    final t = (frames[middle] - frames[from]) / span;
    final pose = poses[middle];
    double off(double a, double b, double actual) => (a + (b - a) * t - actual)
        .abs();
    if (off(start.center.x, end.center.x, pose.center.x) >
            _cameraPositionTolerance ||
        off(start.center.y, end.center.y, pose.center.y) >
            _cameraPositionTolerance ||
        off(start.zoom, end.zoom, pose.zoom) > _cameraZoomTolerance ||
        off(
              start.rotationDegrees,
              end.rotationDegrees,
              pose.rotationDegrees,
            ) >
            _cameraRotationTolerance) {
      return false;
    }
  }
  return true;
}
