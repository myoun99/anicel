import 'dart:math' as math;
import 'dart:ui';

import '../../models/frame.dart' show InbetweenMark;

/// The box the timeline family draws an in-between mark in, in a [cell]
/// whose word is set at [fontSize] — the rows, the flip window, the folded
/// strip, the storyboard's panels: HALF the ● that word used to print, on
/// each axis as much of that as the cell has.
///
/// 🗣️유저 2026-09-24: 「타임라인쪽 점 마크도 지금 너무 크니까 작게하고싶어.
/// 지금의 절반?」. 🔬Measured in the app's face: the ● a 14px bold cell word
/// printed inked 12–13px across (0.89em), so the mark is 0.45em across.
///
/// 🚨★★★IT KEEPS ITS SIZE AND NARROWS, AS A WORD DOES (F-297, 유저
/// 2026-10-05): 「점 지금 줌 낮아지면 크기 자체가 작아지는데 그게아니라
/// 글자랑 똑같이 법 통일해서 가로가 작아지도록」. ↩️It shrank WHOLE with a
/// tight cell — the type fitted to the cell, under every cell narrower
/// than 14px, times 0.225 — on the reading that 「a circle cannot narrow on
/// one axis the way a word does」 (D39-2). It can: narrowed, a disc is the
/// stadium [inbetweenMarkShape] draws.
///
/// It keeps to its cell at every zoom (I-22: the ten-minute floor's cells
/// are an eighth of a pixel) — it is what lets the tile that holds the cell
/// be the only one that draws it.
Size timelineInbetweenMarkSize(double fontSize, {required Size cell}) {
  final across = fontSize * 0.45;
  return Size(math.min(across, cell.width), math.min(across, cell.height));
}

/// The timesheet's in-between mark: the small dot the sheet already drew
/// inside blocks, now on an unnamed drawing's head too (유저 2026-09-24:
/// 「타임시트패널에서 동그라미는 작은걸로 통일」). ↩️The head printed the mark as
/// its 10px cel-number text, about twice across.
const double timesheetInbetweenMarkRadius = 2.8;

/// Where an in-between mark stands and the box it fills.
typedef InbetweenMarkPlace = ({Offset center, Size size});

/// The shape of a mark that fills [place]: a disc in a square box, and in a
/// box narrowed on one axis the stadium a rounded rect as round as it is
/// narrow makes — the one filled shape the tiles bake
/// (`TimelineGridTileOpWriter.rrectFill`), so a tile and the classic pass
/// draw one mark.
RRect inbetweenMarkShape(InbetweenMarkPlace place) => RRect.fromRectAndRadius(
  Rect.fromCenter(
    center: place.center,
    width: place.size.width,
    height: place.size.height,
  ),
  Radius.circular(place.size.shortestSide / 2),
);

/// THE drawer of an in-between mark — every surface that shows one asks
/// here, so a mark is one shape wherever it stands and whatever put it there
/// (a dot inside a block, a drawing with no cel number: one mark, 유저
/// 2026-09-24).
///
/// It is drawn, not printed: a font's ● sits where the face puts it — BIZ's
/// was a size and a baseline of its own — and a circle is where its centre is.
void paintInbetweenMark(
  Canvas canvas,
  InbetweenMark mark,
  InbetweenMarkPlace place,
  Color color,
) {
  switch (mark) {
    case InbetweenMark.one:
      canvas.drawRRect(inbetweenMarkShape(place), Paint()..color = color);
  }
}
