import 'dart:ui';

import '../../models/frame.dart' show InbetweenMark;
import 'timeline_cell_style.dart' show timelineFittedGlyphFontSize;

/// How large the timeline family draws an in-between mark in a cell of
/// [cellExtent] × [crossExtent] whose word is set at [fontSize] — the rows,
/// the flip window, the folded strip, the storyboard's panels: HALF the ●
/// that word used to print.
///
/// 🗣️유저 2026-09-24: 「타임라인쪽 점 마크도 지금 너무 크니까 작게하고싶어.
/// 지금의 절반?」. 🔬Measured in the app's face: the ● a 14px bold cell word
/// printed inked 12–13px across (0.89em), so the mark is 0.45em across.
///
/// A circle cannot narrow on one axis the way a word does (B), so it shrinks
/// with a tight cell as every mark does (D39-2, [timelineFittedGlyphFontSize])
/// — which keeps it inside its cell at every zoom.
double timelineInbetweenMarkRadius(
  double fontSize, {
  required double cellExtent,
  required double crossExtent,
}) =>
    timelineFittedGlyphFontSize(
      fontSize,
      cellExtent,
      crossExtent: crossExtent,
    ) *
    0.225;

/// The timesheet's in-between mark: the small dot the sheet already drew
/// inside blocks, now on an unnamed drawing's head too (유저 2026-09-24:
/// 「타임시트패널에서 동그라미는 작은걸로 통일」). ↩️The head printed the mark as
/// its 10px cel-number text, about twice across.
const double timesheetInbetweenMarkRadius = 2.8;

/// THE drawer of an in-between mark — every surface that shows one asks
/// here, so a mark is one shape wherever it stands and whatever put it there
/// (a dot inside a block, a drawing with no cel number: one mark, 유저
/// 2026-09-24).
///
/// It is drawn, not printed: a font's ● sits where the face puts it — BIZ's
/// was a size and a baseline of its own — and a circle is where its centre is.
void paintInbetweenMark(
  Canvas canvas,
  InbetweenMark mark, {
  required Offset center,
  required double radius,
  required Color color,
}) {
  switch (mark) {
    case InbetweenMark.one:
      canvas.drawCircle(center, radius, Paint()..color = color);
  }
}
