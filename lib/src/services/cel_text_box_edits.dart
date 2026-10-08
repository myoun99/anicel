import 'dart:math' as math;

import '../models/canvas_point.dart';
import '../models/cel_text.dart';

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

/// [content] with every LENGTH of it [factor] times what it was — the
/// letters' size, their tracking and their outline, and the box's width —
/// about [centre], which stays where it is.
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
) {
  final radians = degrees * math.pi / 180;
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  final dx = content.anchor.x - centre.x;
  final dy = content.anchor.y - centre.y;
  return content.copyWith(
    rotationDegrees: content.rotationDegrees + degrees,
    anchor: CanvasPoint(
      x: centre.x + dx * cos - dy * sin,
      y: centre.y + dx * sin + dy * cos,
    ),
  );
}

/// The way [content]'s letters run, as one step of it on the canvas: along
/// its lines — or, written in columns, DOWN them — turned as the text is.
///
/// What a box's room is measured along ([CelTextContent.wrapWidth]), and so
/// what a hand on the edge that sets it travels along.
({double dx, double dy}) celTextLettersWay(CelTextContent content) {
  final radians = content.rotationDegrees * math.pi / 180;
  return content.vertical
      ? (dx: -math.sin(radians), dy: math.cos(radians))
      : (dx: math.cos(radians), dy: math.sin(radians));
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
