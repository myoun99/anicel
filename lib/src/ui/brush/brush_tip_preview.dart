import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/brush_settings.dart';
import '../../models/brush_tip_shape.dart';

/// A small synchronous preview of a brush tip for preset lists.
///
/// Sampled tips render as a coarse grid averaged from the mask's alpha
/// bytes (no async image decode, so it is deterministic in widget tests);
/// parametric tips render their ellipse/square shape with roundness, angle,
/// and a soft outer ring when hardness is low. This is a shape hint, not a
/// rasterizer-accurate rendering.
class BrushTipPreview extends StatelessWidget {
  const BrushTipPreview({super.key, required this.settings});

  final BrushSettings settings;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    // ⛔No `RepaintBoundary`. It looks free and is not, twice over: a
    // boundary is a composited layer of its own, AND it sets
    // `needsCompositing`, which is the only reason the host row's
    // `Container(clipBehavior: Clip.antiAlias)` promotes to a real clip
    // LAYER (`PaintingContext.pushClipPath` gates on exactly that). Two
    // layers per row, per frame, to isolate a painter that redraws only
    // when its preset does.
    //
    // What isolates this now is the panel-level bake — see
    // [StaticRaster], installed on the tab funnel. A boundary INSIDE a
    // bake would be worse than useless: the bake has to paint through
    // whenever it finds one, or the boundary would freeze.
    return CustomPaint(
      painter: _BrushTipPreviewPainter(settings: settings, color: color),
      size: Size.infinite,
    );
  }
}

/// Preview raster resolution for sampled tips (cells per edge). The tip
/// library's inline thumbnails are exactly this wide, so one of those paints
/// at full fidelity here.
const int brushTipPreviewGrid = 16;

/// Draws [alpha] — a `side`x`side` coverage mask, whether a full tip or the
/// library's thumbnail of one — as a coarse grid of cells.
///
/// Deliberately synchronous and image-free: previews appear in list rows and
/// picker grids by the dozen, and an async decode per cell would make the
/// whole panel flicker as it scrolled.
void paintBrushTipAlpha(
  Canvas canvas,
  Size size,
  Uint8List alpha,
  int side,
  Color color,
) {
  final cell = size.shortestSide / brushTipPreviewGrid;
  final texelsPerCell = math.max(1, side ~/ brushTipPreviewGrid);
  final paint = Paint();
  for (var row = 0; row < brushTipPreviewGrid; row += 1) {
    for (var col = 0; col < brushTipPreviewGrid; col += 1) {
      final startX = col * side ~/ brushTipPreviewGrid;
      final startY = row * side ~/ brushTipPreviewGrid;
      var total = 0;
      var count = 0;
      for (var dy = 0; dy < texelsPerCell; dy += 1) {
        final y = startY + dy;
        if (y >= side) {
          break;
        }
        for (var dx = 0; dx < texelsPerCell; dx += 1) {
          final x = startX + dx;
          if (x >= side) {
            break;
          }
          total += alpha[y * side + x];
          count += 1;
        }
      }
      if (count == 0 || total == 0) {
        continue;
      }
      paint.color = color.withValues(alpha: (total / count) / 255);
      canvas.drawRect(
        Rect.fromLTWH(col * cell, row * cell, cell + 0.5, cell + 0.5),
        paint,
      );
    }
  }
}

/// A standalone preview of one coverage mask — the picker's grid cell.
class BrushTipMaskPreview extends StatelessWidget {
  const BrushTipMaskPreview({
    super.key,
    required this.alpha,
    required this.side,
  });

  final Uint8List alpha;
  final int side;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BrushTipMaskPreviewPainter(
        alpha: alpha,
        side: side,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      size: Size.infinite,
    );
  }
}

class _BrushTipMaskPreviewPainter extends CustomPainter {
  const _BrushTipMaskPreviewPainter({
    required this.alpha,
    required this.side,
    required this.color,
  });

  final Uint8List alpha;
  final int side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintBrushTipAlpha(canvas, size, alpha, side, color);

  @override
  bool shouldRepaint(_BrushTipMaskPreviewPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.side != side ||
      !identical(oldDelegate.alpha, alpha);
}

class _BrushTipPreviewPainter extends CustomPainter {
  const _BrushTipPreviewPainter({required this.settings, required this.color});

  final BrushSettings settings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = settings.tipMask;
    if (mask != null) {
      paintBrushTipAlpha(canvas, size, mask.alpha, mask.size, color);
    } else {
      _paintParametric(canvas, size);
    }
  }

  void _paintParametric(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.32;
    final roundness = settings.roundness.clamp(0.05, 1.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Negative because angleDegrees is visual-CCW in y-down coordinates.
    canvas.rotate(-settings.angleDegrees * math.pi / 180);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 2,
      height: radius * 2 * roundness,
    );
    final soft = settings.hardness < 0.85;
    final corePaint = Paint()..color = color.withValues(alpha: soft ? 0.8 : 1);
    if (settings.tipShape == BrushTipShape.square) {
      if (soft) {
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.3));
        canvas.drawRect(rect.deflate(radius * 0.25), corePaint);
      } else {
        canvas.drawRect(rect, corePaint);
      }
    } else {
      if (soft) {
        canvas.drawOval(rect, Paint()..color = color.withValues(alpha: 0.3));
        canvas.drawOval(rect.deflate(radius * 0.25), corePaint);
      } else {
        canvas.drawOval(rect, corePaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrushTipPreviewPainter oldDelegate) {
    return oldDelegate.settings != settings || oldDelegate.color != color;
  }
}
