import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/straight_rgba_image.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_piece.dart';

/// Decodes the held piece ONCE and hands the image to [builder], null until
/// the decode lands.
///
/// ⛔It used to draw a 20-cell mosaic of alpha-weighted averages instead —
/// the trick the tip previews use, on the reasoning that raw RGBA cannot
/// reach a canvas synchronously and a decoding preview would flicker. The
/// first half is true (there is no synchronous bytes→image path on Skia);
/// the second half was borrowed from a different problem. Tip previews
/// change with every slider drag, so they cannot afford a decode. **A cut
/// piece changes only when something is cut** — the pose knobs re-order
/// bytes or scale the destination rect, neither of which is a new picture —
/// so one decode per piece is enough, and the artwork shows at full
/// resolution (유저: *"퀄리티 낮추지마. 원본그대로."*).
///
/// Before the decode lands the previews draw NOTHING. That is this app's
/// standing answer for "no image yet" (see the surface painter's fallback
/// ladder, whose last rung is silence): show the artwork or show nothing,
/// never a degraded stand-in. The window is one frame in practice — the
/// decode starts when the piece arrives, not when a preview is looked at.
class CutPieceImageHost extends StatefulWidget {
  const CutPieceImageHost({
    super.key,
    required this.piece,
    required this.builder,
  });

  final CutPiece piece;
  final Widget Function(BuildContext context, ui.Image? image) builder;

  @override
  State<CutPieceImageHost> createState() => _CutPieceImageHostState();
}

class _CutPieceImageHostState extends State<CutPieceImageHost> {
  ui.Image? _image;

  /// Bumped per request, so a decode that lands after the piece changed (or
  /// after this went away) disposes its image instead of showing it.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(CutPieceImageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The PIXELS' identity, not the piece's: flipping and scaling produce a
    // new [CutPiece] around the same bytes, and re-decoding for those would
    // throw the image away on every knob nudge. The flips are a canvas
    // transform below and the scale is the destination rect.
    if (oldWidget.piece.image.id != widget.piece.image.id) {
      _decode();
    }
  }

  void _decode() {
    final piece = widget.piece;
    final request = ++_request;
    decodeStraightRgbaImage(
      rgba: piece.image.rgba,
      width: piece.image.width,
      height: piece.image.height,
      onDecoded: (image) {
        if (!mounted || request != _request) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
      },
    );
  }

  @override
  void dispose() {
    _request += 1; // Invalidate an in-flight decode.
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _image);
}

