import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/project_background.dart';
import 'raster_picture.dart';

/// Paints the project PAPER (R10-⑥ / R3b): the paper color, alpha
/// included — a thinned paper lets the pasteboard and the backdrop behind
/// it show through, which is the four-plane stage's whole point. The
/// checkerboard belongs to an ABSENT plane ([paintAlphaCheckerboard]); the
/// paper itself never checkers.
///
/// A paper that is NONE (F-114, 유저 2026-09-15: 「없음버튼 누르면 없는상태.
/// 즉 해당 용지부분이 체크무늬되도록」) paints nothing here, on every route
/// that paints paper through this function; the checkerboard where it would
/// be is the stage planes' to draw, never this function's.
///
/// [antiAlias] is REQUIRED: on the display the paper's edge is the canvas's
/// edge, and how it is cut is the display law's answer
/// (`displayEdgeAntiAliased` in `display_resample.dart` — F-67-paper-edge).
/// A default here would let a new route inherit an edge nobody chose, the
/// door A4 shut on `filterQuality`.
void paintProjectPaper(
  Canvas canvas,
  Rect rect,
  ProjectBackground background, {
  required bool antiAlias,
}) {
  final color = Color(background.paintedArgb);
  if (color.a <= 0) {
    return;
  }
  canvas.drawRect(
    rect,
    Paint()
      ..color = color
      ..isAntiAlias = antiAlias,
  );
}

/// The alpha checkerboard as a painter: fills whatever it is given with it.
class AlphaCheckerboardPainter extends CustomPainter {
  const AlphaCheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    paintAlphaCheckerboard(canvas, Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant AlphaCheckerboardPainter oldDelegate) => false;
}

/// The alpha checkerboard — what an ABSENT plane shows (F-114: 「해당 용지
/// 부분이 체크무늬되도록」), and what the export and import previews draw
/// where a picture's alpha stays open. Canvas-space cells, so the checker
/// zooms with the artwork and always reads at drawing resolution.
///
/// 🪦It used to be the rendering of an ALPHA-PREVIEW toggle in the settings
/// menu (R3b). 유저 2026-09-16: 「설정의 알파 미리보기 필요없어졌으니 잔재 싹
/// 삭제」 — the switch and its app-view notifier are gone; the checkerboard
/// stayed, because every OTHER caller was drawing real absent alpha.
///
/// 🚨ONE DRAW, HOWEVER MUCH IT COVERS (F-373, 2026-10-17): one period of
/// the checker ([_checkerTile]) repeated by a shader. It was a `drawRect`
/// per grey cell, and on Impeller nothing keeps a still surface baked
/// (`StaticRaster.capturePays`), so every frame replayed every one of
/// them: under a 4000×3000 picture in the import window's preview that
/// was about 94,000 rects and 370–540 ms of raster a frame on the Surface
/// Pro 11, and a press in the window showed most of a second late (유저
/// F-373: 「배치창 조작이 너무느림」). As one tile the same frames
/// rasterized in 3–65 ms — no slower than with no checker at all.
///
/// ⛔NEAREST, not smoothed: drawn on that device against the cells it
/// replaced, nearest gave the same pixels at 1× and 2× and the same grain
/// zoomed out to 0.2×, where smoothing (low · medium) blurred the cells
/// and washed the grain out.
void paintAlphaCheckerboard(Canvas canvas, Rect rect) {
  canvas.drawRect(rect, Paint()..shader = _checkerShader);
}

/// [_checkerTile] repeated from the origin of whatever space the canvas is
/// in — the cells' own grid, so they zoom and pan with the artwork.
final ui.ImageShader _checkerShader = ui.ImageShader(
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

/// One period of the checker, drawn once for the process: two cells of
/// eight by two, white, the two where row + column is odd grey.
ui.Image _checkerTile() {
  final grey = Paint()..color = const Color(0xFFCCCCCC);
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 16, 16),
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..drawRect(const Rect.fromLTWH(8, 0, 8, 8), grey)
    ..drawRect(const Rect.fromLTWH(0, 8, 8, 8), grey);
  return rasterPicture(recorder, 16, 16);
}
