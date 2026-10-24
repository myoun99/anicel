import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/straight_rgba_image.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/cut_piece.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

/// Decodes the held piece ONCE and hands the image to [builder], null until
/// the decode lands.
///
/// ⛔It used to draw a 20-cell mosaic of alpha-weighted averages instead —
/// the trick the tip previews use, on the reasoning that raw RGBA cannot
/// reach a canvas synchronously and a decoding preview would flicker. The
/// first half was taken as true (no synchronous bytes→image path was known
/// on Skia then; tiles have had one since 2026-09-17, `pictureOf`); the
/// second half was borrowed from a different problem. Tip previews
/// change with every slider drag, so they cannot afford a decode. **A cut
/// piece changes only when something is cut** — the pose knobs re-order
/// bytes or scale the destination rect, neither of which is a new picture —
/// so one decode per piece is enough, and the artwork shows at full
/// resolution (유저: *"퀄리티 낮추지마. 원본그대로."*).
///
/// Before the decode lands the previews draw NOTHING: show the artwork or
/// show nothing, never a degraded stand-in. The window is one frame in
/// practice — the decode starts when the piece arrives, not when a preview
/// is looked at. (🪦The surface painter's fallback ladder this once pointed
/// at, whose last rung was the same silence, went on 2026-09-17: a canvas
/// tile pictures itself inside the paint. A piece is not a tile — any
/// width by any height, straight bytes — and still decodes here.)
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
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(CutPieceImageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The PIXELS' identity, not the piece's: flipping and scaling produce a
    // new [CutPiece] around the same bytes, and re-decoding for those would
    // throw the image away on every knob nudge. The flips are a canvas
    // transform below and the scale is the destination rect.
    if (oldWidget.piece.image.id != widget.piece.image.id) {
      unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    final piece = widget.piece;
    final request = ++_request;
    // 🚨A piece the engine refused leaves the preview showing what it had —
    // no `onFailed`, because there is nothing here to write down and nothing
    // above waiting on the picture. 🪦Until 2026-09-08 a refusal could not be
    // observed at all: `decodeStraightRgbaImage` was a callback the SDK
    // simply never invoked on failure.
    final image = await decodedImageStillWanted(
      decodeStraightRgbaImage(
        rgba: piece.image.rgba,
        width: piece.image.width,
        height: piece.image.height,
      ),
      wanted: () => mounted && request == _request,
    );
    if (image == null) {
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
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
/// The SCALE is the target's: inside a fixed panel box a percentage cannot
/// show, so the panel prints the number beside it.
///
/// NEAREST sampling, always. The stamp lands through `ResampleMode.pick`
/// (2치 보존) and the canvas draws its own tiles with `FilterQuality.none`,
/// so this is what "원본그대로" means here: magnify to the same hard pixels
/// the commit will put down, rather than a smoothed guess at them.
///
/// ↩️The cursor ghost drew through here too — at its footprint, with the
/// stamp's opacity and composite (F-69), held to its rect (F-243), the
/// layer's paint left to the buffer around it (F-33) — until
/// brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」) moved the stamp
/// ghost to the overlay's CPU pre-blended tiles. What is left draws what is
/// HELD, so it takes neither the stamp's opacity nor its composite.
void paintCutPiece(
  Canvas canvas,
  Rect target,
  CutPiece piece,
  ui.Image? image,
) {
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

  final paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  final source = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  if (!piece.flipHorizontal && !piece.flipVertical) {
    canvas.drawImageRect(image, source, destination, paint);
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
  canvas.drawImageRect(image, source, destination, paint);
  canvas.restore();
}

/// The held piece, drawn on nothing: the panel behind it shows through, as
/// it does behind the brush's stroke in the same box.
///
/// 🗣️유저 2026-10-08 (F-271, 정정): 「흰색말고 투명인채로 하는데, 격자무늬가
/// 아니라 브러시 프리뷰에서 쓰는것마냥 뒤 패널색이 되는것? 즉 뒤가 비치도록.
/// 그런 느낌의 투명」.
///
/// ↩️It stood on the transparency checker until 10-03, then on white (유저
/// 10-03: 「투명인건 맞는데 배경 그냥 흰색으로」) until the correction above.
/// The ground is the box's to give — [ToolSettingsPreview] paints none, and
/// neither preview inside it paints one of its own.
class CutPiecePreview extends StatelessWidget {
  const CutPiecePreview({super.key, required this.piece});

  final CutPiece piece;

  @override
  Widget build(BuildContext context) {
    return CutPieceImageHost(
      piece: piece,
      builder: (context, image) => CustomPaint(
        key: const ValueKey<String>('cut-piece-preview'),
        painter: _CutPiecePreviewPainter(piece: piece, image: image),
        size: Size.infinite,
      ),
    );
  }
}

class _CutPiecePreviewPainter extends CustomPainter with RepaintOnProps {
  const _CutPiecePreviewPainter({required this.piece, required this.image});

  final CutPiece piece;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    // ↩️The app's one transparency checker was painted here (유저 2026-09-09:
    // 「투명이라는 의미의 체크무늬 … 이미있으면 있던거 쓰고」) — and before
    // that a checker of this painter's own — then white (F-271, 10-03). No
    // ground since the user's correction (F-271, 10-08: 「뒤가 비치도록」).
    paintCutPiece(canvas, Offset.zero & size, piece, image);
  }

  @override
  Object get props => (ByIdentity(piece), ByIdentity(image));
}

/// 🚨★★★F-33 — the stamp's AIM: what a click there would press, in CANVAS
/// space — the held piece, where, how strong and in what composite.
///
/// 유저: 「레이어 블렌드모드나 **합성같은게 다** 반영되는」 프리뷰. The
/// cursor overlay could never do that: it is a `Positioned` widget ON TOP of
/// the canvas, so the only thing it can honour is the stamp's own opacity.
/// So the aim travels as data, and the ghost is laid from it as the click's
/// own bytes on the stroke overlay (`_BrushCanvasPanelState._showStampGhost`)
/// — drawn in the active layer's paint as a stroke is, so the layer's
/// opacity, blend and group buffer reach it.
///
/// ↩️It carried the piece's decoded image too — BORROWED, never owned, for
/// [BitmapSurfacePainter] to draw the ghost with on the GPU, in a slot of
/// its own because the overlay's tile slots retire the image they replace —
/// until brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」) moved the stamp
/// ghost to the overlay's CPU pre-blended tiles.
class CutStampPreview {
  const CutStampPreview({
    required this.piece,
    required this.canvasRect,
    required this.opacity,
    required this.blendMode,
  });

  final CutPiece piece;

  /// Where the stamp would land, in CANVAS pixels — the space the artwork
  /// lives in. The click's dab centres on its centre.
  final Rect canvasRect;

  /// The stamp tool's opacity: what a click would press with.
  final double opacity;

  /// The stamp tool's own composite — the other half of "what a click would
  /// press with" (F-69), and what the ghost blends the piece in with.
  /// ⛔The TOOL's, not the layer's: the layer's paint goes on over the ghost
  /// once, as over any of the layer's tiles, and must not go on twice (F-33).
  ///
  /// 🚨Kept in [operator ==] on purpose: a blend picked while the pointer
  /// rests (a blend action, I-31) moves nothing else, and only a changed
  /// value re-lays the ghost.
  final BrushBlendMode blendMode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutStampPreview &&
          identical(other.piece, piece) &&
          other.canvasRect == canvasRect &&
          other.opacity == opacity &&
          other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(
    identityHashCode(piece),
    canvasRect,
    opacity,
    blendMode,
  );
}

/// Publishes a [CutStampPreview] into [sink] for as long as it is mounted.
///
/// A WIDGET, so the aim lives exactly as long as the stamp's cursor layer:
/// mounted with the tool it publishes, and unmounted — another tool, no
/// slot — it clears [sink] on the way out, which takes the ghost down.
/// ↩️It was a widget first for the borrowed image's sake: the decoded image
/// belonged to [CutPieceImageHost], and the reference had to go in the same
/// `dispose` that freed it, until brush-fidelity-Q9 took the image out.
///
/// Draws nothing. F-33: a ghost drawn by a widget sits ON TOP of the canvas
/// and cannot be told about the layer it is going onto.
class CutStampPreviewPublisher extends StatefulWidget {
  const CutStampPreviewPublisher({
    super.key,
    required this.sink,
    required this.preview,
  });

  final ValueNotifier<CutStampPreview?> sink;

  /// Null while there is nothing to show (no hover, no piece) — the sink is
  /// cleared rather than left holding the last position.
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
    // ⛔On the way OUT rather than at the next hover: a stamp tool put down
    // takes its ghost with it. Only while the sink still holds what this
    // one published, though: a publisher that took over (a piece arriving
    // swaps the cursor layer's branch) ran its initState before this
    // dispose, and its aim stays. The image's decode used to republish a
    // frame later and hide that order.
    if (widget.sink.value == widget.preview) {
      widget.sink.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
