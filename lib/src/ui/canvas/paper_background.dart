import 'package:flutter/widgets.dart';

import '../../models/project_background.dart';

/// Paints the project PAPER (R10-⑥ / R3b): the paper color, alpha
/// included — a thinned paper lets the pasteboard and the backdrop behind
/// it show through, which is the four-plane stage's whole point. The old
/// alpha checkerboard moved to the backdrop's alpha-preview toggle
/// ([paintAlphaCheckerboard]); the paper itself never checkers.
void paintProjectPaper(
  Canvas canvas,
  Rect rect,
  ProjectBackground background,
) {
  final color = Color(background.argb);
  if (color.a <= 0) {
    return;
  }
  canvas.drawRect(rect, Paint()..color = color);
}

/// The BACKDROP plane under the alpha-preview toggle, as a painter: fills
/// whatever it is given with the checkerboard.
class AlphaCheckerboardPainter extends CustomPainter {
  const AlphaCheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    paintAlphaCheckerboard(canvas, Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant AlphaCheckerboardPainter oldDelegate) => false;
}

/// The ALPHA-PREVIEW toggle itself (R3b): app VIEW state, never project
/// data and never printed — flip it to see the backdrop as the open alpha
/// an alpha export would leave.
final ValueNotifier<bool> alphaPreviewEnabled = ValueNotifier<bool>(false);

/// The alpha checkerboard — the ALPHA-PREVIEW toggle's rendering of the
/// backdrop plane: where it shows is exactly where an alpha export stays
/// open. Canvas-space cells, so the checker zooms with the artwork and
/// always reads at drawing resolution.
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
