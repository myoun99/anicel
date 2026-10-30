import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show listEquals;

import '../models/camera_work_marks.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/key_range_move.dart' show transformKeyAgreedNames;
import '../models/property_track.dart';
import '../models/sheet_marks.dart';
import '../models/sheet_paint_layer.dart';
import '../models/transform_track.dart' show pathKeySpace;
import 'camera_frame_corners.dart';

/// One key of a camera's path: its frame on the canvas, the colour its place
/// among all the camera's keys gives it, and the name its lanes agree on —
/// on a layer's position or anchor path, the point it stands at and its
/// own name.
typedef CameraPathKey = ({
  int frameIndex,
  List<Offset> corners,
  CameraKeyRole role,
  String? name,
});

/// A camera's path over its cut's canvas (I-89 ④): its frame at every key,
/// and at any frame from the first key to the last as playback shows it.
/// A layer's position and its anchor point walk one by the same code, a
/// point where the camera has its frame ([CameraPath.ofLane]).
class CameraPath {
  CameraPath._(this._shownAt, this.keys)
    : _frames = List<List<Offset>?>.filled(
        keys.last.frameIndex - keys.first.frameIndex + 1,
        null,
      ),
      _halves = List<List<Offset>?>.filled(
        2 * (keys.last.frameIndex - keys.first.frameIndex) + 1,
        null,
      );

  /// [cut]'s camera path, its frames [frameSize] canvas pixels at zoom 1 —
  /// null while the camera moves nothing: no key, or every key framing one
  /// place, the conte's rule for a camera holding still (F-310).
  static CameraPath? of(Cut cut, CanvasSize frameSize) {
    final keyed = cut.camera.track.keyedFrames;
    if (keyed.isEmpty) {
      return null;
    }
    final frames = cameraFramesShown(
      cut,
      frameSize,
      first: keyed.first,
      last: keyed.last,
    );
    if (frames.every(
      (frame) => listEquals(frame.corners, frames.first.corners),
    )) {
      return null;
    }
    final names = transformKeyAgreedNames(cut.camera.track);
    return CameraPath._(
      (time) => cameraFrameShownAtTime(cut, frameSize, time),
      [
        for (final (index, frame) in frames.indexed)
          (
            frameIndex: frame.frameIndex,
            corners: frame.corners,
            role: CameraKeyRole.at(index, frames.length),
            name: names[frame.frameIndex],
          ),
      ],
    );
  }

  /// [lane] — a layer's lane whose keys walk a path, its position or its
  /// anchor point (`walksAPath`) — as a path of points in the lane's own
  /// space (I-89-Q9, 유저 2026-10-12 「같은 코드로 레이어 위치 레인에도」 ·
  /// anchor-walks-a-path): its value at every key, and at any time between
  /// where its walk takes it. A surface lays it as it lays a camera's
  /// frames; there is no frame to draw. Null while it walks nowhere: one
  /// key or none, or every key at one place.
  ///
  /// A key stands at its value — a roving key too, on the path where the
  /// walk passes it — and is called by the cell it stands on, as a
  /// camera's roving key is.
  ///
  /// The lane's frames run [axisOffset] ahead of the cut's — a track-SE
  /// row's keys stand on the track's — and the path's are the cut's.
  static CameraPath? ofLane(
    PropertyTrack<CanvasPoint> lane, {
    int axisOffset = 0,
  }) {
    final keys = lane.keys;
    if (keys.length < 2) {
      return null;
    }
    final first = keys.values.first.value;
    if (keys.values.every((key) => key.value == first)) {
      return null;
    }
    Offset pointOf(CanvasPoint value) => Offset(value.x, value.y);
    return CameraPath._(
      (time) => [
        pointOf(
          lane.resolveAtTime(
            time: time + axisOffset,
            orElse: () => first,
            space: pathKeySpace,
          ),
        ),
      ],
      [
        for (final (index, MapEntry(key: frame, :value))
            in keys.entries.indexed)
          (
            frameIndex: frame - axisOffset,
            corners: [pointOf(value.value)],
            role: CameraKeyRole.at(index, keys.length),
            name: value.name,
          ),
      ],
    );
  }

  /// Where the path stands at a time: the camera's frame, or a point.
  final List<Offset> Function(double time) _shownAt;

  /// Every key, first to last.
  final List<CameraPathKey> keys;

  /// The frames between the keys, read as they are asked for.
  final List<List<Offset>?> _frames;

  int get firstFrame => keys.first.frameIndex;
  int get lastFrame => keys.last.frameIndex;

