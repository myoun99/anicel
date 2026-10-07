import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/canvas_size.dart';
import '../../models/text_cel_style.dart';
import 'canvas_letter_passes.dart';
import 'canvas_letter_style.dart';

/// ONE canvas-text implementation (R5, ⓣ): the SE NAME TAG draws it live
/// over the picture. ↩️The TEXT LAYER baked it into cels until F-154
/// removed the kind — the text tool the user plans for ordinary layers
/// writes with this same machinery. ✅It does, since 2026-10-06: the
/// letters' recipe is `canvasLetterTextStyle`, which a text on a cel
/// (`layoutCelText`) is set with too. Engine text in the app's BUNDLED
/// faces (`AppTypography.bundledFamily`, 유저 2026-09-25: 「글꼴 앱에서 정한거
/// 통일」) — declared in `pubspec.yaml`, so the engine has them from the
/// first frame and a picture prints the same letters on every machine.
/// ↩️A text with no chosen face used to print in the OS's, with the conte's
/// own faces catching CJK behind it.
///
/// Layout: hard newlines only (no auto-wrap in v1); [TextCelStyle.align]
/// spreads lines around the anchor's x, the first line's TOP sits at the
/// anchor's y. A null anchor centers the block on the canvas.

/// A laid-out text block: where it lands and how to draw it. Built
/// SYNCHRONOUSLY so a CustomPainter can use it.
class TextCelLayout {
  TextCelLayout._({
    required this.inkBounds,
    required this.topLeft,
    required CanvasLetterPasses letters,
    required this.style,
    required this.pad,
    required this.textSize,
  }) : _letters = letters;

  /// The block's painted extent in canvas coordinates — text bounds plus
  /// the background box / outline, snapped to whole pixels so a bake's
  /// placement stays a 1:1 integer mapping.
  final ui.Rect inkBounds;

  /// The text block's own top-left (inside [inkBounds]).
  final ui.Offset topLeft;

  final TextCelStyle style;

  /// Background-box padding (zero when the box is off).
  final double pad;

  /// The text block's laid-out size.
  final ui.Size textSize;

  /// The letters, set for drawing — stroke under fill, smooth or hard
  /// (the passes a text on a cel is drawn in too).
  final CanvasLetterPasses _letters;

  /// Draws at the layout's canvas coordinates — the caller sets up any
  /// viewport/camera transform first.
  void paint(ui.Canvas canvas) {
    final background = style.backgroundColor;
    if (background != null) {
      // The アフレコ box: text bounds plus breathing room, the SE red-box
      // vocabulary.
      _letters.paintBoxBehind(
        canvas,
        ui.Rect.fromLTWH(
          topLeft.dx - pad,
          topLeft.dy - pad,
          textSize.width + pad * 2,
          textSize.height + pad * 2,
        ),
        background,
      );
    }
    // ⚠️A letter's size past the ink the layout counts: that box is the
    // lines' own, and a glyph reaches out of its line.
    _letters.paint(
      canvas,
      topLeft,
      within: inkBounds.inflate(style.fontSize),
    );
  }

  void dispose() => _letters.dispose();
}

/// A tag line's pitch, as a multiple of its letters' size.
const double _tagLineHeight = 1.25;

/// Lays [content] out against [canvas]'s geometry. Cheap enough to call
/// per frame from a painter; dispose the result when done.
///
/// [maxWidth] SHRINKS the type until the block fits (the SE name tag's
/// budget — a long line must stay inside the picture instead of running
/// off it). Null keeps the block unbounded, where the author's size is
/// the contract. Shrinking rather than wrapping is
/// deliberate: the tag's anchor puts its single line above a margin, so
/// wrapped lines would flow down off the edge and collide with the row
/// below.
TextCelLayout layoutTextCel({
  required TextCelContent content,
  required CanvasSize canvas,
  double? maxWidth,
}) {
  final style = content.style;

  // The letters' recipe is [canvasLetterTextStyle] — the one a text on a
  // cel is set with too (R9-rest, 2026-10-06).
  TextPainter build({ui.Paint? foreground, double? fontSize}) => TextPainter(
    text: TextSpan(
      text: content.text,
      style: canvasLetterTextStyle(
        style,
        lineHeight: _tagLineHeight,
        fontSize: fontSize,
        foreground: foreground,
      ),
    ),
    textAlign: canvasTextAlign(style.align),
    textDirection: TextDirection.ltr,
  )..layout();

  var fill = build();
  var drawnSize = style.fontSize;
  if (maxWidth != null && maxWidth > 0 && fill.width > maxWidth) {
    // ONE re-measure at the scale that fits — the tag stays a single
    // line, so the stacked rows keep their pitch.
    drawnSize = style.fontSize * (maxWidth / fill.width);
    fill.dispose();
    fill = build(fontSize: drawnSize);
  }
  final textSize = ui.Size(fill.width, fill.height);
  final outlined = canvasLetterOutlinePaint(style) != null;
  // The tag is one run in one style. What was set to measure it is its
  // fill pass, where its letters are smooth — the tag is set every frame.
  final passes = CanvasLetterPasses.of(
    [style],
    (paintOf) => build(fontSize: drawnSize, foreground: paintOf(style)),
    measured: fill,
  );

  final anchor =
      content.position ??
      ui.Offset(canvas.width / 2, (canvas.height - textSize.height) / 2);
  final topLeft = ui.Offset(switch (style.align) {
    TextCelAlign.left => anchor.dx,
    TextCelAlign.center => anchor.dx - textSize.width / 2,
    TextCelAlign.right => anchor.dx - textSize.width,
  }, anchor.dy);

  // The pad follows the DRAWN size, so a shrunk tag keeps its proportions.
  final pad = style.backgroundColor == null ? 0.0 : drawnSize * 0.25;
  final outlineInflate = outlined ? style.outlineWidth / 2 : 0.0;
  final ink = (topLeft & textSize).inflate(
    pad > outlineInflate ? pad : outlineInflate,
  );

  return TextCelLayout._(
    inkBounds: ui.Rect.fromLTRB(
      ink.left.floorToDouble(),
      ink.top.floorToDouble(),
      ink.right.ceilToDouble(),
      ink.bottom.ceilToDouble(),
    ),
    topLeft: topLeft,
    letters: passes,
    style: style,
    pad: pad,
    textSize: textSize,
  );
}
