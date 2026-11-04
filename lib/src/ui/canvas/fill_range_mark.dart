import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/canvas_point.dart';
import 'raster_picture.dart';

/// 🚨★★★THE RANGE A FILL HELD DOWN WILL COVER, AS THE CANVAS MARKS IT
/// (I-160-Q1 a, 유저 2026-11-04 「TVPaint 처럼 체크 격자」): a checker of
/// white and black over every pixel the fill would write into, drawn on the
/// row the fill lands on and under the rows above it.
///
/// 🗣️유저, with the answer: 「정확히는 체크격자가 그림 위에 오는것임. 즉 현재
/// 행 위. 그 위에 레이어있으면 체크격자 가려져서 사라지는거 인지하고있음.
/// 체크격자는 그리고 래스터로하면 느리니 최대한 선택도구 개미줄처럼 벡터로.
/// 그리고 체크격자는 흰색/검정을 불투명도 50%정도로 낮춰서. 즉 칠하려는곳의
/// 밑 색이 살짝 보임. 근데 렉있다거나 무거워진다거나 하면 불투명도 낮춘다거나
/// 하는거없이 100%로 해도됨. 성능위주」.
///
/// ⛔Not a landing preview (`LandingPreview`): those are the pixels a
/// landing writes, drawn in the row's own paint at its opacity and made
/// tile by tile when reduced (F-240). This marks where a fill reaches and
/// is none of the row's pixels — drawn after the row, at its own 50%.
final class FillRangeMark {
  /// The mark of [contours], closed outlines on the pixel grid in the space
  /// of the row the fill lands on (`FillRange.contoursWithin`).
  FillRangeMark(List<List<CanvasPoint>> contours)
    : outline = _outlineOf(contours),
      bounds = _boundsOf(contours);

  /// Every contour as one path: the fill carves the holes out, the walk
  /// winding a hole against its component.
  final ui.Path outline;

  /// Everything [paint] draws, in the row's space — [Rect.zero] for none.
  final Rect bounds;

  /// Whether [paint] draws nothing.
  bool get isEmpty => bounds.isEmpty;

  /// The checker over [outline]: one path filled by one shader — the vector
  /// the user asked for, as the ants are, with no picture of the range made.
  void paint(Canvas canvas) => canvas.drawPath(outline, _checkerPaint);

  static ui.Path _outlineOf(List<List<CanvasPoint>> contours) {
    final path = ui.Path();
    for (final contour in contours) {
      path.addPolygon([
        for (final point in contour) Offset(point.x, point.y),
      ], true);
    }
    return path;
  }

  static Rect _boundsOf(List<List<CanvasPoint>> contours) {
    Rect? bounds;
    for (final contour in contours) {
      for (final point in contour) {
        final at = Rect.fromLTWH(point.x, point.y, 0, 0);
        bounds = bounds?.expandToInclude(at) ?? at;
      }
    }
    return bounds ?? Rect.zero;
  }
}

/// [_checkerTile] repeated from the origin of the row's space: canvas-space
/// cells, as the alpha checkerboard's (`paintAlphaCheckerboard`), so the
/// mark lies on the row's grid at every zoom and in the frame's one
/// picture. Nearest, for the same reason as that one's.
final Paint _checkerPaint = Paint()
  ..shader = ui.ImageShader(
    _checkerTile(),
    TileMode.repeated,
    TileMode.repeated,
    Float64List(16)
      ..[0] = 1
      ..[5] = 1
      ..[10] = 1
      ..[15] = 1,
    filterQuality: FilterQuality.none,
  );

/// One period of the mark: two by two cells of eight, white where row +
/// column is even and black where it is odd, each at half opacity — 「밑 색이
/// 살짝 보임」.
ui.Image _checkerTile() {
  final recorder = ui.PictureRecorder();
  final white = Paint()..color = const Color(0x80FFFFFF);
  final black = Paint()..color = const Color(0x80000000);
  // Four cells, none over another: a translucent cell drawn over another
  // would blend the two.
  Canvas(recorder)
    ..drawRect(const Rect.fromLTWH(0, 0, 8, 8), white)
    ..drawRect(const Rect.fromLTWH(8, 8, 8, 8), white)
    ..drawRect(const Rect.fromLTWH(8, 0, 8, 8), black)
    ..drawRect(const Rect.fromLTWH(0, 8, 8, 8), black);
  return rasterPicture(recorder, 16, 16);
}
