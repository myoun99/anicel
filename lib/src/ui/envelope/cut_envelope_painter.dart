import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/contain_rect.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/envelope/cut_envelope_form.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../../models/sheet_paint_layer.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../sheet_painting.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

/// Paints a cut envelope. The panel and every export share it, so what is
/// on screen IS the page — the timesheet's rule.
class CutEnvelopePainter extends CustomPainter with RepaintOnProps {
  const CutEnvelopePainter({
    required this.layout,
    required this.source,
    required this.face,
    this.layers,
    this.viewport,
    this.effectiveRatio = 1.0,
    this.imageFor,
    this.inkImageFor,
    this.inkKeyFor,
    this.liveInkKeys = const {},
    // The ink store: a landed stroke (or an async-composed display image)
    // must repaint the sheet even though none of the compared fields
    // changed.
    super.repaint,
  });

  final CutEnvelopeLayout layout;
  final CutEnvelopeSource source;

  /// The app's face (`appFaceOf`) the envelope's words are set in — the
  /// panel's and the export window's ambient style. 🗣️유저 2026-09-24
  /// (documents-in-which-face-Q1: 「둘다 앱글꼴로 통일」): the envelope
  /// named no face and printed in the OS's.
  final TextStyle face;

  /// Which strata to draw; null draws all four (the panel, and any export
  /// that wants one flat image).
  final Set<SheetPaintLayer>? layers;

  /// The panel's pan/zoom: document space IS paper space and this places
  /// it, exactly like the timesheet and conte painters. Null keeps the
  /// fit-to-size behaviour the exports use, where the canvas already IS
  /// the paper.
  final CanvasViewport? viewport;

  /// The view's DPR — the SAME one the host snapped with, so
  /// [applyViewportTransform]'s own snap is a no-op here rather than a
  /// second, coarser rounding.
  final double effectiveRatio;

  /// Resolves a media asset path to a decoded image (logo, 도장).
  final ui.Image? Function(String assetPath)? imageFor;

  /// The ink surface for a box.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// The ink key a box's strokes live under.
  final BrushFrameKey Function(String boxId)? inkKeyFor;

  /// Keys a LIVE input window is already showing: the painter skips them so
  /// translucent ink never composites twice. Everything else is drawn here
  /// — which is the only reason ink is visible at all in the boxes too
  /// small (or too far off screen) to mount a window.
  final Set<BrushFrameKey> liveInkKeys;

  bool _draws(SheetPaintLayer layer) =>
      layers == null || layers!.contains(layer);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    enterSheetPaperSpace(canvas, size, (
      viewport: viewport,
      devicePixelRatio: effectiveRatio,
      paper: Size(layout.paperWidth, layout.paperHeight),
    ));
    if (_draws(SheetPaintLayer.paper)) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, layout.paperWidth, layout.paperHeight),
        Paint()..color = Color(layout.form.paperArgb),
      );
    }

    final ink = Color(layout.form.inkArgb);
    if (_draws(SheetPaintLayer.form)) {
      _paintForm(canvas, ink);
    }
    if (_draws(SheetPaintLayer.content)) {
      _paintContent(canvas);
    }
    if (_draws(SheetPaintLayer.ink)) {
      _paintInk(canvas);
    }
    canvas.restore();
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

  /// The handwriting, above everything the form prints (it was written on
  /// the finished sheet — pen over paper).
  ///
  /// A box shows the TOP-LEFT slice of the shared ink surface, sized by
  /// [CutEnvelopeLayout.inkSurfaceScale] rather than by the image, and
  /// clipped to itself so a stroke can never bleed into the next cell.
  void _paintInk(Canvas canvas) {
    final keyFor = inkKeyFor;
    final imageFor = inkImageFor;
    if (keyFor == null || imageFor == null) {
      return;
    }
    final surfaceScale = layout.inkSurfaceScale;
    for (final placed in layout.placedBoxes) {
      if (!placed.box.takesInk) {
        continue;
      }
      final key = keyFor(placed.box.id);
      if (liveInkKeys.contains(key)) {
        continue;
      }
      final image = imageFor(key);
      if (image == null) {
        continue;
      }
      final boxRect = Rect.fromLTWH(
        placed.x,
        placed.y,
        placed.width,
        placed.height,
      );
      paintSheetInkWindow(canvas, image, boxRect, surfaceScale);
    }
  }

  void _paintImage(Canvas canvas, ui.Image image, PlacedEnvelopeBox placed) {
    final source = Size(image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      Offset.zero & source,
      containRect(
        source,
        Rect.fromLTWH(placed.x, placed.y, placed.width, placed.height),
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
        style: face.copyWith(
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
  Object get props => (
    layout.form,
    layout.paperWidth,
    layout.paperHeight,
    source,
    face,
    ByIdentity(layers),
    viewport,
    effectiveRatio,
    // Mounting a window HIDES that box's baked ink here; unmounting shows
    // it again. Miss this and a stroke stays doubled (or missing) until
    // something else happens to repaint.
    BySet(liveInkKeys),
  );
}
