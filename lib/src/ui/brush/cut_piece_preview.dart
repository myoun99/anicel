import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut_piece.dart';

/// Cells per long edge when a held piece is drawn as a preview.
///
/// The same coarse-grid trick the tip previews use, and for the same
/// reason spelled out there: **deliberately synchronous and image-free.**
/// Raw RGBA cannot be handed to a canvas directly — the routes to a
/// `ui.Image` are async — and a preview that decodes would flicker every
/// time the piece or the pose changed. Averaging into cells costs one loop
/// and paints the same frame.
///
/// This is a hint at the artwork, not a rasterisation of it.
const int cutPiecePreviewGrid = 20;

/// Draws [piece] into [target], letterboxed.
///
/// Letterboxed rather than stretched because a cut piece is any width by
/// any height: stretching it into a square box would make the preview lie
/// about the shape, which is the one thing it exists to tell you.
///
/// The FLIPS are honoured — a preview's job is "this is what would land".
/// The scale is not: inside a fixed box a percentage cannot show, and the
/// panel prints the number beside it. (The CURSOR preview is the opposite
/// case and scales, because there the size is the whole point.)
void paintCutPiece(
  Canvas canvas,
  Rect target,
  CutPiece piece, {
  double opacity = 1,
}) {
  final image = piece.flippedImage();
  final width = image.width;
  final height = image.height;
  if (width <= 0 || height <= 0 || target.isEmpty) {
    return;
  }

  // Letterbox: fit the piece's aspect inside the target.
  final scale = math.min(target.width / width, target.height / height);
  final drawWidth = width * scale;
  final drawHeight = height * scale;
  final left = target.left + (target.width - drawWidth) / 2;
  final top = target.top + (target.height - drawHeight) / 2;

  final longSide = math.max(width, height);
  final cols = math.max(1, (width * cutPiecePreviewGrid / longSide).round());
  final rows = math.max(1, (height * cutPiecePreviewGrid / longSide).round());
  final cellWidth = drawWidth / cols;
  final cellHeight = drawHeight / rows;

  final rgba = image.rgba;
  final paint = Paint();
  for (var row = 0; row < rows; row += 1) {
    final startY = row * height ~/ rows;
    final endY = math.max(startY + 1, (row + 1) * height ~/ rows);
    for (var col = 0; col < cols; col += 1) {
      final startX = col * width ~/ cols;
      final endX = math.max(startX + 1, (col + 1) * width ~/ cols);
      var r = 0;
      var g = 0;
      var b = 0;
      var a = 0;
      var count = 0;
      for (var y = startY; y < endY; y += 1) {
        for (var x = startX; x < endX; x += 1) {
          final index = (y * width + x) * 4;
          // Weight colour by alpha so a mostly-transparent cell is not
          // dragged toward whatever colour its stray opaque pixel had.
          final alpha = rgba[index + 3];
          r += rgba[index] * alpha;
          g += rgba[index + 1] * alpha;
          b += rgba[index + 2] * alpha;
          a += alpha;
          count += 1;
        }
      }
      if (count == 0 || a == 0) {
        continue;
      }
      paint.color = Color.fromARGB(
        255,
        (r / a).round().clamp(0, 255),
        (g / a).round().clamp(0, 255),
        (b / a).round().clamp(0, 255),
      ).withValues(alpha: (a / count / 255) * opacity);
      canvas.drawRect(
        Rect.fromLTWH(
          left + col * cellWidth,
          top + row * cellHeight,
          // Half a pixel of overlap, so neighbouring cells do not leave
          // hairlines of background between them.
          cellWidth + 0.5,
          cellHeight + 0.5,
        ),
        paint,
      );
    }
  }
}

/// The held piece, drawn over a checker.
///
/// The checker is not decoration: a cut piece has transparency, and on a
/// plain panel background a transparent region and a white one look
/// identical — which on a transparent-background animation cel is exactly
/// the confusion worth avoiding.
class CutPiecePreview extends StatelessWidget {
  const CutPiecePreview({super.key, required this.piece});

  final CutPiece piece;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey<String>('cut-piece-preview'),
      painter: _CutPiecePreviewPainter(
        piece: piece,
        checkerColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      size: Size.infinite,
    );
  }
}

class _CutPiecePreviewPainter extends CustomPainter {
  const _CutPiecePreviewPainter({
    required this.piece,
    required this.checkerColor,
  });

  final CutPiece piece;
  final Color checkerColor;

  static const double _checkerCell = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final paint = Paint()..color = checkerColor;
    for (var y = 0.0; y < size.height; y += _checkerCell) {
      for (var x = 0.0; x < size.width; x += _checkerCell) {
        if (((x ~/ _checkerCell) + (y ~/ _checkerCell)).isEven) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(x, y, _checkerCell, _checkerCell).intersect(bounds),
          paint,
        );
      }
    }
    paintCutPiece(canvas, bounds, piece);
  }

  @override
  bool shouldRepaint(_CutPiecePreviewPainter oldDelegate) =>
      !identical(oldDelegate.piece, piece) ||
      oldDelegate.checkerColor != checkerColor;
}

/// The held piece under the pointer, at the size and place it would land.
///
/// The brush wears its footprint for the reason written beside it — "so a
/// stroke can be aimed before it starts" — and a stamp needs that more, not
/// less: it puts down a whole drawing rather than a dot, and without this
/// the only way to find out where it goes is to drop it and undo.
///
/// Unlike the panel thumbnail this DOES scale, because the footprint is the
/// question being asked. It is drawn faded and outlined so it reads as a
/// preview rather than as paint that already landed.
class CutPieceCursorOverlay extends StatelessWidget {
  const CutPieceCursorOverlay({
    super.key,
    required this.position,
    required this.viewport,
    required this.piece,
  });

  /// Pointer position in viewport (panel-local) coordinates.
  final Offset position;
  final CanvasViewport viewport;
  final CutPiece piece;

  @override
  Widget build(BuildContext context) {
    final extent = viewport.canvasDeltaToViewportDelta(
      dx: piece.stampWidth.toDouble(),
      dy: piece.stampHeight.toDouble(),
    );
    final width = extent.x.abs();
    final height = extent.y.abs();
    if (width < 1 || height < 1) {
      return const SizedBox.shrink();
    }
    return Positioned(
      // Centre-anchored, matching where a click actually drops it.
      left: position.dx - width / 2,
      top: position.dy - height / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        // Its own layer, so following the pointer is a transform rather
        // than a repaint of the piece.
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey<String>('cut-piece-cursor-overlay'),
            painter: _CutPieceCursorPainter(
              piece: piece,
              outlineColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _CutPieceCursorPainter extends CustomPainter {
  const _CutPieceCursorPainter({
    required this.piece,
    required this.outlineColor,
  });

  final CutPiece piece;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    paintCutPiece(canvas, bounds, piece, opacity: 0.7);
    // A hairline says where the piece ENDS, which matters when it is
    // mostly transparent and its silhouette alone does not show the box.
    canvas.drawRect(
      bounds.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outlineColor.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_CutPieceCursorPainter oldDelegate) =>
      !identical(oldDelegate.piece, piece) ||
      oldDelegate.outlineColor != outlineColor;
}
