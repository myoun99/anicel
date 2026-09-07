import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/straight_rgba_image.dart';
import '../../models/cut_piece.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

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
  //
  // 🚨★★★F-33: the LAYER's opacity and blend are NOT applied here, and that
  // is not an omission. When [BitmapSurfacePainter] carries a stamp ghost
  // it reports `drawsDisjointCoverage == false` — the ghost lands over
  // whatever the coordinate already holds — and the stack answers that by
  // assembling the layer into a buffer and putting the layer's paint on
  // the BUFFER (「Null when the buffer carries it, so nothing applies
  // twice」). So the ghost inherits the layer for free, and applying it
  // again here would darken it against every other pixel of the same row.
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
  canvas.scale(
    piece.flipHorizontal ? -1.0 : 1.0,
    piece.flipVertical ? -1.0 : 1.0,
  );
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

class _CutPiecePreviewPainter extends CustomPainter with RepaintOnProps {
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
  Object get props => (ByIdentity(piece), ByIdentity(image), checkerColor);
}

/// 🚨★★★F-33 — the stamp's ghost, told where it lands in CANVAS space.
///
/// 유저: 「레이어 블렌드모드나 **합성같은게 다** 반영되는」 프리뷰. The
/// cursor overlay could never do that: it is a `Positioned` widget ON TOP of
/// the canvas, so the only thing it can honour is the stamp's own opacity.
///
/// What honours the rest is [BitmapSurfacePainter], which draws the active
/// layer INSIDE the composite tree and hands its `layerPaint` — 「the LAYER's
/// own opacity/blend/colour chain」 — to every draw it makes. So the preview
/// travels as data to that painter instead of as a widget above it.
///
/// ⛔THE IMAGE IS BORROWED, NEVER OWNED. It belongs to the held [CutPiece],
/// and the piece outlives any one hover. The overlay's own stamp slot
/// ([ActiveStrokeOverlayModel.setStampOverlay]) RETIRES the image it
/// replaces — handing it a piece's image would dispose the thing the user
/// is still holding. That is why this is a separate slot with its own rule
/// rather than a second caller of that one.
class CutStampPreview {
  const CutStampPreview({
    required this.piece,
    required this.image,
    required this.canvasRect,
    required this.opacity,
  });

  final CutPiece piece;

  /// ⛔Borrowed — see the class doc. Never disposed or retired from here.
  /// NULL until the decode lands ([CutPieceImageHost]) — the preview says
  /// WHERE and HOW STRONG from the first hover frame, and the picture joins
  /// it when it is ready. That is the same nothing the old overlay drew in
  /// that window, and it keeps this value independent of an async step.
  final ui.Image? image;

  /// Where the stamp would land, in CANVAS pixels — the same space the
  /// surface painter draws its tiles in.
  final Rect canvasRect;

  /// The stamp tool's opacity: what a click would press with.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutStampPreview &&
          identical(other.piece, piece) &&
          identical(other.image, image) &&
          other.canvasRect == canvasRect &&
          other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    identityHashCode(piece),
    identityHashCode(image),
    canvasRect,
    opacity,
  );
}

/// Publishes a [CutStampPreview] into [sink] for as long as it is mounted.
///
/// A WIDGET, because the thing it publishes is owned by a widget: the
/// decoded image belongs to [CutPieceImageHost], which disposes it on
/// unmount. Writing the sink from here means the reference is dropped in
/// the same `dispose` that frees the image, so the painter can never hold a
/// disposed one — the whole reason [CutStampPreview] documents its image as
/// borrowed rather than owned.
///
/// Draws nothing. The painter is what draws, and that is the point of F-33:
/// a ghost drawn by a widget sits ON TOP of the canvas and cannot be told
/// about the layer it is going onto.
class CutStampPreviewPublisher extends StatefulWidget {
  const CutStampPreviewPublisher({
    super.key,
    required this.sink,
    required this.preview,
  });

  final ValueNotifier<CutStampPreview?> sink;

  /// Null while there is nothing to show (no hover, no decoded image yet) —
  /// the sink is cleared rather than left holding the last position.
  final CutStampPreview? preview;

  @override
  State<CutStampPreviewPublisher> createState() =>
      _CutStampPreviewPublisherState();
}

class _CutStampPreviewPublisherState extends State<CutStampPreviewPublisher> {
  @override
  void initState() {
    super.initState();
    widget.sink.value = widget.preview;
  }

  @override
  void didUpdateWidget(CutStampPreviewPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sink, widget.sink)) {
      oldWidget.sink.value = null;
    }
    widget.sink.value = widget.preview;
  }

  @override
  void dispose() {
    // ⛔The image goes away with the host above this; the reference must go
    // with it, and it must go on the way OUT rather than at the next hover.
    widget.sink.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
