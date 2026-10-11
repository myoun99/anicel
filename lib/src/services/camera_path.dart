import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show listEquals;

import '../models/camera_work_marks.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/key_range_move.dart' show transformKeyAgreedNames;
import '../models/sheet_marks.dart';
import '../models/sheet_paint_layer.dart';
import 'camera_frame_corners.dart';

/// One key of a camera's path: its frame on the canvas, the colour its place
/// among all the camera's keys gives it, and the name its lanes agree on.
typedef CameraPathKey = ({
  int frameIndex,
  List<Offset> corners,
  CameraKeyRole role,
  String? name,
});

/// A camera's path over its cut's canvas (I-89 ④): its frame at every key,
/// and at any frame from the first key to the last as playback shows it.
class CameraPath {
  CameraPath._(this._cut, this._frameSize, this.keys)
    : _frames = List<List<Offset>?>.filled(
        keys.last.frameIndex - keys.first.frameIndex + 1,
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
    return CameraPath._(cut, frameSize, [
      for (final (index, frame) in frames.indexed)
        (
          frameIndex: frame.frameIndex,
          corners: frame.corners,
          role: CameraKeyRole.at(index, frames.length),
          name: names[frame.frameIndex],
        ),
    ]);
  }

  final Cut _cut;
  final CanvasSize _frameSize;

  /// Every key, first to last.
  final List<CameraPathKey> keys;

  /// The frames between the keys, read as they are asked for.
  final List<List<Offset>?> _frames;

  int get firstFrame => keys.first.frameIndex;
  int get lastFrame => keys.last.frameIndex;

  /// The camera's frame at [frameIndex], from [firstFrame] to [lastFrame].
  List<Offset> frameAt(int frameIndex) =>
      _frames[frameIndex - firstFrame] ??= cameraFrameShownAt(
        _cut,
        _frameSize,
        frameIndex,
      );
}

/// [path] as the canvas and the export write it (I-89 ④⑥, 유저 2026-10-11:
/// 「캔버스랑 출력쪽은 키마다 전부 사각형 그리는거야. 사각형이랑 십자랑 한
/// 세트로. 위치도 다 통일」): the trail the camera's centre draws, and at
/// every key its frame with the cross at its centre and its label at the
/// frame's top-left corner, in the colour its place among all the camera's
/// keys gives it. The conte's paper frames its first and last alone
/// (`conteCameraMarksOf`).
///
/// A label is the key's name, else the frame it stands on as the frame
/// cursor counts it (「사각형있는건 A가 왼쪽위인거처럼 24f도 사각형존재하게
/// 되니까 왼쪽위」).
///
/// [place] lays a canvas point on the surface. Only the frames [from] to
/// [to] are written, where a surface keeps to some.
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
      if (first < last)
        [
          for (var frame = first; frame <= last; frame += 1)
            place(cameraFrameCentre(path.frameAt(frame))),
        ],
    ],
    keys: [
      for (final key in path.keys)
        if (key.frameIndex >= first && key.frameIndex <= last)
          CameraMarkedKey(
            corners: [for (final corner in key.corners) place(corner)],
            role: key.role,
            framed: true,
            cross: CameraKeyCross.centre,
            label: key.name ?? '${key.frameIndex + 1}f',
          ),
    ],
    sizes: sizes,
    layer: layer,
  );
}

/// The crosses [path] wears in time on the canvas (I-89 ④ 「공간 + 시간」,
/// 유저 2026-10-10: 「시간 표시가 지금 동그란 점인데 동일한 십자가로 … 점은
/// 1f2f3f 정하는게아니라 커스텀으로」): one at the camera's centre every
/// [every] frames counted from the cut's first, square to its frame there —
/// grey where the [playhead] has passed, blue where it is yet to go, in ink
/// where it stands. A key wears its own cross where a tick would fall.
///
/// [place], [from] and [to] as [cameraPathMarks] takes them.
Iterable<SheetMark> cameraPathTicks(
  CameraPath path, {
  required Offset Function(Offset point) place,
  required int every,
  required int playhead,
  required double arm,
  required double width,
  required SheetPaintLayer layer,
  int? from,
  int? to,
}) sync* {
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
    yield* cameraCrossMarks(
      corners,
      at: cameraFrameCentre(corners),
      argb: frame < playhead
          ? cameraTickPastArgb
          : frame > playhead
          ? cameraTickAheadArgb
          : cameraBetweenArgb,
      arm: arm,
      width: width,
      layer: layer,
    );
  }
}