/// Draws [image] (the piece's pixels) into [target], letterboxed, with
/// [piece]'s flips applied.
///
/// Letterboxed rather than stretched because a cut piece is any width by
/// any height: stretching it into a square box would make the preview lie
/// about the shape, which is the one thing it exists to tell you.
///
/// The FLIPS are honoured — a preview's job is "this is what would land".
/// Whether the SCALE is honoured is the caller's business: inside a fixed
/// panel box a percentage cannot show and the panel prints the number
/// beside it, while the cursor preview is the opposite case (there the
/// footprint is the whole question). [opacity] follows the same split: it
/// is the stamp's PRESSURE, so the preview that stands for a landing wants
/// it and the panel thumbnail — which stands for what is HELD — does not.
///
/// NEAREST sampling, always. The stamp lands through `ResampleMode.pick`
/// (2치 보존) and the canvas draws its own tiles with `FilterQuality.none`,
/// so this is what "원본그대로" means here: magnify to the same hard pixels
/// the commit will put down, rather than a smoothed guess at them.
void paintCutPiece(
  Canvas canvas,
  Rect target,
  CutPiece piece,
  ui.Image? image, {
  double opacity = 1,
}) {
  if (image == null || target.isEmpty) {
    return;
  }
  final width = image.width;
  final height = image.height;
  if (width <= 0 || height <= 0) {
    return;
  }

  // Letterbox: fit the piece's aspect inside the target.
  final scale = math.min(target.width / width, target.height / height);
  final drawWidth = width * scale;
  final drawHeight = height * scale;
  final destination = Rect.fromLTWH(
    target.left + (target.width - drawWidth) / 2,
    target.top + (target.height - drawHeight) / 2,
    drawWidth,
    drawHeight,
  );

  // The paint's ALPHA modulates the image — the same one line every other
  // faded image in this app is drawn with (`drawPosedLayerImage`), so a
  // half-strength stamp previews the way a half-strength layer composites.
  final paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false
    ..color = const Color(0xFF000000).withValues(alpha: opacity.clamp(0, 1));
  if (!piece.flipHorizontal && !piece.flipVertical) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      destination,
      paint,
    );
    return;
  }
  // A mirror about the destination's own centre, so the piece stays inside
  // the box it was letterboxed into. Cheaper than re-ordering bytes and, in
  // a preview, exactly as truthful.
  canvas.save();
  canvas.translate(destination.center.dx, destination.center.dy);
  canvas.scale(piece.flipHorizontal ? -1.0 : 1.0, piece.flipVertical ? -1.0 : 1.0);
  canvas.translate(-destination.center.dx, -destination.center.dy);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    destination,
    paint,
  );
  canvas.restore();
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
    return CutPieceImageHost(
      piece: piece,
      builder: (context, image) => CustomPaint(
        key: const ValueKey<String>('cut-piece-preview'),
        painter: _CutPiecePreviewPainter(
          piece: piece,
          image: image,
          checkerColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CutPiecePreviewPainter extends CustomPainter {
  const _CutPiecePreviewPainter({
    required this.piece,
    required this.image,
    required this.checkerColor,
  });

  final CutPiece piece;
  final ui.Image? image;
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
    paintCutPiece(canvas, bounds, piece, image);
  }

  @override
  bool shouldRepaint(_CutPiecePreviewPainter oldDelegate) =>
      !identical(oldDelegate.piece, piece) ||
      !identical(oldDelegate.image, image) ||
      oldDelegate.checkerColor != checkerColor;
}

/// The held piece under the pointer, at the size and place it would land.
///
/// The brush wears its footprint for the reason written beside it — "so a
/// stroke can be aimed before it starts" — and a stamp needs that more, not
/// less: it puts down a whole drawing rather than a dot, and without this
/// the only way to find out where it goes is to drop it and undo.
///
/// Unlike the panel thumbnail this DOES scale, and it wears the stamp's
/// [opacity], because both are the footprint — the question being asked.
///
/// ⛔It still draws the piece and nothing else — no outline, and no fade of
/// its OWN. A constant ghosting was here briefly and the user removed it:
/// *"그냥 심플하게 진짜 그냥 아무것도 안 하고 프리뷰만 띄워."* [opacity] is
/// not that fade coming back: that one was decoration invented here and it
/// LIED, showing a made-up strength for a stamp that would land at full
/// force. This one is the number the tool will actually press with, so
/// honouring it is the same rule that removed the fade — show what would
/// land, and nothing else. Same note as
/// [[tool-settings-panel-convention]] — do not decorate this.
class CutPieceCursorOverlay extends StatelessWidget {
  const CutPieceCursorOverlay({
    super.key,
    required this.position,
    required this.viewport,
    required this.piece,
    this.opacity = 1,
  });

  /// Pointer position in viewport (panel-local) coordinates.
  final Offset position;
  final CanvasViewport viewport;
  final CutPiece piece;

  /// The stamp tool's opacity — what a click would press with.
  final double opacity;

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
          child: CutPieceImageHost(
            piece: piece,
            builder: (context, image) => CustomPaint(
              key: const ValueKey<String>('cut-piece-cursor-overlay'),
              painter: _CutPieceCursorPainter(
                piece: piece,
                image: image,
                opacity: opacity,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _CutPieceCursorPainter extends CustomPainter {
  const _CutPieceCursorPainter({
    required this.piece,
    required this.image,
    required this.opacity,
  });

  final CutPiece piece;
  final ui.Image? image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) =>
      paintCutPiece(canvas, Offset.zero & size, piece, image, opacity: opacity);

  @override
  bool shouldRepaint(_CutPieceCursorPainter oldDelegate) =>
      !identical(oldDelegate.piece, piece) ||
      !identical(oldDelegate.image, image) ||
      oldDelegate.opacity != opacity;
}
