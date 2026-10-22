import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/canvas_point.dart';
import '../models/cel_text.dart';
import 'cel_text_frame.dart';

/// THE EDITS A TEXT'S BOX TAKES (R9-rest, the text tool) — what a hand on
/// its corner, outside it or on its edge does — as values: a content in, a
/// content out. The letters' own edits are `cel_text_edits.dart`.
///
/// ⚠️A text turns about its ANCHOR (`CelTextContent.anchor`), and a hand on
/// its box keeps another point still — the one law every box on the canvas
/// keeps (F-222): a scale, the box's CENTRE (유저 2026-09-22: 「확대/축소의
/// 기준점은 항상 상자의 중심」); a turn, the box's CROSS, which is the centre
/// until a hand carries it (유저 2026-09-20: 「앵커포인트는 회전시 앵커를
/// 기준으로 회전해」 — `celTextCrossOf`). So each of these moves the anchor
/// as well, to where that point standing still puts it.

/// The smallest a letter is set at, in canvas pixels. A scale stops there
/// and so does the size setting: the engine sets nothing at a size of none,
/// and a text scaled to nothing could not be scaled back.
const double celTextMinFontSize = 1;

/// The narrowest a box wraps at, in canvas pixels.
const double celTextMinWrapWidth = 1;

/// HOW LONG THE BOX IS THAT A TEXT WHICH GROWS IS SET IN, its longest line —
/// or column — being [longest] long as it is drawn: to the next whole pixel
/// PAST it. It is the box the text is made when it is made one
/// (`celTextBoxed`).
///
/// 🗣️유저 2026-10-18 (text-letters-lean-and-underline-Q5, of a text that
/// grows whose paragraphs are aligned unlike): 「글 덩어리 하나가 첫 문단의
/// 정렬로 기준점에 선다」 — the text is ONE block, a box its longest line
/// fills, and each paragraph stands in it as its own alignment says. So it
/// is set in the very box it would be made, and made one no letter moves
/// (유저 2026-10-06, `cel_text_box_width.dart`).
///
/// ⚠️PAST it, and never exactly as long: the engine aligns a line only where
/// it has room (measured 2026-10-06, `_frameOf` in `cel_text_lines.dart`).
double celTextBoxLengthPast(double longest) =>
    math.max(longest.floorToDouble() + 1, celTextMinWrapWidth);

/// [content] with every LENGTH of it [factor] times what it was — the
/// letters' size, their tracking and their outline, and the box's width
/// and least height — about [centre], which stays where it is.
///
/// 🗣️The press table 유저 took on 2026-10-06: a corner scales 「글자가
/// 커진다, 중심 기준」 — the letters themselves, not a picture of them.
///
/// ⚠️[factor] stops where the smallest letter would go under
/// [celTextMinFontSize].
CelTextContent celTextScaledAbout(
  CelTextContent content,
  double factor,
  CanvasPoint centre,
) {
  final smallest = content.spans.fold(
    double.infinity,
    (size, span) => math.min(size, span.style.fontSize),
  );
  final scale = smallest.isFinite
      ? math.max(factor, celTextMinFontSize / smallest)
      : factor;
  final wrapWidth = content.wrapWidth;
  final minHeight = content.minHeight;
  return content.copyWith(
    spans: [
      for (final span in content.spans)
        CelTextSpan(
          text: span.text,
          style: span.style.copyWith(
            fontSize: span.style.fontSize * scale,
            letterSpacing: span.style.letterSpacing * scale,
            outlineWidth: span.style.outlineWidth * scale,
          ),
        ),
    ],
    wrapWidth: wrapWidth == null
        ? null
        : math.max(wrapWidth * scale, celTextMinWrapWidth),
    minHeight: minHeight == null
        ? null
        : math.max(minHeight * scale, celTextMinWrapWidth),
    anchor: CanvasPoint(
      x: centre.x + (content.anchor.x - centre.x) * scale,
      y: centre.y + (content.anchor.y - centre.y) * scale,
    ),
  );
}

/// [content] turned a further [degrees] clockwise about [centre], which
/// stays where it is.
CelTextContent celTextTurnedAbout(
  CelTextContent content,
  double degrees,
  CanvasPoint centre,
) => _keptAt(
  content,
  content.copyWith(rotationDegrees: content.rotationDegrees + degrees),
  centre,
);

/// [content] leaning by [degrees] ([CelTextContent.skewDegrees]) about
/// [centre], which stays where it is.
CelTextContent celTextLeanedAbout(
  CelTextContent content,
  double degrees,
  CanvasPoint centre,
) => _keptAt(content, content.copyWith(skewDegrees: degrees), centre);

/// [content] mirrored — [flipped] — or not, about [centre], which stays
/// where it is ([CelTextContent.flipped]).
CelTextContent celTextFlippedAbout(
  CelTextContent content,
  CanvasPoint centre, {
  required bool flipped,
}) => _keptAt(content, content.copyWith(flipped: flipped), centre);

