import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/brush_settings.dart';
import 'brush_stroke_preview_cache.dart';

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

  @override
  State<BrushStrokePreview> createState() => _BrushStrokePreviewState();
}

class _BrushStrokePreviewState extends State<BrushStrokePreview> {
  /// OUR clone of the cache's image (the cache may evict and dispose its
  /// own handle any time).
  ui.Image? _image;
  BrushSettings? _imageSettings;
  int _imageWidth = 0;
  int _imageHeight = 0;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _adopt(ui.Image image, BrushSettings settings, int width, int height) {
    _image?.dispose();
    _image = image.clone();
    _imageSettings = settings;
    _imageWidth = width;
    _imageHeight = height;
  }

  void _resolve(int rasterWidth, int rasterHeight) {
    final settings = widget.settings;
    if (_image != null &&
        _imageSettings == settings &&
        _imageWidth == rasterWidth &&
        _imageHeight == rasterHeight) {
      return;
    }
    final cached = BrushStrokePreviewCache.instance.imageFor(
      settings,
      rasterWidth,
      rasterHeight,
    );
    if (cached != null) {
      _adopt(cached, settings, rasterWidth, rasterHeight);
      return;
    }
    BrushStrokePreviewCache.instance
        .ensure(settings, rasterWidth, rasterHeight)
        .then((image) {
          // Re-check against the LIVE widget: the row may have moved to
          // another preset (or size) while the raster was in flight.
          if (!mounted ||
              widget.settings != settings ||
              (_imageSettings == widget.settings &&
                  _imageWidth == rasterWidth &&
                  _imageHeight == rasterHeight)) {
            return;
          }
          setState(() => _adopt(image, settings, rasterWidth, rasterHeight));
        });
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
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
        // Raster at physical resolution so hidpi rows stay crisp.
        final rasterWidth = (width * devicePixelRatio).round();
        final rasterHeight = (height * devicePixelRatio).round();
        _resolve(rasterWidth, rasterHeight);
        final image = _image;
        if (image == null ||
            _imageSettings != widget.settings ||
            _imageWidth != rasterWidth ||
            _imageHeight != rasterHeight) {
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
          image: image,
          width: width.toDouble(),
          height: height.toDouble(),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          color: Theme.of(context).colorScheme.onSurface,
          colorBlendMode: BlendMode.srcIn,
        );
      },
    );
  }
}
