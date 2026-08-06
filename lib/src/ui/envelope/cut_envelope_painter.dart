import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/envelope/cut_envelope_form.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';

/// Which stratum of the envelope a painter draws.
///
/// Four layers, so a PSD export can hand them over separately and whoever
/// opens it can delete the filled-in values without losing the form (user,
/// 2026-08-06: "자동입력된거 지우고싶을때 못지우니까"). The timesheet
/// already splits FORM from CONTENT for the same reason; the envelope is
/// born with the whole set.
enum EnvelopePaintLayer {
  /// The sheet itself: kraft for a real 봉투, white for a digital one.
  paper,

  /// Printed rules, box outlines and the words the form itself carries.
  form,

  /// Values bound from the project — the layer that has to be erasable.
  content,

  /// Handwriting. Lives in its own store, never in a cel.
  ink,
}

/// Paints a cut envelope. The panel and every export share it, so what is
/// on screen IS the page — the timesheet's rule.
class CutEnvelopePainter extends CustomPainter {
  const CutEnvelopePainter({
    required this.layout,
    required this.source,
    this.layers,
    this.imageFor,
    this.inkImageFor,
    this.inkKeyFor,
  });

  final CutEnvelopeLayout layout;
  final CutEnvelopeSource source;

  /// Which strata to draw; null draws all four (the panel, and any export
  /// that wants one flat image).
  final Set<EnvelopePaintLayer>? layers;

  /// Resolves a media asset path to a decoded image (logo, 도장).
  final ui.Image? Function(String assetPath)? imageFor;

  /// The ink surface for a box.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// The ink key a box's strokes live under.
  final BrushFrameKey Function(String boxId)? inkKeyFor;

  bool _draws(EnvelopePaintLayer layer) =>
      layers == null || layers!.contains(layer);

  @override
  void paint(Canvas canvas, Size size) {
    if (_draws(EnvelopePaintLayer.paper)) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Color(layout.form.paperArgb),
      );
    }

    final ink = Color(layout.form.inkArgb);
    if (_draws(EnvelopePaintLayer.form)) {
      _paintForm(canvas, ink);
    }
    if (_draws(EnvelopePaintLayer.content)) {
      _paintContent(canvas);
    }
    if (_draws(EnvelopePaintLayer.ink)) {
      _paintInk(canvas);
    }
  }

  void _paintForm(Canvas canvas, Color ink) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.1 * layout.textScale).clamp(0.6, 6).toDouble()
      ..color = ink;

    for (final placed in layout.placedBoxes) {
      if (placed.box.bordered) {
        canvas.drawRect(
          Rect.fromLTWH(placed.x, placed.y, placed.width, placed.height),
          stroke,
        );
      }
      final label = placed.box.label;
      if (label != null && label.isNotEmpty) {
        _paintText(
          canvas,
          label,
          placed,
          size: placed.box.labelSize,
          align: placed.box.labelAlign,
          color: ink.withValues(alpha: 0.82),
          top: true,
        );
      }
    }

    for (final rule in layout.form.rules) {
      canvas.drawLine(
        Offset(
          layout.formX + rule.x1 * layout.formWidth,
          layout.formY + rule.y1 * layout.formHeight,
        ),
        Offset(
          layout.formX + rule.x2 * layout.formWidth,
          layout.formY + rule.y2 * layout.formHeight,
        ),
        stroke,
      );
    }
  }

  void _paintContent(Canvas canvas) {
    for (final placed in layout.placedBoxes) {
      switch (placed.box.contentKind) {
        case EnvelopeContentKind.blank:
          continue;
        case EnvelopeContentKind.text:
          final text = resolveEnvelopeText(placed.box.binding!, source);
          if (text == null || text.isEmpty) {
            continue;
          }
          _paintText(
            canvas,
            text,
            placed,
            size: placed.box.contentSize,
            align: placed.box.contentAlign,
            color: const Color(0xFF1A1A18),
          );
        case EnvelopeContentKind.image:
          final path = resolveEnvelopeImage(placed.box.binding!, source);
          final image = path == null ? null : imageFor?.call(path);
          if (image != null) {
            _paintImage(canvas, image, placed);
          }
      }
    }
  }

  void _paintInk(Canvas canvas) {
    final keyFor = inkKeyFor;
    final imageFor = inkImageFor;
    if (keyFor == null || imageFor == null) {
      return;
    }
    for (final placed in layout.placedBoxes) {
      if (!placed.box.takesInk) {
        continue;
      }
      final image = imageFor(keyFor(placed.box.id));
      if (image == null) {
        continue;
      }
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        Rect.fromLTWH(placed.x, placed.y, placed.width, placed.height),
        Paint()..filterQuality = FilterQuality.high,
      );
    }
  }

  /// Fits [image] inside the box without distorting it — a stamp is a
  /// stamp, not a stretched one.
  void _paintImage(Canvas canvas, ui.Image image, PlacedEnvelopeBox placed) {
    final scale = (placed.width / image.width) < (placed.height / image.height)
        ? placed.width / image.width
        : placed.height / image.height;
    final width = image.width * scale;
    final height = image.height * scale;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        placed.x + (placed.width - width) / 2,
        placed.y + (placed.height - height) / 2,
        width,
        height,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _paintText(
    Canvas canvas,
    String text,
    PlacedEnvelopeBox placed, {
    required double size,
    required EnvelopeAlign align,
    required Color color,
    bool top = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size * layout.textScale,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: placed.width - 4 * layout.textScale);

    final inset = 3 * layout.textScale;
    final x = switch (align) {
      EnvelopeAlign.left => placed.x + inset,
      EnvelopeAlign.right => placed.right - inset - painter.width,
      EnvelopeAlign.center => placed.x + (placed.width - painter.width) / 2,
    };
    // Labels hug the top of their cell (the printed head of a column);
    // values sit centred in the space that leaves.
    final y = top
        ? placed.y + inset
        : placed.y + (placed.height - painter.height) / 2;
    painter.paint(canvas, Offset(x, y));
    painter.dispose();
  }

  @override
  bool shouldRepaint(CutEnvelopePainter oldDelegate) =>
      oldDelegate.layout.form != layout.form ||
      oldDelegate.layout.paperWidth != layout.paperWidth ||
      oldDelegate.layout.paperHeight != layout.paperHeight ||
      oldDelegate.source != source ||
      oldDelegate.layers != layers;
}
