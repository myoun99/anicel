import 'dart:collection';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/camera_row_reach.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard/storyboard_lane_lists.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show cameraPropertyLanes;
import 'package:flutter_test/flutter_test.dart';

/// F-625: a projection row's lane labels walk the keys of EVERY cut of the
/// track, and ask for them at every pass of the rail — so a cut's keys are
/// read once while the cut is the same object, and a lane's frames are
/// handed back as the same list while they are the same frames
/// ([FilmLaneKeys]). The list is what a label is kept by.
///
/// Cuts a [0, 24), b [24, 48) and c [48, 60); a's camera keys its own 0 and
/// 12, b's its own 2.
void main() {
  const trackId = TrackId('t1');
  final rowId = trackCameraRowId(trackId);

  Cut cutOf(String id, int duration, List<int> keys, {String name = ''}) =>
      Cut(
        id: CutId(id),
        name: name.isEmpty ? id : name,
        duration: duration,
        canvasSize: const CanvasSize(width: 640, height: 360),
        camera: CutCamera(
          keyframes: {
            for (final frame in keys)
              frame: CameraPose(
                center: CanvasPoint(x: 320.0 + frame, y: 180),
              ),
          },
        ),
        layers: [
          Layer(
            id: LayerId('$id-cam'),
            name: 'Camera',
            kind: LayerKind.camera,
            frames: const [],
          ),
        ],
      );

  Project filmOf(List<Cut> cuts) => Project(
    id: const ProjectId('film'),
    name: 'Film',
    createdAt: DateTime.utc(2026, 11, 22),
    tracks: [Track(id: trackId, name: 'V1', cuts: cuts)],
  );

  List<CameraRowReach> reachesOf(Project project) =>
      cameraRowReachesOf(buildStoryboardTimelineLayout(project), const []);

  /// The rail's lists over [project] as it stands at each ask, and how many
  /// cuts' lanes they have read.
  ({
    FilmLaneKeys Function() keys,
    int Function() reads,
    void Function(Project) stand,
  })
  rail(Project first) {
    var project = first;
    var reads = 0;
    final kept = KeptStoryboardLanes(() => project);
    return (
      keys: () => kept.filmKeys(project.tracks.single, rowId, (
        layerOf: (cut) => cut.layers.cameraLayer,
        lanesOf: (cut, camera) {
          reads += 1;
          return cameraPropertyLanes(
            camera,
            cut.camera.track,
            canvasSize: cut.canvasSize,
          );
        },
      )),
      reads: () => reads,
      stand: (next) => project = next,
    );
  }

  test('a pass that changed nothing reads no cut again, and hands the same '
      'list back', () {
    final film = filmOf([
      cutOf('a', 24, [0, 12]),
      cutOf('b', 24, [2]),
      cutOf('c', 12, const []),
    ]);
    final r = rail(film);

    final first = r.keys().framesOf('scale', reachesOf(film));
    expect(first, [0, 12, 26]);
    expect(r.reads(), 3, reason: '⛔전제: a cut is read once for all its lanes');

    final again = r.keys().framesOf('scale', reachesOf(film));
    expect(r.keys().framesOf('position', reachesOf(film)), [0, 12, 26]);
    expect(again, same(first));
    expect(r.reads(), 3);
  });

  test('🚨while the cuts lie alike no lane is walked again, pass after '
      'pass — and each is walked once when a cut moved', () {
    final a = cutOf('a', 24, [0, 12]);
    final b = cutOf('b', 24, [2]);
    final film = filmOf([a, b]);
    final r = rail(film);
    final first = _Walked(reachesOf(film));
    final scale = r.keys().framesOf('scale', first);
    r.keys().framesOf('position', first);
    r.keys().framesOf('scale', first);
    expect(first.walks, 2, reason: '⛔전제: once a lane');

    // The next pass: the same cuts laid alike, in a list of its own.
    final again = _Walked(reachesOf(film));
    expect(again, isNot(same(first)), reason: '⛔전제');
    expect(r.keys().framesOf('scale', again), same(scale));
    r.keys().framesOf('position', again);
    expect(again.walks, 0);

    final pushed = filmOf([a, b.copyWith(leadingGapFrames: 5)]);
    r.stand(pushed);
    final moved = _Walked(reachesOf(pushed));
    expect(r.keys().framesOf('scale', moved), [0, 12, 31]);
    r.keys().framesOf('scale', moved);
    expect(moved.walks, 1);
  });

  test('🚨an edit reads the one cut it made anew — and a lane whose keys it '
      'did not move keeps its list', () {
    final a = cutOf('a', 24, [0, 12]);
    final b = cutOf('b', 24, [2]);
    final c = cutOf('c', 12, const []);
    final film = filmOf([a, b, c]);
    final r = rail(film);
    final first = r.keys().framesOf('scale', reachesOf(film));
    expect(r.reads(), 3, reason: '⛔전제');

    // c is named again: a new cut, the same keys.
    final renamed = filmOf([a, b, cutOf('c', 12, const [], name: 'C')]);
    r.stand(renamed);

    expect(r.keys().framesOf('scale', reachesOf(renamed)), same(first));
    expect(r.reads(), 4, reason: 'c alone');
  });

  test('🚨a key that comes in another cut is a new list, with its frame', () {
    final a = cutOf('a', 24, [0, 12]);
    final b = cutOf('b', 24, [2]);
    final film = filmOf([a, b, cutOf('c', 12, const [])]);
    final r = rail(film);
    final first = r.keys().framesOf('scale', reachesOf(film));

    final keyed = filmOf([a, b, cutOf('c', 12, [4])]);
    r.stand(keyed);
    final after = r.keys().framesOf('scale', reachesOf(keyed));

    expect(after, [0, 12, 26, 52]);
    expect(after, isNot(same(first)));
    expect(r.keys().ownKeysOf(keyed.tracks.single.cuts[2], 'scale'), {4});
  });

  test('a cut moved along the track moves its keys\' frames', () {
    final a = cutOf('a', 24, [0, 12]);
    final b = cutOf('b', 24, [2]);
    final film = filmOf([a, b]);
    final r = rail(film);
    expect(r.keys().framesOf('scale', reachesOf(film)), [0, 12, 26]);

    final pushed = filmOf([a, b.copyWith(leadingGapFrames: 5)]);
    r.stand(pushed);

    expect(r.keys().framesOf('scale', reachesOf(pushed)), [0, 12, 31]);
  });

  test('a lane no cut holds has no frame', () {
    final film = filmOf([cutOf('a', 24, [0, 12])]);
    final r = rail(film);

    expect(r.keys().framesOf('no-such-lane', reachesOf(film)), isEmpty);
    expect(
      r.keys().ownKeysOf(film.tracks.single.cuts.single, 'no-such-lane'),
      isEmpty,
    );
  });
}

/// A track's reaches that count the times they are walked whole — a
/// lane's frames read off every cut. Comparing two of them walks
/// neither (`listEquals` asks by index).
final class _Walked extends ListBase<CameraRowReach> {
  _Walked(this._of);

  final List<CameraRowReach> _of;
  int walks = 0;

  @override
  int get length => _of.length;

  @override
  set length(int _) => throw UnsupportedError('fixed');

  @override
  CameraRowReach operator [](int index) => _of[index];

  @override
  void operator []=(int index, CameraRowReach value) =>
      throw UnsupportedError('fixed');

  @override
  Iterator<CameraRowReach> get iterator {
    walks += 1;
    return _of.iterator;
  }
}
