import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/brush_settings.dart';
import '../../models/brush_tip_entry.dart' show brushTipThumbnailSide;
import '../../models/brush_tip_mask.dart';
import '../../services/brush_tip_thumbnails.dart';
import '../canvas/raster_picture.dart';
import '../repaint_props.dart';
import '../widgets/superellipse_clip.dart';

/// A small synchronous preview of a brush tip for preset lists.
///
/// Sampled tips render as the coarse grid of their picture
/// ([BrushTipMaskPreview]); the analytic tip renders its ellipse with
/// roundness, angle, and a soft outer ring when hardness is low. This is a
/// shape hint, not a rasterizer-accurate rendering.
class BrushTipPreview extends StatelessWidget {
  const BrushTipPreview({super.key, required this.settings, this.well});

  final BrushSettings settings;

  /// The well it fills, whose corners cut it ([BrushTipMaskPreview.well]).
  final RoundedSuperellipseBorder? well;

  @override
  Widget build(BuildContext context) {
    // ⛔No `RepaintBoundary`. It looks free and is not: a boundary is a
    // composited layer of its own, a layer per row, per frame, to isolate a
    // painter that redraws only when its preset does. (It was two while the
    // host row clipped it: a boundary sets `needsCompositing`, which
    // promoted that clip to a real clip LAYER — the well cuts it now,
    // [well].)
    //
    // What isolates it is the library CELL's own boundary (H40,
    // 2026-09-24). The panel-level bake this note used to name never did:
    // the library's body holds its grid's scroll viewport, so it painted
    // through from the start.
    final mask = settings.tipMask;
    if (mask != null) {
      return BrushTipMaskPreview(mask: mask, well: well);
    }
    final color = Theme.of(context).colorScheme.onSurface;
    return CustomPaint(
      painter: _BrushTipPreviewPainter(settings: settings, color: color),
      size: Size.infinite,
    );
  }
}

/// Paints [alpha] — a tip's picture, [brushTipThumbnailSide]² cells, a byte
/// each ([BrushTipThumbnails]) — as a grid of cells, anchored at the top
/// left and [Size.shortestSide] across.
///
/// 🚨ONE CELL A BYTE (tip-coverage-is-a-second-r1-Q1): the picture is
/// already the mask read down by the app's one resampler, so a cell draws
/// its byte. ↩️A grid handed a whole mask averaged it into its cells itself
/// — a box filter of its own, beside that resampler (ARCH-audit-Q7 had
/// joined three such and missed this one).
///
/// Every cell overhangs its right and bottom neighbour by half a logical
/// pixel, so the last row and column reach half a pixel past the grid.
///
/// In a [within] — the well it fills — a cell reaching its corner is the
/// well's shape where the cell lies ([SuperellipseCut.drawRSuperellipseCut]).
///
/// A widget shows this through [RenderBrushTipGrid], which draws it once.
@visibleForTesting
void paintBrushTipGrid(
  Canvas canvas,
  Size size,
  Uint8List alpha,
  Color color, {
  ui.RSuperellipse? within,
}) {
  assert(
    alpha.length == brushTipThumbnailSide * brushTipThumbnailSide,
    'a tip picture of ${alpha.length} bytes',
  );
  final cell = size.shortestSide / brushTipThumbnailSide;
  final paint = Paint();
  for (var row = 0; row < brushTipThumbnailSide; row += 1) {
    for (var col = 0; col < brushTipThumbnailSide; col += 1) {
      final value = alpha[row * brushTipThumbnailSide + col];
      if (value == 0) {
        continue;
      }
      paint.color = color.withValues(alpha: value / 255);
      final at = Rect.fromLTWH(col * cell, row * cell, cell + 0.5, cell + 0.5);
      if (within == null) {
        canvas.drawRect(at, paint);
      } else {
        canvas.drawRSuperellipseCut(within, at, paint);
      }
    }
  }
}

/// A standalone preview of one tip — the picker's grid cell: its picture
/// ([BrushTipThumbnails]), drawn by [paintBrushTipGrid].
class BrushTipMaskPreview extends StatelessWidget {
  /// [mask]'s picture, as it lands — its cell empty till then.
  const BrushTipMaskPreview({
    super.key,
    required BrushTipMask this.mask,
    this.well,
  }) : thumbnail = null;

  /// [thumbnail], a picture a tip's index carries (`BrushTipEntry.thumbnail`).
  const BrushTipMaskPreview.thumbnail(
    Uint8List this.thumbnail, {
    super.key,
    this.well,
  }) : mask = null;

  final BrushTipMask? mask;
  final Uint8List? thumbnail;

  /// The well it fills, whose corners cut it — null where it stands clear
  /// of every corner.
  ///
  /// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2: 「그림 안의
  /// 자르기를 『자르지 않고 그 모양으로 칠하는』 그리기로 다시 짠다」): a well in
  /// a dock does not clip it ([SuperellipseClip]) — the cells are cut as the
  /// grid is drawn. ↩️The well clipped it.
  final RoundedSuperellipseBorder? well;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    Widget grid(Uint8List? alpha) => _BrushTipGrid(
      alpha: alpha ?? _nothing,
      color: color,
      well: well,
    );
    if (thumbnail case final drawn?) {
      return grid(drawn);
    }
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: BrushTipThumbnails.instance.of(mask!),
      builder: (context, alpha, _) => grid(alpha),
    );
  }
}

/// The picture of a tip whose own has not landed: no cell drawn.
final Uint8List _nothing = Uint8List(
  brushTipThumbnailSide * brushTipThumbnailSide,
);

