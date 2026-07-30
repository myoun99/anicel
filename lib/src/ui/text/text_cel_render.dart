import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/canvas_size.dart';
import '../../models/text_cel_style.dart';
import '../conte/conte_fonts.dart';

/// Renders one TEXT CEL's parameters to a canvas-sized image (R5, ⓣ) —
/// the projection the bake sweep donates into the cel store. Engine text
/// through the bundled conte faces (registered at startup), the same
/// bytes the PDF path embeds, so screen/export can never disagree on a
/// glyph.
///
/// Layout: hard newlines only (no auto-wrap in v1); [TextCelStyle.align]
/// spreads lines around the anchor's x, the first line's TOP sits at the
/// anchor's y. A null anchor centers the block on the canvas.
Future<ui.Image> renderTextCelImage({
  required TextCelContent content,
  required CanvasSize canvas,
}) async {
  await ensureConteFontsLoaded();
  final style = content.style;

  TextPainter layout(Color color, {Paint? foreground}) {
    final painter = TextPainter(
      text: TextSpan(
        text: content.text,
        style: TextStyle(
          color: foreground == null ? color : null,
          foreground: foreground,
          fontSize: style.fontSize,
          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
          letterSpacing: style.letterSpacing == 0 ? null : style.letterSpacing,
          fontFamily: style.fontFamily,
          // CJK safety on every family choice (platform default included):
          // the bundled faces catch what the primary face misses.
          fontFamilyFallback: const [conteJpFontFamily, conteKrFontFamily],
          height: 1.25,
        ),
      ),
      textAlign: switch (style.align) {
        TextCelAlign.left => TextAlign.left,
        TextCelAlign.center => TextAlign.center,
        TextCelAlign.right => TextAlign.right,
      },
      textDirection: TextDirection.ltr,
    )..layout();
    return painter;
  }

  final fill = layout(style.colorValue);
  final anchor =
      content.position ??
      ui.Offset(canvas.width / 2, (canvas.height - fill.height) / 2);
  final topLeft = ui.Offset(switch (style.align) {
    TextCelAlign.left => anchor.dx,
    TextCelAlign.center => anchor.dx - fill.width / 2,
    TextCelAlign.right => anchor.dx - fill.width,
  }, anchor.dy);

  final recorder = ui.PictureRecorder();
  final paintCanvas = ui.Canvas(recorder);

  final backgroundColor = style.backgroundColorValue;
  if (backgroundColor != null && content.text.isNotEmpty) {
    // The アフレコ box: text bounds plus breathing room, the SE red-box
    // vocabulary.
    final pad = style.fontSize * 0.25;
    paintCanvas.drawRect(
      ui.Rect.fromLTWH(
        topLeft.dx - pad,
        topLeft.dy - pad,
        fill.width + pad * 2,
        fill.height + pad * 2,
      ),
      ui.Paint()..color = backgroundColor,
    );
  }

  final outlineColor = style.outlineColorValue;
  if (outlineColor != null && style.outlineWidth > 0) {
    // Stroke under fill — the timeline glyph outline recipe (#15: one
    // rule on every surface).
    final stroke = layout(
      outlineColor,
      foreground: ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = style.outlineWidth
        ..strokeJoin = ui.StrokeJoin.round
        ..color = outlineColor,
    );
    stroke.paint(paintCanvas, topLeft);
    stroke.dispose();
  }
  fill.paint(paintCanvas, topLeft);
  fill.dispose();

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(canvas.width, canvas.height);
  } finally {
    picture.dispose();
  }
}
