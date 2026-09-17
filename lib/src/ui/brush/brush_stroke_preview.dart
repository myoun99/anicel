import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/brush_settings.dart';
import '../effective_device_pixel_ratio.dart';
import 'brush_stroke_preview_cache.dart';

/// The raster width LADDER, in logical pixels.
///
/// 🚨A CACHE KEY MUST NOT BE A CONTINUOUS VALUE (유저 2026-09-10: 「패널
/// 스플리터로 조절할때마다 재로드인가 재계산되던데 그런방면 좀 더 효율적으로
/// 가볍게 할수있나?」). The cache is keyed by (settings, width, height) and
/// the width came straight off the row's constraints, so every PIXEL of a
/// splitter drag minted a fresh key for every visible row and queued a fresh
/// isolate raster behind two workers — dragging 200px asked for two hundred
/// rasters per row.
///
/// ⚠️The same prescription has a precedent here: the canvas zoom was a
/// continuous slider and became a LADDER (2026-08-20) for exactly this
/// reason — cache churn, and a verification matrix that has to be finite.
///
/// ⛔ROUNDING UP, never down: the picture is drawn `BoxFit.fill` at the row's
/// true width, so a rung above it is always a DOWNSCALE and stays crisp. A
/// rung below would upscale and blur.
/// ⛔The HEIGHT is NOT laddered. It is the row height, which does not move
/// while the panel is dragged, and rounding it up would stretch the S-curve
/// vertically — the stroke would read thicker than the brush is set to.
const double brushStrokePreviewWidthRung = 32.0;

/// The physical raster width for a row [logicalWidth] wide.
int brushStrokePreviewRasterWidth(
  double logicalWidth,
  double devicePixelRatio,
) {
  final rungs = math.max(1, (logicalWidth / brushStrokePreviewWidthRung).ceil());
  return (rungs * brushStrokePreviewWidthRung * devicePixelRatio).round();
}

/// A small S-curve stroke sample rendered with the preset's settings.
///
/// Dab pixel coverage comes from the shared `brushPixelCoveragesForDab`
/// oracle, so sampled tips, roundness/angle, hardness, dual masks, and
/// paper texture all show up honestly. The brush size is normalized to the
/// row height (a preview, not a 1:1 rendering), a synthetic 0-1-0 pressure
/// arc tapers the stroke when the pressure toggles are on, and placement
/// dynamics (scatter/jitter) are intentionally skipped to keep the preview
/// deterministic.
///
/// Rasterization runs ONCE per (settings, size, DPR) in a background
/// isolate and lands in the app-wide [BrushStrokePreviewCache] as a
/// [ui.Image] (UI-R18 R18-B) — mounting a row costs one `drawImageRect`,
/// never a re-raster, which is what un-jams the brush list's scroll. The
/// image bakes alpha only; the theme color tints it at paint time.
class BrushStrokePreview extends StatefulWidget {
  const BrushStrokePreview({super.key, required this.settings});

  final BrushSettings settings;

  /// 🪦An `overlay` slot stood here — the row's name label, laid over the
  /// sample. F-82 (2026-09-16) gave the name a band of its own under the
  /// stroke (유저: 「이름 공간 따로 할당」), and this was its only caller.

  @override
  State<BrushStrokePreview> createState() => _BrushStrokePreviewState();
}

class _BrushStrokePreviewState extends State<BrushStrokePreview> {
  /// OUR clone of the cache's sample (the cache may evict and dispose its
  /// own handle any time).
  BrushStrokeSample? _sample;
  BrushSettings? _sampleSettings;
  int _sampleWidth = 0;
  int _sampleHeight = 0;

  @override
  void dispose() {
    _sample?.image.dispose();
    super.dispose();
  }

  void _adopt(
    BrushStrokeSample sample,
    BrushSettings settings,
    int width,
    int height,
  ) {
    _sample?.image.dispose();
    _sample = sample.cloneImage();
    _sampleSettings = settings;
    _sampleWidth = width;
    _sampleHeight = height;
  }

  void _resolve(int rasterWidth, int rasterHeight) {
    final settings = widget.settings;
    if (_sample != null &&
        _sampleSettings == settings &&
        _sampleWidth == rasterWidth &&
        _sampleHeight == rasterHeight) {
      return;
    }
    final cached = BrushStrokePreviewCache.instance.sampleFor(
      settings,
      rasterWidth,
      rasterHeight,
    );
    if (cached != null) {
      _adopt(cached, settings, rasterWidth, rasterHeight);
      return;
    }
    unawaited(BrushStrokePreviewCache.instance
        .ensure(settings, rasterWidth, rasterHeight)
        .then((sample) {
          // Re-check against the LIVE widget: the row may have moved to
          // another preset (or size) while the raster was in flight.
          if (!mounted ||
              widget.settings != settings ||
              (_sampleSettings == widget.settings &&
                  _sampleWidth == rasterWidth &&
                  _sampleHeight == rasterHeight)) {
            return;
          }
          setState(() => _adopt(sample, settings, rasterWidth, rasterHeight));
        }));
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = EffectiveDevicePixelRatio.of(context);
    final strokeInk = Theme.of(context).colorScheme.onSurface;
    // ⛔No `RepaintBoundary` here either, for the same reason as
    // [BrushTipPreview]: the row is isolated by the panel-level bake,
    // and a boundary inside a bake forces the bake to paint through.
    // The row is static between preset edits anyway — the raster it
    // shows is cached in `BrushStrokePreviewCache`.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.floor()
            : 160;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight.floor()
            : 28;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }
        // Raster at physical resolution so hidpi rows stay crisp, and on a
        // width LADDER so a splitter drag is not a re-raster per pixel.
        final rasterWidth = brushStrokePreviewRasterWidth(
          width.toDouble(),
          devicePixelRatio,
        );
        final rasterHeight = (height * devicePixelRatio).round();
        _resolve(rasterWidth, rasterHeight);
        final sample = _sample;
        // 🚨THE PICTURE WE ALREADY HAVE STAYS UP while the next rung bakes
        // (유저 2026-09-10: 「재로드인가 재계산되던데」 — the blank-then-pop was
        // half of what that looked like). It is the same brush drawn at a
        // neighbouring width, so stretching it for a frame or two is a much
        // smaller lie than an empty row. ⛔Only for the same SETTINGS: a row
        // recycled onto another preset must never show the old brush.
        if (sample == null || _sampleSettings != widget.settings) {
          // The sample pops in when its raster lands; the box holds the
          // row's layout meanwhile.
          return SizedBox(width: width.toDouble(), height: height.toDouble());
        }
        // ⛔NOT `ColorFiltered`, which is the same tint at a wildly
        // different price. That widget is a `ColorFilterLayer`, and
        // `pushColorFilter` has no `needsCompositing` gate the way the
        // clips do — so it is a GUARANTEED offscreen bind and resolve,
        // once per row, on every frame the app produces. The preset
        // list measured 7.4 ms/frame with four rows visible while
        // nothing on screen was changing; that is 1.85 ms a row, which
        // is render-target-switch money, not drawing money.
        //
        // `RawImage`'s own colour is the identical `ColorFilter.mode`
        // (rendering/image.dart) set on the `drawImageRect` paint, and
        // allocates no layer at all. The premultiplied-white contract
        // the raster is built under (see BrushStrokePreviewCache) is
        // what makes srcIn mean the same thing either way.
        return RawImage(
          image: sample.image,
          width: width.toDouble(),
          height: height.toDouble(),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          color: strokeInk,
          colorBlendMode: BlendMode.srcIn,
        );
      },
    );
  }
}