  /// The camera's frame at [frameIndex], from [firstFrame] to [lastFrame].
  List<Offset> frameAt(int frameIndex) =>
      _frames[frameIndex - firstFrame] ??= _shownAt(frameIndex.toDouble());

  /// The camera's frame every half frame from [firstFrame] to [lastFrame],
  /// read as it is asked for.
  final List<List<Offset>?> _halves;

  /// The trail each corner of the camera's frame draws over the frames
  /// [from] to [to] the path covers — four polylines, top-left first, or a
  /// point's one; none where those frames hold no travel.
  ///
  /// How a camera's travel reads (유저 2026-09-30, after Storyboard Pro:
  /// 「키마다 궤도? 를 그려둬서 어떻게 진행되는지 알게해줘. 그냥 단순하게
  /// 선으로」 · 「궤도는 중앙이아니라 각 꼭짓점 4개 전부야」 — one through
  /// the centre shows no turn and no push-in), on every surface alike
  /// (2026-10-12, I-89-Q13 「콘티처럼 꼭짓점 4개 궤적」 · 「이 궤도 시스템은
  /// 콘티용지패널이랑 정확히 동일. 즉 법 통일」): each corner at every frame
  /// and at the half between, as the confirmed spec's mock draws a trail
  /// (5판) — so a path bent through its keys (I-89 ④) reads as the curve it
  /// walks, not as a frame's chords. ↩️The canvas drew one trail, through
  /// the centre; the conte drew its four straight from key to key.
  List<List<Offset>> cornerTrailsBetween(int from, int to) {
    final frames = _halvesBetween(from, to);
    if (frames.isEmpty) {
      return const [];
    }
    return [
      for (var corner = 0; corner < frames.first.length; corner += 1)
        [for (final frame in frames) frame[corner]],
    ];
  }

  /// The line the middle of the camera's frame walks over the frames [from]
  /// to [to] — through every key's cross, bent as the path's handles bend
  /// it — read off the frames its corners' trails are
  /// ([cornerTrailsBetween]). None where those frames hold no travel, and
  /// none on a point's path: its one trail is its middle's.
  ///
  /// 🗣️F-368 (유저 2026-10-17, F-368-Q1 A): 「중앙 궤적 선 + 핸들(두 모드
  /// 공통, 서 있을 때)」 — what the canvas adds while one stands on the
  /// camera, never the camera's trail: that stays its four corners'.
  List<Offset> centreTrailBetween(int from, int to) {
    final frames = _halvesBetween(from, to);
    if (frames.isEmpty || cameraPlaceIsAPoint(frames.first)) {
      return const [];
    }
    return [for (final frame in frames) cameraFrameCentre(frame)];
  }

  /// The camera's frame at every frame and at the half between, over the
  /// frames [from] to [to] the path covers — none where those frames hold
  /// no travel.
  List<List<Offset>> _halvesBetween(int from, int to) {
    final first = math.max(from, firstFrame);
    final last = math.min(to, lastFrame);
    if (first >= last) {
      return const [];
    }
    return [
      for (var half = 2 * first; half <= 2 * last; half++)
        _halves[half - 2 * firstFrame] ??= half.isEven
            ? frameAt(half ~/ 2)
            : _shownAt(half / 2),
    ];
  }
}

/// [path] as the canvas and the export write it (I-89 ④⑥, 유저 2026-10-11:
/// 「캔버스랑 출력쪽은 키마다 전부 사각형 그리는거야. 사각형이랑 십자랑 한
/// 세트로. 위치도 다 통일」): the trail each corner of its frame draws
/// ([CameraPath.cornerTrailsBetween]), and at every key its frame with the
/// cross at its centre and its label at its top-left corner
/// ([CameraMarkedKey]), in the colour its place among all the camera's keys
/// gives it — as the conte's paper writes a cell's (`conteCameraMarksOf`).
///
/// A label is the key's name, else the frame it stands on
/// ([cameraKeyLabel]; 「사각형있는건 A가 왼쪽위인거처럼 24f도
/// 사각형존재하게 되니까 왼쪽위」). On a layer's position or anchor path, where a key
/// is a point with no frame, it stands beside the key's cross off the path
/// either side of it (I-89-Q9).
///
/// [place] lays a point of the path on the surface. Only the frames [from]
/// to [to] are written, where a surface keeps to some.
Iterable<SheetMark> cameraPathMarks(
  CameraPath path, {
  required Offset Function(Offset point) place,
  required CameraMarkSizes sizes,
  required SheetPaintLayer layer,
  int? from,
  int? to,
}) {
  final first = math.max(path.firstFrame, from ?? path.firstFrame);
  final last = math.min(path.lastFrame, to ?? path.lastFrame);
  return cameraWorkMarks(
    trails: [
      for (final trail in path.cornerTrailsBetween(first, last))
        [for (final point in trail) place(point)],
    ],
    keys: [
      for (final key in path.keys)
        if (key.frameIndex >= first && key.frameIndex <= last)
          CameraMarkedKey(
            corners: [for (final corner in key.corners) place(corner)],
            role: key.role,
            label: cameraKeyLabel(key.name, key.frameIndex),
            beside: _eitherSide(path, key.frameIndex, 1, place),
          ),
    ],
    sizes: sizes,
    layer: layer,
  );
}

