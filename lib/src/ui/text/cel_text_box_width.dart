import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../models/canvas_point.dart';
import '../../models/cel_text.dart';
import '../../models/text_cel_style.dart';
import '../../services/cel_text_box_edits.dart' show celTextMinWrapWidth;
import '../../services/cel_text_edits.dart';
import 'cel_text_layout.dart';

/// A TEXT THAT GROWS, AND A BOX — SWAPPED (R9-rest).
///
/// 🗣️유저 2026-10-06, of whether a text is one that grows with what is
/// typed or a box its lines wrap in: 「이부분 고정할지 비고정할지는
/// 도구설정에서 스왑가능」 — and of the swap, the answer taken with the
/// settings' layout: 「상자 폭을 바꿔도 보이는 모양은 그대로. 고정→자동이면
/// 줄이 꺾이던 자리에 Enter가 들어갑니다」.
///
/// So neither moves a letter: every one stands where it stood, on the same
/// line. What changes is what the NEXT letter typed does — run on, or wrap.
///
/// They read the letters as the engine sets them, which is why they are
/// here and not beside the box's other edits (`cel_text_box_edits.dart`):
/// how wide a line is, and where a line broke for want of room, only the
/// layout knows.

/// [content] as a BOX that looks the same: as wide as the next whole pixel
/// PAST its longest line, hung where its lines already stand.
///
/// The anchor of a text that grows is the point its lines are set ABOUT; a
/// box's is its top left corner. It moves there, by the text's own
/// alignment, so that no line does.
///
/// ⚠️PAST the longest line, and never exactly as wide as it: the engine
/// aligns a line only where it has room (`_roomToAlign`, measured
/// 2026-10-06), and a line that filled its box to the pixel would be set
/// half its tracking off the others.
///
/// [content] itself for one that is a box already — and for one with no
/// letters: it has no line to be as wide as.
///
/// Written in COLUMNS it is the same swap read down them: as long as the
/// next whole pixel past its longest column, hung by its top right corner
/// where its columns already stand.
CelTextContent celTextBoxed(CelTextContent content) {
  if (content.wrapWidth != null || content.isEmpty) {
    return content;
  }
  final layout = layoutCelText(content);
  final block = layout.block;
  final room = math.max(
    (content.vertical ? block.height : block.width).floorToDouble() + 1,
    celTextMinWrapWidth,
  );
  final corner = layout.toCanvas(_boxCornerOf(content, block, room));
  layout.dispose();
  return content.copyWith(
    wrapWidth: room,
    anchor: CanvasPoint(x: corner.dx, y: corner.dy),
  );
}

/// Where a box with [room] for its letters hangs — its anchor, in the
/// text's own frame — so that the letters of [block], a text that grows,
/// stay where they are: its top left corner, or written in columns its top
/// right.
Offset _boxCornerOf(CelTextContent content, Rect block, double room) {
  if (content.vertical) {
    return Offset(block.right, switch (content.align) {
      TextCelAlign.left => block.top,
      TextCelAlign.center => block.center.dy - room / 2,
      TextCelAlign.right => block.bottom - room,
    });
  }
  return Offset(switch (content.align) {
    TextCelAlign.left => block.left,
    TextCelAlign.center => block.center.dx - room / 2,
    TextCelAlign.right => block.right - room,
  }, block.top);
}

/// [content] as a text that GROWS and looks the same: a break typed in
/// wherever a line had wrapped for want of room, and the anchor moved from
/// the box's corner to the point its lines stand about.
///
/// 🔬Measured 2026-10-06: a line that wraps at a space keeps that space,
/// hanging past its end and counted by no alignment — and a space before a
/// TYPED break is counted by none either. So the break goes in AFTER the
/// space and every letter is kept: one put in its place would join two
/// words the day the break is taken out again.
///
/// [content] itself for one that grows already.
CelTextContent celTextUnboxed(CelTextContent content) {
  final width = content.wrapWidth;
  if (width == null) {
    return content;
  }
  final layout = layoutCelText(content);
  var broken = content;
  // From the last place to the first, so the ones still to come stand where
  // the layout said.
  for (final place in layout.wrapPlaces.reversed) {
    broken = celTextWithLetters(
      broken,
      range: (start: place, end: place),
      letters: '\n',
      // Unread: a text with a line that wrapped has letters.
      nextLetterStyle: const TextLetterStyle(),
    );
  }
  // How far along its room the point its letters stand ABOUT is: the head
  // of a line or a column, its middle, or its foot.
  final along = switch (content.align) {
    TextCelAlign.left => 0.0,
    TextCelAlign.center => width / 2,
    TextCelAlign.right => width,
  };
  final about = layout.toCanvas(
    content.vertical ? Offset(0, along) : Offset(along, 0),
  );
  layout.dispose();
  return broken.copyWith(
    wrapWidth: null,
    anchor: CanvasPoint(x: about.dx, y: about.dy),
  );
}

/// [content] written in COLUMNS ([vertical]) or in lines, WHERE IT STANDS:
/// the top left corner of its letters' block stays where it is.
///
/// A box keeps its SHAPE as near as a box can: the room its letters had
/// across them becomes the room they have along them — a box four lines
/// tall is, in columns, four lines long — and its other side is whatever
/// its letters then take.
///
/// [content] itself when it is written that way already.
CelTextContent celTextWrittenAs(
  CelTextContent content, {
  required bool vertical,
}) {
  if (content.vertical == vertical) {
    return content;
  }
  final before = layoutCelText(content);
  final block = before.block;
  final corner = before.toCanvas(block.topLeft);
  before.dispose();
  final written = content.copyWith(
    vertical: vertical,
    wrapWidth: content.wrapWidth == null
        ? null
        : math.max(
            (vertical ? block.height : block.width).ceilToDouble(),
            celTextMinWrapWidth,
          ),
  );
  // Set once to learn where its block's corner falls, and moved by what
  // that is off.
  final after = layoutCelText(written);
  final falls = after.toCanvas(after.block.topLeft);
  after.dispose();
  return written.copyWith(
    anchor: CanvasPoint(
      x: written.anchor.x + corner.dx - falls.dx,
      y: written.anchor.y + corner.dy - falls.dy,
    ),
  );
}