/// [changed] — [content] turned, leaned or mirrored otherwise — standing so
/// the point of it at [centre] stays there: its anchor carried to where
/// that point standing still puts it.
CelTextContent _keptAt(
  CelTextContent content,
  CelTextContent changed,
  CanvasPoint centre,
) {
  final still = Offset(centre.x, centre.y);
  final local = CelTextFrame.of(content).toLocal(still);
  final anchor = still - CelTextFrame.of(changed).onCanvas(local);
  return changed.copyWith(anchor: CanvasPoint(x: anchor.dx, y: anchor.dy));
}

/// The way [content]'s letters run, as one step of it on the canvas: along
/// its lines — or, written in columns, DOWN them — leaned, mirrored and
/// turned as the text is ([CelTextFrame]).
///
/// What a box's room is measured along ([CelTextContent.wrapWidth]), and so
/// what a hand on the edge that sets it carries the anchor along.
({double dx, double dy}) celTextLettersWay(CelTextContent content) {
  final frame = CelTextFrame.of(content);
  final step = content.vertical ? frame.yStep : frame.xStep;
  return (dx: step.dx, dy: step.dy);
}

/// How far [travel], a hand's travel on the canvas, goes the way
/// [content]'s letters run ([celTextLettersWay]) and the way its lines
/// stack ([celTextStackingWay]) — read in its own frame, where a box's
/// room and its height are measured.
({double letters, double stacking}) celTextTravelAlong(
  CelTextContent content,
  Offset travel,
) {
  final local = CelTextFrame.of(content).inFrame(travel);
  return content.vertical
      ? (letters: local.dy, stacking: -local.dx)
      : (letters: local.dx, stacking: local.dy);
}

/// A box [content] given [width] of room by one of the two edges its
/// letters run between: the other edge stays where it is.
///
/// A box hangs from its anchor — its top left corner, or written in columns
/// its top right — so the FAR edge only changes the room, and the edge the
/// anchor is on ([byLeadingEdge]: the left one, or in columns the top)
/// carries the anchor along the letters' way by what the room lost.
///
/// ⛔For a box only: a text that grows has no room to drag.
CelTextContent celTextBoxWidened(
  CelTextContent content,
  double width, {
  required bool byLeadingEdge,
}) {
  final before = content.wrapWidth;
  if (before == null) {
    throw ArgumentError.value(content, 'content', 'has no box to widen');
  }
  final after = math.max(width, celTextMinWrapWidth);
  if (!byLeadingEdge) {
    return content.copyWith(wrapWidth: after);
  }
  final way = celTextLettersWay(content);
  final along = before - after;
  return content.copyWith(
    wrapWidth: after,
    anchor: CanvasPoint(
      x: content.anchor.x + along * way.dx,
      y: content.anchor.y + along * way.dy,
    ),
  );
}

/// The way [content]'s lines stack, as one step of it on the canvas: down
/// them — or, written in columns, leftwards across them — leaned, mirrored
/// and turned as the text is ([CelTextFrame]).
///
/// What a box's least height is measured along
/// ([CelTextContent.minHeight]), and so what a hand on the edge that sets
/// it carries the anchor along.
({double dx, double dy}) celTextStackingWay(CelTextContent content) {
  final frame = CelTextFrame.of(content);
  final step = content.vertical ? -frame.xStep : frame.yStep;
  return (dx: step.dx, dy: step.dy);
}

/// How deep [content]'s box is — across its lines, or the way its columns
/// stack — with its letters [lettersDepth] deep: as deep as they are, or
/// as deep as it is at least ([CelTextContent.minHeight]) where that is
/// more (F-317-Q2: 「넘치면 상자가 늘어난다」).
double celTextBoxDepth(
  CelTextContent content, {
  required double lettersDepth,
}) => math.max(lettersDepth, content.minHeight ?? 0);

/// A box [content] at least [height] tall, by one of the two edges its
/// lines stack between — its top or its bottom, or written in columns its
/// right or its left: the other edge stays where it is, as
/// [celTextBoxWidened]'s does.
///
/// A box is never less than its lines, [lettersDepth] tall: a hand that
/// takes an edge past them leaves it there (F-317-Q2: 「끈 높이는 최소치」).
/// It hangs from its anchor, on its top edge — in columns its right — so
/// the FAR edge only changes the height, and the edge the anchor is on
/// ([byLeadingEdge]) carries the anchor the way the lines stack by what
/// the height lost.
///
/// ⛔For a box only: a text that grows has no box to be tall.
CelTextContent celTextBoxDeepened(
  CelTextContent content,
  double height, {
  required double lettersDepth,
  required bool byLeadingEdge,
}) {
  if (content.wrapWidth == null) {
    throw ArgumentError.value(content, 'content', 'has no box to deepen');
  }
  final before = celTextBoxDepth(content, lettersDepth: lettersDepth);
  final after = math.max(math.max(height, lettersDepth), celTextMinWrapWidth);
  if (!byLeadingEdge) {
    return content.copyWith(minHeight: after);
  }
  final way = celTextStackingWay(content);
  final along = before - after;
  return content.copyWith(
    minHeight: after,
    anchor: CanvasPoint(
      x: content.anchor.x + along * way.dx,
      y: content.anchor.y + along * way.dy,
    ),
  );
}
