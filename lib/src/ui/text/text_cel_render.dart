import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/canvas_size.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/text_cel_style.dart';
import '../conte/conte_fonts.dart';

/// ONE canvas-text implementation for both surfaces (R5, ⓣ): the TEXT
/// LAYER bakes it into a cel and the SE NAME TAG draws it live over the
/// picture. Engine text through the bundled conte faces (registered at
/// startup), the same bytes the PDF path embeds, so screen/export can
/// never disagree on a glyph.
///
/// Layout: hard newlines only (no auto-wrap in v1); [TextCelStyle.align]
/// spreads lines around the anchor's x, the first line's TOP sits at the
/// anchor's y. A null anchor centers the block on the canvas.

/// A laid-out text block: where it lands and how to draw it. Built
/// SYNCHRONOUSLY so a CustomPainter can use it (font registration is
/// idempotent and warmed at startup; a cold frame measures in the
/// fallback face and reflows once, the conte panel's rule).
class TextCelLayout {
  TextCelLayout._({
    required this.inkBounds,
    required this.topLeft,
    required TextPainter fill,
    required TextPainter? stroke,
    required this.style,
    required this.pad,
    required this.textSize,
  }) : _fill = fill,
       _stroke = stroke;

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

  final TextPainter _fill;
  final TextPainter? _stroke;

  /// Draws at the layout's canvas coordinates — the caller sets up any
  /// viewport/camera transform first.
  void paint(ui.Canvas canvas) {
    final backgroundColor = style.backgroundColorValue;
    if (backgroundColor != null) {
      // The アフレコ box: text bounds plus breathing room, the SE red-box
      // vocabulary.
      canvas.drawRect(
        ui.Rect.fromLTWH(
          topLeft.dx - pad,
          topLeft.dy - pad,
          textSize.width + pad * 2,
          textSize.height + pad * 2,
        ),
        ui.Paint()..color = backgroundColor,
      );
    }
    // Stroke under fill — the timeline glyph outline recipe (#15: one
    // rule on every surface).
    _stroke?.paint(canvas, topLeft);
    _fill.paint(canvas, topLeft);
  }

  void dispose() {
    _fill.dispose();
    _stroke?.dispose();
  }
}

/// Lays [content] out against [canvas]'s geometry. Cheap enough to call
/// per frame from a painter; dispose the result when done.
TextCelLayout layoutTextCel({
  required TextCelContent content,
  required CanvasSize canvas,
}) {
  final style = content.style;

  TextPainter build(Color color, {Paint? foreground}) => TextPainter(
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

  final fill = build(style.colorValue);
  final outlineColor = style.outlineColorValue;
  final stroke = outlineColor != null && style.outlineWidth > 0
      ? build(
          outlineColor,
          foreground: ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = style.outlineWidth
            ..strokeJoin = ui.StrokeJoin.round
            ..color = outlineColor,
        )
      : null;

  final anchor =
      content.position ??
      ui.Offset(canvas.width / 2, (canvas.height - fill.height) / 2);
  final topLeft = ui.Offset(switch (style.align) {
    TextCelAlign.left => anchor.dx,
    TextCelAlign.center => anchor.dx - fill.width / 2,
    TextCelAlign.right => anchor.dx - fill.width,
  }, anchor.dy);

  final pad = style.backgroundColor == null ? 0.0 : style.fontSize * 0.25;
  final outlineInflate = stroke == null ? 0.0 : style.outlineWidth / 2;
  final ink = ui.Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy,
    fill.width,
    fill.height,
  ).inflate(pad > outlineInflate ? pad : outlineInflate);

  return TextCelLayout._(
    inkBounds: ui.Rect.fromLTRB(
      ink.left.floorToDouble(),
      ink.top.floorToDouble(),
      ink.right.ceilToDouble(),
      ink.bottom.ceilToDouble(),
    ),
    topLeft: topLeft,
    fill: fill,
    stroke: stroke,
    style: style,
    pad: pad,
    textSize: ui.Size(fill.width, fill.height),
  );
}

/// Renders a TEXT CEL to an image over the text's own ink bounds — the
/// projection the bake sweep donates into the cel store, together with
/// the placement rect that says where those pixels sit in canvas space.
/// Rendering the BOUNDS (not the canvas rect) keeps off-canvas anchors
/// alive on the pasteboard like any oversized drop, and keeps a small
/// cut-number stamp from costing a full-canvas raster.
Future<({ui.Image image, ui.Rect placement})> renderTextCelImage({
  required TextCelContent content,
  required CanvasSize canvas,
}) async {
  await ensureConteFontsLoaded();
  final layout = layoutTextCel(content: content, canvas: canvas);
  try {
    final wall = ui.Rect.fromLTRB(
      canvas.pasteboardLeft.toDouble(),
      canvas.pasteboardTop.toDouble(),
      canvas.pasteboardRightExclusive.toDouble(),
      canvas.pasteboardBottomExclusive.toDouble(),
    );
    var bounds = layout.inkBounds.intersect(wall);
    if (bounds.isEmpty) {
      // Fully outside even the pasteboard: an empty 1px placement bakes
      // an empty surface (transparent tiles are skipped).
      bounds = const ui.Rect.fromLTWH(0, 0, 1, 1);
    }

    final recorder = ui.PictureRecorder();
    final paintCanvas = ui.Canvas(recorder);
    paintCanvas.translate(-bounds.left, -bounds.top);
    layout.paint(paintCanvas);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        bounds.width.round(),
        bounds.height.round(),
      );
      return (image: image, placement: bounds);
    } finally {
      picture.dispose();
    }
  } finally {
    layout.dispose();
  }
}
