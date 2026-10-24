import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/project_background.dart';
import 'display_resample.dart';
import 'raster_picture.dart';

/// Paints the project PAPER (R10-⑥ / R3b): the paper color, alpha
/// included — a thinned paper lets the pasteboard and the backdrop behind
/// it show through, which is the four-plane stage's whole point. The
/// checkerboard belongs to an ABSENT plane ([paintAbsentPlane]); the paper
/// itself never checkers.
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
/// door A4 shut on `filterQuality`. An edge not anti-aliased is cut on the
/// grid of [pixelRatio] ([displayEdgeRect]).
void paintProjectPaper(
  Canvas canvas,
  Rect rect,
  ProjectBackground background, {
  required bool antiAlias,
  required double pixelRatio,
}) {
  final color = Color(background.paintedArgb);
  if (color.a <= 0) {
    return;
  }
  canvas.drawRect(
    displayEdgeRect(
      canvas,
      rect,
      antiAlias: antiAlias,
      pixelRatio: pixelRatio,
    ),
    Paint()
      ..color = color
      ..isAntiAlias = antiAlias,
  );
}

/// The alpha checkerboard — what an ABSENT plane shows (F-114: 「해당 용지
/// 부분이 체크무늬되도록」), and what the export and import previews draw
/// where a picture's alpha stays open. Canvas-space cells, so the checker
/// zooms with the artwork and always reads at drawing resolution — an
/// absent plane on screen lays it in the screen's ([paintAbsentPlane]).
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

/// An ABSENT plane on screen (F-114): the checkerboard over [region] — a
/// rect in whatever space the canvas is in now, its edge cut by
/// [antiAlias] — in the SCREEN's cells. [screen] is the canvas's transform
/// where the painter's box is: `canvas.getTransform()` at the top of its
/// `paint`, before the view or a camera moved it.
///
/// 🚨ONE CELL GRID FOR EVERY ABSENT PLANE ON SCREEN
/// (camera-checkerboard-rides-the-canvas, 2026-10-23). The editing canvas
/// laid its planes in its box, so its cells sat eight logical pixels from
/// the box's corner at every zoom; laid under the view and the camera, the
/// same checker took the canvas's cells — measured four pixels at 50% —
/// and pressing play with the camera view on changed the pattern. The
/// playback flag's own law is 「the way the editing canvas shows it」
/// (`PlaybackFramePainter.checkersAbsentPlanes`, F-114), and 유저 09-17:
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」. So every absent plane on
/// screen — the canvas's stage, the film's floor and apron, a paper seen
/// through the camera, the fade's wash — lays its cells here, and planes
/// that meet are one pattern. ↩️Each called [paintAlphaCheckerboard] in
/// the space it happened to be in.
void paintAbsentPlane(
  Canvas canvas,
  Rect region, {
  required Float64List screen,
  required bool antiAlias,
}) {
  final onScreen = Matrix4.tryInvert(Matrix4.fromFloat64List(screen));
  if (onScreen == null) {
    return;
  }
  onScreen.multiply(Matrix4.fromFloat64List(canvas.getTransform()));
  final back = Matrix4.tryInvert(onScreen);
  if (back == null) {
    return;
  }
  canvas.save();
  canvas.clipRect(region, doAntiAlias: antiAlias);
  canvas.transform(back.storage);
  // Past the region on every side, so the clip alone cuts its edge: the
  // checker's own rect is anti-aliased, and laid ON the edge it thinned the
  // edge's pixels however the clip had cut them (measured 10-23: a row a
  // quarter pasteboard at 150% under a clip that kept it whole).
  paintAlphaCheckerboard(
    canvas,
    MatrixUtils.transformRect(onScreen, region).inflate(2),
  );
  canvas.restore();
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