class _BrushTipGrid extends LeafRenderObjectWidget {
  const _BrushTipGrid({
    required this.alpha,
    required this.color,
    required this.well,
  });

  final Uint8List alpha;
  final Color color;
  final RoundedSuperellipseBorder? well;

  BrushTipGridLook _look(BuildContext context) => (
    alpha: alpha,
    color: color,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    well: well?.borderRadius.resolve(Directionality.maybeOf(context)),
  );

  @override
  RenderBrushTipGrid createRenderObject(BuildContext context) =>
      RenderBrushTipGrid(_look(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBrushTipGrid renderObject,
  ) {
    renderObject.look = _look(context);
  }
}

/// What a tip grid's drawing depends on besides its size. The record's `==`
/// compares [alpha] by identity, as `Uint8List` does.
typedef BrushTipGridLook = ({
  Uint8List alpha,
  Color color,
  double devicePixelRatio,
  BorderRadius? well,
});

/// 🚨**A SAMPLED TIP'S GRID IS DRAWN ONCE AND PLACED 1:1 EVERY FRAME**
/// (유저 2026-09-24, `tip-icons-every-frame-Q1`: 「한 번 그린 그림을 쓴다」
/// — 「결과 절대 바뀌면 안되는건 캔버스뿐임 … 제일 가벼운걸 모색바람」).
/// The grid is up to 256 translucent rects, and Impeller on Windows paints
/// the whole window every frame, idle ones included: 360 icons painted as
/// rects cost 254 ms of raster a frame on the real app, placed from a
/// drawing made once 2.5 ms. The drawing is made at the icon's DEVICE size,
/// the half-pixel overhang included, so placing it is a copy; at a whole
/// device pixel what moves is the offscreen blend's rounding, ≤3/255 — a
/// panel, not the canvas. At a fractional one it lands on the nearest pixel.
///
/// ⛔The drawing belongs to the icon, not to a shared store: made on the
/// first paint after its look or size changes, disposed with the icon. A
/// store with a capacity would redraw EVERY icon EVERY frame once more were
/// on screen than it holds.
///
/// 🪦It was painted live for the byte-identity this round gave up: a bake
/// moved ≤2/255 over the grid and ≤19/255 where a box clipped that
/// overhang, and baking the whole library cell still moved 264 pixels
/// (≤9/255) — measured 2026-09-24, before the answer.
///
/// Still deliberately synchronous and decode-free — the drawing is made
/// inside the paint that asks: previews appear in list rows and picker
/// grids by the dozen, and an async decode per cell would make the whole
/// panel flicker as it scrolled.
class RenderBrushTipGrid extends RenderBox {
  RenderBrushTipGrid(this._look);

  BrushTipGridLook _look;
  BrushTipGridLook get look => _look;
  set look(BrushTipGridLook value) {
    if (value == _look) {
      return;
    }
    _look = value;
    _dropDrawing();
    markNeedsPaint();
  }

  ui.Image? _drawing;
  Size? _drawnAt;

  /// The drawing the last paint placed, or null before the first paint and
  /// after the look changed.
  @visibleForTesting
  ui.Image? get debugDrawing => _drawing;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// A hit, as the `CustomPaint` this replaced answered.
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void dispose() {
    _dropDrawing();
    super.dispose();
  }

  void _dropDrawing() {
    _drawing?.dispose();
    _drawing = null;
    _drawnAt = null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      return;
    }
    if (_drawnAt != size) {
      _dropDrawing();
    }
    final canvas = context.canvas;
    final ratio = _look.devicePixelRatio;
    // The last row and column overhang the grid by half a logical pixel.
    final extent = ((size.shortestSide + 0.5) * ratio).ceil();
    final drawing = _drawing ??= _draw(extent);
    if (drawing == null) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      _paintGrid(canvas);
      canvas.restore();
      return;
    }
    _drawnAt = size;
    final pixels = extent.toDouble();
    canvas.drawImageRect(
      drawing,
      Rect.fromLTWH(0, 0, pixels, pixels),
      Rect.fromLTWH(offset.dx, offset.dy, pixels / ratio, pixels / ratio),
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// The grid over this box, cut by its well.
  void _paintGrid(Canvas canvas) => paintBrushTipGrid(
    canvas,
    size,
    _look.alpha,
    _look.color,
    within: _look.well?.toRSuperellipse(Offset.zero & size),
  );

  /// The grid at device resolution, or null when the raster threw — the
  /// icon then paints live, which is always available and always right.
  ///
  /// 🚨A throw let out of a paint blanks every sibling under the same
  /// repaint boundary until something dirties it again (the same trap
  /// `StaticRaster._captureChild` names), so it is reported and painted
  /// through, never raised.
  ui.Image? _draw(int extent) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_look.devicePixelRatio);
    _paintGrid(canvas);
    try {
      return rasterPicture(recorder, extent, extent);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'anicel',
          context: ErrorDescription(
            'drawing a brush tip grid at $size — painting it live',
          ),
        ),
      );
      return null;
    }
  }
}

class _BrushTipPreviewPainter extends CustomPainter with RepaintOnProps {
  const _BrushTipPreviewPainter({required this.settings, required this.color});

  final BrushSettings settings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
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
    // ⛔The square branch went with the brush's tipShape: a brush tip is the
    // analytic ROUND one or an image, so this preview can only draw an oval.
    if (soft) {
      canvas.drawOval(rect, Paint()..color = color.withValues(alpha: 0.3));
      canvas.drawOval(rect.deflate(radius * 0.25), corePaint);
    } else {
      canvas.drawOval(rect, corePaint);
    }
    canvas.restore();
  }

  @override
  Object get props => (settings, color);
}
