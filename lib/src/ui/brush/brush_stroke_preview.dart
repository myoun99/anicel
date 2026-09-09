import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/brush_settings.dart';
import '../effective_device_pixel_ratio.dart';
import '../theme/text_on_ground.dart';
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
  const BrushStrokePreview({
    super.key,
    required this.settings,
    this.name,
    this.nameGround,
  });

  final BrushSettings settings;

  /// Drawn ON the sample when set — see [_nameOverlay].
  final String? name;

  /// The row's own colour behind the sample, for picking the name's ink.
  /// Required in practice whenever [name] is set; the surface is the
  /// sensible fallback for a caller that has no other ground.
  final Color? nameGround;

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

  /// The name, written on whatever the sample actually put behind it.
  ///
  /// 🚨THE INK IS THE SHARED LAW, NOT A THEME COLOUR (유저 2026-09-10: 「브러시
  /// 이름 텍스트가 너무 안보이는데 공용 뒤 색에따라 색 바꾸는 텍스트 사용한다
  /// 던가? 타임라인 프레임블록에서 쓰던 공용텍스트있잖아」 — and the law's own
  /// file quotes the same instruction from 09-08). It used to be
  /// `onSurfaceVariant`, which is the SAME family the stroke is tinted with,
  /// so a name centred on a thick stroke was writing white on white.
  ///
  /// ⚠️`textOnColor` needs the composited ground, and here that is the row's
  /// colour with `nameGroundCoverage` of stroke ink laid over it.
  ///
  /// 🚨THE NAME RIDES THE STROKE (유저 2026-09-08: 「스트로크가 젤 밑에 중앙에
  /// 깔려있고, 그 위에 오버레이로 **스트로크랑 겹치든 말든** 중앙 살짝아래에
  /// 이름있고」). ⛔The 78%-alpha plate this replaced existed to keep the two
  /// apart, and the user asked for them not to be kept apart.
  ///
  /// ⚠️`Alignment(0, 0.5)` is 「살짝 아래」 read literally: the middle of the
  /// region between the centre (0) and the bottom (1). The band the ink is
  /// measured over is written from these same two facts — see
  /// [brushStrokeNameBandTop].
  Widget _nameOverlay(String name, Color strokeInk, double coverage) {
    final ground = Color.lerp(
      widget.nameGround ?? strokeInk,
      strokeInk,
      coverage,
    )!;
    return Align(
      alignment: const Alignment(0, 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          name,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: textOnColor(ground)),
        ),
      ),
    );
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
        final name = widget.name;
        // 🚨THE PICTURE WE ALREADY HAVE STAYS UP while the next rung bakes
        // (유저 2026-09-10: 「재로드인가 재계산되던데」 — the blank-then-pop was
        // half of what that looked like). It is the same brush drawn at a
        // neighbouring width, so stretching it for a frame or two is a much
        // smaller lie than an empty row. ⛔Only for the same SETTINGS: a row
        // recycled onto another preset must never show the old brush.
        if (sample == null || _sampleSettings != widget.settings) {
          // The sample pops in when its raster lands; the box holds the
          // row's layout meanwhile. ⚠️The NAME does not wait for it — a
          // list of blank rows tells the user nothing about which brush is
          // which, so it writes on the bare row until the ink arrives.
          return SizedBox(
            width: width.toDouble(),
            height: height.toDouble(),
            child: name == null ? null : _nameOverlay(name, strokeInk, 0),
          );
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
        final picture = RawImage(
          image: sample.image,
          width: width.toDouble(),
          height: height.toDouble(),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          color: strokeInk,
          colorBlendMode: BlendMode.srcIn,
        );
        if (name == null) {
          return picture;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            picture,
            _nameOverlay(name, strokeInk, sample.nameGroundCoverage),
          ],
        );
      },
    );
  }
}
