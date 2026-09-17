import 'package:flutter/widgets.dart';

import '../../models/project_background.dart';

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
void paintAlphaCheckerboard(Canvas canvas, Rect rect) {
  const cell = 8.0;
  canvas.save();
  canvas.clipRect(rect);
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  final gray = Paint()..color = const Color(0xFFCCCCCC);
  final firstColumn = (rect.left / cell).floor();
  final firstRow = (rect.top / cell).floor();
  for (var row = firstRow; row * cell < rect.bottom; row += 1) {
    for (var column = firstColumn; column * cell < rect.right; column += 1) {
      if ((row + column).isEven) {
        continue;
      }
      canvas.drawRect(
        Rect.fromLTWH(column * cell, row * cell, cell, cell),
        gray,
      );
    }
  }
  canvas.restore();
}