/// Where [path] runs either side of [frame] on the surface [place] lays it
/// on — at the frames [by] before and after it, as far as the path goes:
/// what a label beside a cross there stands off ([cameraCrossLabel]).
List<Offset> _eitherSide(
  CameraPath path,
  int frame,
  int by,
  Offset Function(Offset point) place,
) => [
  for (final side in [frame - by, frame + by])
    cameraFrameCentre([
      for (final corner in path.frameAt(
        side.clamp(path.firstFrame, path.lastFrame),
      ))
        place(corner),
    ]),
];

/// The crosses [path] wears in time on the canvas (I-89 ④ 「공간 + 시간」,
/// 유저 2026-10-10: 「시간 표시가 지금 동그란 점인데 동일한 십자가로 … 점은
/// 1f2f3f 정하는게아니라 커스텀으로」): one at the camera's centre every
/// [every] frames counted from the cut's first, square to its frame there —
/// grey where the [playhead] has passed, blue where it is yet to go, in ink
/// where it stands. A key wears its own cross where a tick would fall.
///
/// Each wears the frame it stands on beside it, in its colour, off the way
/// the path runs ([cameraCrossLabel]: 유저 2026-10-12 「궤도 십자가? 보이는
/// 경우가 있잖아. 출력용말고 편집할때. 그 상황에서 십자가쪽에도 프레임번호
/// 아까말한대로 보여주도록」) — the crosses either side of it are the path.
/// So does a key's own cross, in the key's colour, off the path right
/// either side of it (I-89-Q16 B, 유저 2026-10-12: 「키의 십자에도」) — an
/// unnamed key's frame reads twice, at its frame's corner and beside its
/// cross. A point's label already stands there ([cameraPathMarks]): its
/// frame, unless it is named, and then the frame takes the next free
/// quarter.
///
/// [place], [from] and [to] as [cameraPathMarks] takes them.
Iterable<SheetMark> cameraPathTicks(
  CameraPath path, {
  required Offset Function(Offset point) place,
  required int every,
  required int playhead,
  required double arm,
  required double width,
  required double labelSize,
  required double labelGap,
  required SheetPaintLayer layer,
  int? from,
  int? to,
}) sync* {
  SheetWords frameBeside(
    int frame,
    List<Offset> corners,
    int argb, {
    required int by,
    int after = 0,
  }) => cameraCrossLabel(
    cameraFrameLabel(frame),
    corners,
    at: cameraFrameCentre(corners),
    taken: _eitherSide(path, frame, by, place),
    argb: argb,
    size: labelSize,
    gap: labelGap,
    layer: layer,
    after: after,
  );
  final first = math.max(path.firstFrame, from ?? path.firstFrame);
  final last = math.min(path.lastFrame, to ?? path.lastFrame);
  final keyed = {for (final key in path.keys) key.frameIndex};
  for (
    var frame = (first + every - 1) ~/ every * every;
    frame <= last;
    frame += every
  ) {
    if (keyed.contains(frame)) {
      continue;
    }
    final corners = [for (final corner in path.frameAt(frame)) place(corner)];
    final argb = frame < playhead
        ? cameraTickPastArgb
        : frame > playhead
        ? cameraTickAheadArgb
        : cameraBetweenArgb;
    yield* cameraCrossMarks(
      corners,
      at: cameraFrameCentre(corners),
      argb: argb,
      arm: arm,
      width: width,
      layer: layer,
    );
    yield frameBeside(frame, corners, argb, by: every);
  }
  for (final key in path.keys) {
    final point = cameraPlaceIsAPoint(key.corners);
    if (key.frameIndex >= first &&
        key.frameIndex <= last &&
        (key.name != null || !point)) {
      yield frameBeside(
        key.frameIndex,
        [for (final corner in key.corners) place(corner)],
        cameraKeyArgb(key.role),
        by: 1,
        after: point ? 1 : 0,
      );
    }
  }
}
